#!/usr/bin/env bash

# region 18) MicroK8s installation
# 1. Check hardware resources
run_cmd "free -h"            "Available memory"
run_cmd "df -h"              "Disk space"
run_cmd "nproc"              "Available CPUs"

# 2. Channel selection based on architecture
ARCH=$(uname -m)             # x86_64 or aarch64 (Jetson)
CHANNEL="1.34/stable"        # default
[[ $ARCH == "aarch64" ]] && CHANNEL="1.34/stable"   # same channel but separated for clarity

info "Installing MicroK8s (channel ${CHANNEL})..."
if run_cmd "snap install microk8s --classic --channel=${CHANNEL}" "MicroK8s installation"; then
  ok  "MicroK8s installed correctly"
else
  err "MicroK8s installation failed"
  exit 1
fi
# endregion 18) MicroK8s installation

# region 19) Non-root user configuration
PAR_USER="${SUDO_USER:-$USER}"
PAR_HOME=$(getent passwd "$PAR_USER" | cut -d: -f6)
info "Adding user '$PAR_USER' to microk8s group..."
debug "Configuring permissions for user $PAR_USER (home: $PAR_HOME)"

run_cmd "usermod -aG microk8s \"$PAR_USER\"" "Adding user to microk8s group"

# Re-execution if necessary with loop prevention control
if [[ $MICROK8S_GROUP_REEXEC -eq 0 ]] && ! id -nG "$PAR_USER" | grep -qw microk8s; then
  info "Re-executing under 'sg microk8s' for permissions..."
  debug "User not yet in the group, running sg microk8s"
  export MICROK8S_GROUP_REEXEC=1
  exec sg microk8s "$0" "${@}"
elif [[ $MICROK8S_GROUP_REEXEC -eq 1 ]]; then
  debug "Re-exec completed, continuing with configuration"
fi

# Kubeconfig setup - different for primary vs secondary nodes
if [[ "${IS_PRIMARY_NODE:-false}" == "true" ]]; then
  info "🏗️  PRIMARY NODE: Setting up kubeconfig..."
  debug "Creating .kube directory for the user"
  run_cmd "mkdir -p \"$PAR_HOME/.kube\"" "Creating .kube directory"

  debug "Exporting kubeconfig"
  run_cmd "microk8s config > \"$PAR_HOME/.kube/config\"" "Kubeconfig export"

  # Rename cluster and context in kubeconfig to match $CLUSTER_NAME
target_cluster_name="${CLUSTER_NAME:-microk8s-cluster}"
  if [[ -n "$target_cluster_name" && "$target_cluster_name" != "microk8s" && "$target_cluster_name" != "microk8s-cluster" ]]; then
    info "Renaming kubeconfig cluster and context to '$target_cluster_name'..."
    sed -i "s|name: microk8s-cluster|name: ${target_cluster_name}|g" "$PAR_HOME/.kube/config"
    sed -i "s|cluster: microk8s-cluster|cluster: ${target_cluster_name}|g" "$PAR_HOME/.kube/config"
    sed -i "s|name: microk8s|name: ${target_cluster_name}|g" "$PAR_HOME/.kube/config"
    sed -i "s|current-context: microk8s|current-context: ${target_cluster_name}|g" "$PAR_HOME/.kube/config"
  fi
elif [[ "${IS_SECONDARY_NODE:-false}" == "true" ]]; then
  info "🔗 SECONDARY NODE: Kubeconfig will be configured after joining cluster"
  debug "Creating .kube directory for the user"
  run_cmd "mkdir -p \"$PAR_HOME/.kube\"" "Creating .kube directory"
  # Kubeconfig will be set up after successful join
fi

# If remote access is enabled, update kubeconfig with the correct IP
# Initialize variables if not set (for secondary nodes)
REMOTE_ACCESS="${REMOTE_ACCESS:-no}"
ACCESS_MODE="${ACCESS_MODE:-lan}"
PUB_IP="${PUB_IP:-}"

if [[ "$REMOTE_ACCESS" == "yes" ]]; then
  info "Updating kubeconfig for remote access..."
  
  # Determine the IP to use in kubeconfig
  KUBECONFIG_IP=""
  if [[ "$ACCESS_MODE" == "public" && -n "$PUB_IP" ]]; then
    # In on-premises scenario, kubeconfig must always use public IP for external clients
    # while internal cluster uses local IP for optimized communication
    KUBECONFIG_IP="$PUB_IP"
    if [[ "$IS_CLOUD_PUBLIC" == "true" ]]; then
      info "Kubeconfig configured for cloud public access: $PUB_IP"
    else
      info "Kubeconfig configured for on-premises public access: $PUB_IP"
      warn "Note: External clients will use $PUB_IP, internal cluster will use local IP"
    fi
  else
    # Use local IP for LAN
    KUBECONFIG_IP=$(echo "$LOC_CIDR" | cut -d/ -f1)
    info "Kubeconfig configured for LAN access: $KUBECONFIG_IP"
  fi
  
  # Update the server URL in kubeconfig
  sed -i "s|server: https://.*:16443|server: https://${KUBECONFIG_IP}:16443|" "$PAR_HOME/.kube/config"
  
  # Verify that the update was successful
  if grep -q "server: https://${KUBECONFIG_IP}:16443" "$PAR_HOME/.kube/config"; then
    ok "Kubeconfig updated with server: https://${KUBECONFIG_IP}:16443"
  else
    warn "Kubeconfig update failed, manual update may be necessary"
  fi
else
  info "Local access: kubeconfig will maintain default configuration"
fi

run_cmd "chown -R \"$PAR_USER\":\"$PAR_USER\" \"$PAR_HOME/.kube\"" "Setting .kube permissions"
run_cmd "chmod 600 \"$PAR_HOME/.kube/config\"" "Setting config permissions (kubectl requires 600)" # TODO: check if this is correct - previous version was 640
ok "kubeconfig ready for '$PAR_USER'"

# Note: kubectl wrapper will be created at the end of setup to avoid conflicts during join verification
# endregion 19) Non-root user configuration

# region 20) Waiting for MicroK8s ready and cluster join
if [[ "${IS_PRIMARY_NODE:-false}" == "true" ]]; then
  info "🏗️  PRIMARY NODE: Waiting for MicroK8s ready..."
  debug "Waiting for MicroK8s ready status (potentially long wait)"
  WAIT_COUNT=0
  until microk8s status --wait-ready &>/dev/null; do
    WAIT_COUNT=$((WAIT_COUNT+1))
    debug "Waiting for MicroK8s ready, attempt $WAIT_COUNT..."
    # Every 6 attempts (30 seconds) perform a diagnostic
    if [ $((WAIT_COUNT % 6)) -eq 0 ]; then
      debug "MicroK8s diagnostic check after 30s of waiting..."
      run_cmd "snap services microk8s" "MicroK8s services status" || true
      run_cmd "systemctl status snap.microk8s.daemon-cluster-agent" "MicroK8s agent status" || true
    fi
    sleep 5
  done
  ok "MicroK8s operational on primary node"
  
elif [[ "${IS_SECONDARY_NODE:-false}" == "true" ]]; then
  info "🔗 SECONDARY NODE: Joining existing cluster..."
  
  # First wait for basic MicroK8s to be ready
  info "Waiting for basic MicroK8s installation to be ready..."
  WAIT_COUNT=0
  until microk8s status --wait-ready &>/dev/null; do
    WAIT_COUNT=$((WAIT_COUNT+1))
    debug "Waiting for MicroK8s basic ready, attempt $WAIT_COUNT..."
    if [ $WAIT_COUNT -gt 24 ]; then  # 2 minutes timeout
      err "MicroK8s basic installation timeout"
      exit 1
    fi
    sleep 5
  done
  ok "MicroK8s basic installation ready"
  
  # Now join the cluster
  # Construct join command based on token format
  if [[ "$JOIN_TOKEN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/[a-zA-Z0-9]+$ ]]; then
    # Old format: IP:PORT/TOKEN - use token directly
    JOIN_COMMAND="microk8s join ${JOIN_TOKEN}"
    info "Joining cluster using token: [REDACTED]"
  else
    # New format: TOKEN/TOKEN or TOKEN/TOKEN/TOKEN - construct with primary IP
    JOIN_COMMAND="microk8s join ${PRIMARY_NODE_IP}:25000/${JOIN_TOKEN}"
    info "Joining cluster using token: ${PRIMARY_NODE_IP}:25000/[REDACTED]"
  fi
  
  if run_cmd "$JOIN_COMMAND" "Joining cluster"; then
    ok "Successfully joined cluster"
  else
    err "Failed to join cluster"
    warn "Please verify:"
    warn "1. Primary node is accessible at $PRIMARY_NODE_IP"
    warn "2. Join token is valid and not expired"
    warn "3. Network connectivity between nodes"
    exit 1
  fi
  
  # Wait for cluster join to complete
  info "Waiting for cluster join to complete..."
  JOIN_WAIT=0
  
  # First, set up a temporary kubeconfig to test the connection
  info "Setting up temporary kubeconfig for join verification..."
  run_cmd "microk8s config > \"$PAR_HOME/.kube/config.tmp\"" "Creating temporary kubeconfig"
  
  # Replace any server endpoint with primary node IP (more robust approach)
  sed -i "s|server: https://[^:]*:16443|server: https://${PRIMARY_NODE_IP}:16443|g" "$PAR_HOME/.kube/config.tmp"
  
  # Debug: show what we're looking for
  CURRENT_HOSTNAME=$(hostname)
  info "Waiting for node '$CURRENT_HOSTNAME' to appear in cluster..."
  
  until microk8s kubectl --kubeconfig="$PAR_HOME/.kube/config.tmp" get nodes 2>/dev/null | grep -q "$CURRENT_HOSTNAME"; do
    JOIN_WAIT=$((JOIN_WAIT+1))
    debug "Waiting for node to appear in cluster, attempt $JOIN_WAIT..."
    
    # Show current nodes every 5 attempts for debugging
    if [ $((JOIN_WAIT % 5)) -eq 0 ]; then
      info "Current nodes in cluster (attempt $JOIN_WAIT):"
      NODES_OUTPUT=$(microk8s kubectl --kubeconfig="$PAR_HOME/.kube/config.tmp" get nodes --no-headers 2>/dev/null)
      if [[ -n "$NODES_OUTPUT" ]]; then
        echo "$NODES_OUTPUT" | while read -r line; do
          NODE_NAME=$(echo "$line" | awk '{print $1}')
          NODE_STATUS=$(echo "$line" | awk '{print $2}')
          info "  - $NODE_NAME ($NODE_STATUS)"
        done
        info "  Looking for: $CURRENT_HOSTNAME"
      else
        warn "Cannot connect to cluster API or no nodes found"
      fi
    fi
    
    if [ $JOIN_WAIT -gt 24 ]; then  # 2 minutes timeout
      warn "Node join verification timeout, but join command succeeded"
      warn "This might be a kubeconfig/connectivity issue, not a join failure"
      
      # Final attempt to show cluster state
      info "Final cluster state check:"
      FINAL_NODES=$(microk8s kubectl --kubeconfig="$PAR_HOME/.kube/config.tmp" get nodes --no-headers 2>/dev/null)
      if [[ -n "$FINAL_NODES" ]]; then
        echo "$FINAL_NODES" | while read -r line; do
          NODE_NAME=$(echo "$line" | awk '{print $1}')
          NODE_STATUS=$(echo "$line" | awk '{print $2}')
          info "  - $NODE_NAME ($NODE_STATUS)"
        done
      else
        warn "Cannot retrieve final cluster state"
      fi
      break
    fi
    sleep 5
  done
  
  # Clean up temporary file
  rm -f "$PAR_HOME/.kube/config.tmp"
  
  # Set up kubeconfig after successful join
  info "Setting up kubeconfig after cluster join..."
  if run_cmd "microk8s config > \"$PAR_HOME/.kube/config\"" "Kubeconfig export after join"; then
    # For secondary nodes, update kubeconfig to point to primary node
    info "Updating kubeconfig server endpoint to primary node..."
    
    # Replace any server endpoint with primary node IP (more robust approach)
    sed -i "s|server: https://[^:]*:16443|server: https://${PRIMARY_NODE_IP}:16443|g" "$PAR_HOME/.kube/config"
    
    # Rename cluster and context in kubeconfig to match $CLUSTER_NAME
    target_cluster_name="${CLUSTER_NAME:-microk8s-cluster}"
    if [[ -n "$target_cluster_name" && "$target_cluster_name" != "microk8s" && "$target_cluster_name" != "microk8s-cluster" ]]; then
      info "Renaming kubeconfig cluster and context to '$target_cluster_name'..."
      sed -i "s|name: microk8s-cluster|name: ${target_cluster_name}|g" "$PAR_HOME/.kube/config"
      sed -i "s|cluster: microk8s-cluster|cluster: ${target_cluster_name}|g" "$PAR_HOME/.kube/config"
      sed -i "s|name: microk8s|name: ${target_cluster_name}|g" "$PAR_HOME/.kube/config"
      sed -i "s|current-context: microk8s|current-context: ${target_cluster_name}|g" "$PAR_HOME/.kube/config"
    fi
    
    ok "Kubeconfig server endpoint updated to primary node"
    
    # Set proper permissions
    run_cmd "chmod 600 \"$PAR_HOME/.kube/config\"" "Setting kubeconfig permissions"
    run_cmd "chown $PAR_USER:$PAR_USER \"$PAR_HOME/.kube/config\"" "Setting kubeconfig ownership"
    
    ok "Kubeconfig configured for secondary node"
  else
    warn "Kubeconfig setup failed, but node joined successfully"
  fi
  
  # Final verification: check if node is actually in the cluster
  info "Final verification: checking if node is in cluster..."
  FINAL_NODES_CHECK=$(microk8s kubectl --kubeconfig="$PAR_HOME/.kube/config" get nodes --no-headers 2>/dev/null)
  
  if echo "$FINAL_NODES_CHECK" | grep -q "$CURRENT_HOSTNAME"; then
    ok "✅ Secondary node '$CURRENT_HOSTNAME' successfully joined cluster and is visible"
    
    # Show final cluster state
    info "Final cluster state:"
    echo "$FINAL_NODES_CHECK" | while read -r line; do
      NODE_NAME=$(echo "$line" | awk '{print $1}')
      NODE_STATUS=$(echo "$line" | awk '{print $2}')
      NODE_ROLES=$(echo "$line" | awk '{print $3}')
      if [[ "$NODE_NAME" == "$CURRENT_HOSTNAME" ]]; then
        ok "  ✅ $NODE_NAME ($NODE_STATUS) $NODE_ROLES <- This node"
      else
        info "  - $NODE_NAME ($NODE_STATUS) $NODE_ROLES"
      fi
    done
  else
    warn "⚠️  Node join completed but node may not be visible in cluster yet"
    warn "This could be due to:"
    warn "1. Network connectivity issues"
    warn "2. Certificate propagation delays"
    warn "3. Kubeconfig configuration issues"
    
    # Show what nodes are visible
    info "Current cluster nodes visible:"
    if [[ -n "$FINAL_NODES_CHECK" ]]; then
      echo "$FINAL_NODES_CHECK" | while read -r line; do
        NODE_NAME=$(echo "$line" | awk '{print $1}')
        NODE_STATUS=$(echo "$line" | awk '{print $2}')
        info "  - $NODE_NAME ($NODE_STATUS)"
      done
      warn "Expected to find: $CURRENT_HOSTNAME"
    else
      warn "Cannot connect to cluster API or no nodes found"
    fi
  fi
fi
# endregion 20) Waiting for MicroK8s ready and cluster join

# region 20.5) Remote access kube-apiserver configuration
# Only configure remote access on primary nodes
# Initialize REMOTE_ACCESS if not set
REMOTE_ACCESS="${REMOTE_ACCESS:-no}"
if [[ "${IS_PRIMARY_NODE:-false}" == "true" && "$REMOTE_ACCESS" == "yes" ]]; then
  info "🏗️  PRIMARY NODE: Configuring kube-apiserver for remote access..."
  
  # kube-apiserver configuration file
  APISERVER_ARGS="/var/snap/microk8s/current/args/kube-apiserver"
  APISERVER_BACKUP="${APISERVER_ARGS}.backup.$(date +%s)"
  
  # Original configuration backup
  if [ -f "$APISERVER_ARGS" ]; then
    cp "$APISERVER_ARGS" "$APISERVER_BACKUP"
    debug "kube-apiserver args backup saved to: $APISERVER_BACKUP"
  fi
  
  # Determine the IP to use for binding
  BIND_IP="0.0.0.0"  # Default: all interfaces
  
  if [[ "$ACCESS_MODE" == "public" && -n "$PUB_IP" ]]; then
    BIND_IP="0.0.0.0"  # In public mode, listen on all interfaces
    info "Public mode: kube-apiserver will listen on all interfaces"
  elif [[ "$ACCESS_MODE" == "lan" ]]; then
    # In LAN mode, listen on all interfaces to allow LAN access
    BIND_IP="0.0.0.0"
    info "LAN mode: kube-apiserver will listen on all LAN interfaces"
  fi
  
  # Check if --bind-address is already configured
  if grep -q "^--bind-address=" "$APISERVER_ARGS" 2>/dev/null; then
    info "Updating existing bind-address configuration..."
    sed -i "s|^--bind-address=.*|--bind-address=${BIND_IP}|" "$APISERVER_ARGS"
  else
    info "Adding bind-address configuration..."
    echo "--bind-address=${BIND_IP}" >> "$APISERVER_ARGS"
  fi
  
  # Add insecure binding configuration if needed (testing only)
  # NOTE: Do not add --insecure-bind-address for security
  
  # Verify that advertise-address is configured correctly
  ADVERTISE_IP=""
  if [[ "$ACCESS_MODE" == "public" && -n "$PUB_IP" ]]; then
    # Differentiate between cloud and on-premises scenarios for optimal configuration
    # If we're in cloud (public IP assigned to machine), use public IP
    # If we're on-premises (public IP on router), use local IP for internal communication
    if [[ "$IS_CLOUD_PUBLIC" == "true" ]]; then
      ADVERTISE_IP="$PUB_IP"
      info "CLOUD scenario: advertise-address set to public IP: $ADVERTISE_IP"
    else
      # ON-PREMISES: use local IP to optimize internal communication with kubernetes service
      ADVERTISE_IP=$(echo "$LOC_CIDR" | cut -d/ -f1)
      warn "ON-PREMISES scenario: advertise-address set to local IP: $ADVERTISE_IP"
      warn "Configuration optimized for NAT/router environments"
      info "External clients will still need to use the public IP: $PUB_IP"
    fi
  else
    # Use local IP for LAN
    ADVERTISE_IP=$(echo "$LOC_CIDR" | cut -d/ -f1)
  fi
  
  if grep -q "^--advertise-address=" "$APISERVER_ARGS" 2>/dev/null; then
    info "Updating advertise-address to: $ADVERTISE_IP"
    sed -i "s|^--advertise-address=.*|--advertise-address=${ADVERTISE_IP}|" "$APISERVER_ARGS"
  else
    info "Adding advertise-address: $ADVERTISE_IP"
    echo "--advertise-address=${ADVERTISE_IP}" >> "$APISERVER_ARGS"
  fi
  
  # Configure secure-port if necessary
  if ! grep -q "^--secure-port=" "$APISERVER_ARGS" 2>/dev/null; then
    echo "--secure-port=16443" >> "$APISERVER_ARGS"
    debug "Configured secure-port=16443"
  fi
  
  ok "kube-apiserver configured for remote access"
  info "Bind address: $BIND_IP"
  info "Advertise address: $ADVERTISE_IP"
  
  # Restart MicroK8s to apply changes
  info "Restarting MicroK8s to apply remote access configuration..."
  
  run_cmd "microk8s stop" "Stop MicroK8s for configuration"
  sleep 5
  run_cmd "microk8s start" "Start MicroK8s with new configuration"
  
  # Wait for MicroK8s to be ready again
  info "Waiting for MicroK8s to be operational with the new configuration..."
  RESTART_WAIT=0
  RESTART_MAX_WAIT=120
  while [ $RESTART_WAIT -lt $RESTART_MAX_WAIT ]; do
    if microk8s status --wait-ready 2>/dev/null; then
      ok "MicroK8s operational with remote access configured"
      break
    fi
    RESTART_WAIT=$((RESTART_WAIT + 10))
    debug "Waiting for MicroK8s ready after reconfiguration... ${RESTART_WAIT}s/${RESTART_MAX_WAIT}s"
    sleep 10
  done
  
  if [ $RESTART_WAIT -ge $RESTART_MAX_WAIT ]; then
    err "MicroK8s did not return ready after reconfiguration"
    warn "Restoring original configuration..."
    if [ -f "$APISERVER_BACKUP" ]; then
      cp "$APISERVER_BACKUP" "$APISERVER_ARGS"
      run_cmd "microk8s stop && sleep 5 && microk8s start" "Restore original configuration"
      err "Remote access disabled due to errors"
    fi
  else
    # Connectivity test
    info "Testing kube-apiserver connectivity..."
    if curl -k -s "https://${ADVERTISE_IP}:16443/version" >/dev/null 2>&1; then
      ok "kube-apiserver responds correctly on ${ADVERTISE_IP}:16443"
    else
      # Different message depending on scenario
      if [[ "$ACCESS_MODE" == "public" && "$IS_CLOUD_PUBLIC" == "false" ]]; then
        info "✓ Internal test via public IP failed (normal in NAT/router scenario)"
        info "  Correct configuration: external clients will use ${ADVERTISE_IP}:16443"
    else
      warn "Connectivity test failed - check firewall and network configuration"
      fi
    fi
    
    # DIFFERENTIATED CONFIGURATION FOR PUBLIC SCENARIO
    if [[ "$ACCESS_MODE" == "public" && -n "$PUB_IP" ]]; then
      if [[ "$IS_ONPREMISES_PUBLIC" == "true" ]]; then
        # ON-PREMISES PUBLIC scenario: CoreDNS must use local IP for internal communication
        info "🏠 ON-PREMISES PUBLIC scenario detected (public IP on router, not on machine)"
        info "Configuring CoreDNS for ON-PREMISES PUBLIC scenario..."
        LOCAL_IP=$(echo "$LOC_CIDR" | cut -d/ -f1)
        info "CoreDNS optimized for internal communication via local IP: $LOCAL_IP"
        info "Advanced configuration for NAT/router environments"
        
        # Patch CoreDNS configmap to use local endpoint and external nameservers
        run_cmd "microk8s kubectl patch configmap coredns -n kube-system --type merge -p '{\"data\":{\"Corefile\":\".:53 {\\n    errors\\n    health {\\n      lameduck 5s\\n    }\\n    ready\\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\\n      pods insecure\\n      fallthrough in-addr.arpa ip6.arpa\\n    }\\n    prometheus :9153\\n    forward . 8.8.8.8 8.8.4.4 1.1.1.1\\n    cache 300\\n    reload\\n    loadbalance\\n}\\n\"}}'" "CoreDNS configuration for on-premises public"
        
        # Restart CoreDNS to apply changes
        run_cmd "microk8s kubectl rollout restart deployment coredns -n kube-system" "CoreDNS restart"
        
        # Wait for CoreDNS to be operational
        info "Waiting for CoreDNS to be operational with new configuration..."
        if run_cmd "microk8s kubectl rollout status deployment coredns -n kube-system --timeout=120s" "Wait for CoreDNS ready"; then
          ok "CoreDNS configured for on-premises public scenario"
          
          # Test DNS resolution
          info "Testing DNS resolution..."
          sleep 10
          if timeout 30 bash -c 'microk8s kubectl run test-dns-onprem --image=busybox:1.28 --rm -i --restart=Never -- nslookup google.com >/dev/null 2>&1'; then
            ok "DNS resolution works in on-premises public scenario ✓"
            info "✅ Optimized configuration:"
            info "   • External clients use: https://${PUB_IP}:16443"
            info "   • Internal DNS: Automatic via kubernetes service"
            info "   • External DNS: Google DNS (8.8.8.8, 8.8.4.4, 1.1.1.1)"
            info "   • Public Ingress: Configured for ${PUB_IP} with port forwarding"
            info "📋 Note: Dual-IP configuration optimized for NAT environments"
          else
            warn "DNS test timeout but configuration applied"
            # Clean up test pod if remaining
            microk8s kubectl delete pod test-dns-onprem 2>/dev/null || true
          fi
        else
          warn "CoreDNS did not return ready, but configuration applied"
        fi
        
      elif [[ "$IS_CLOUD_PUBLIC" == "true" ]]; then
        # CLOUD PUBLIC scenario: standard configuration
        info "☁️ CLOUD PUBLIC scenario detected - standard configuration"
        info "✅ Standard cloud configuration:"
        info "   • kube-apiserver accessible: https://${PUB_IP}:16443"
        info "   • Direct public Ingress: ${PUB_IP}"
        info "   • DNS: Standard Kubernetes configuration"
        ok "kube-apiserver accessible both internally and externally on: ${PUB_IP}:16443"
      fi
    fi
  fi
  
elif [[ "${IS_PRIMARY_NODE:-false}" == "true" ]]; then
  info "🏗️  PRIMARY NODE: Remote access disabled - kube-apiserver will maintain local configuration"
elif [[ "${IS_SECONDARY_NODE:-false}" == "true" ]]; then
  info "🔗 SECONDARY NODE: Remote access configuration managed by primary node"
fi
# endregion 20.5) Remote access kube-apiserver configuration
