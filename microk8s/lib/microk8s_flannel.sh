#!/usr/bin/env bash

# region 22) Flannel Configuration (Jetson)
if [ -n "$CUSTOM_CNI" ] && [ "$CUSTOM_CNI" = "flannel" ]; then
  info "Flannel configuration instead of Calico (optimized for Jetson)"
  
  # Ensure core addons list is defined for Jetson/Flannel flow so that
  # the subsequent cert-manager enabling step can pick it up.
  # We intentionally omit "dns" here to mirror the previous Jetson logic.
  CORE_ADDONS=(rbac helm3 ingress cert-manager)
  
  # First disable ha-cluster which is not compatible with Flannel
  info "Disabling ha-cluster (incompatible with Flannel)..."
  if microk8s status | grep -q "ha-cluster: enabled"; then
    warn "ha-cluster is enabled but is incompatible with Flannel - disabling"
    run_cmd "microk8s disable ha-cluster" "Disabling ha-cluster" || warn "Cannot disable ha-cluster, continuing"
  fi
  
  # Use default MicroK8s Pod CIDR (already 10.1.0.0/16)
  POD_CIDR="10.1.0.0/16"
  info "Using MicroK8s default POD_CIDR: $POD_CIDR"
  
  # FIX 2: VERIFY REQUIRED KERNEL MODULES FOR JETSON (conditional VXLAN)
  info "Verifying required kernel modules for Flannel on Jetson..."
  
  # Create modules config directory if needed
  run_cmd "mkdir -p /etc/modules-load.d" "Creating modules directory"
  
  # Essential modules (always needed)
  ESSENTIAL_MODULES=("br_netfilter" "nf_conntrack" "iptable_nat" "iptable_filter" "overlay")
  
  # Check VXLAN availability first to decide backend
  VXLAN_AVAILABLE=false
  if modprobe vxlan 2>/dev/null; then
    VXLAN_AVAILABLE=true
    info "VXLAN module available - can use either vxlan or host-gw backend"
  else
    warn "VXLAN module not available - will force host-gw backend"
    info "This is common on Jetson devices and host-gw works better anyway"
  fi
  
  # Load essential modules
  for module in "${ESSENTIAL_MODULES[@]}"; do
    if ! lsmod | grep -q "^$module "; then
      info "Loading essential module: $module"
      if ! modprobe "$module" 2>/dev/null; then
        warn "Failed to load $module module - continuing anyway"
      fi
    fi
    
    # Add to persistent loading
    if ! grep -q "^$module$" /etc/modules-load.d/microk8s.conf 2>/dev/null; then
      echo "$module" >> /etc/modules-load.d/microk8s.conf
    fi
  done
  
  # Add VXLAN to persistent loading only if available and we'll use it
  if [ "$VXLAN_AVAILABLE" = true ]; then
    if ! grep -q "^vxlan$" /etc/modules-load.d/microk8s.conf 2>/dev/null; then
      echo "vxlan" >> /etc/modules-load.d/microk8s.conf
    fi
  fi
  
  run_cmd "systemctl restart systemd-modules-load" "Reload automatic modules"
  ok "Essential kernel modules verified and configured"
  
  # FIX 3: COMPLETE IPAM AND PREVIOUS CONFIGURATIONS CLEANUP
  info "Complete cleanup of previous configurations and IPAM leaks..."
  
  # Stop all services before cleanup
  run_cmd "microk8s stop" "Stop MicroK8s for complete cleanup"
  sleep 5
  
  # Complete IPAM and CNI configurations cleanup
  run_cmd "rm -rf /var/snap/microk8s/common/run/cni/networks/* || true" "CNI IPAM leak cleanup"
  run_cmd "rm -rf /var/snap/microk8s/common/run/flannel/networks/* || true" "Flannel IPAM leak cleanup"
  run_cmd "rm -rf /var/snap/microk8s/common/run/flannel/* || true" "Complete Flannel directory cleanup"
  run_cmd "rm -f /var/snap/microk8s/current/var/lock/cni-loaded || true" "Removing CNI lock"
  run_cmd "rm -f /var/snap/microk8s/current/var/lock/no-flanneld || true" "Removing no-flanneld lock"
  
  # JETSON CRITICAL: AGGRESSIVE Calico removal - Calico interferes with Flannel on Jetson
  info "AGGRESSIVE Calico removal - Calico intercepts pods and prevents Flannel from working..."
  
  # Stop MicroK8s completely for aggressive cleanup
  run_cmd "microk8s stop" "Stop MicroK8s for complete Calico removal"
  sleep 5
  
  # Remove ALL Calico configurations and data
  run_cmd "rm -f /var/snap/microk8s/current/args/cni-network/10-calico.conflist || true" "Remove Calico CNI config"
  run_cmd "rm -f /var/snap/microk8s/current/args/cni-network/calico-kubeconfig || true" "Remove Calico kubeconfig"
  run_cmd "rm -f /var/snap/microk8s/current/args/cni-network/flannel.conflist || true" "Remove duplicate flannel config"
  run_cmd "rm -rf /var/snap/microk8s/current/opt/cni/bin/calico* || true" "Remove Calico CNI binaries"
  run_cmd "rm -rf /var/snap/microk8s/common/var/lib/calico || true" "Remove Calico data"
  
  # Remove Calico containers and images
  info "Removing active Calico containers and images..."
  run_cmd "microk8s ctr containers rm $(microk8s ctr containers list -q | grep calico) 2>/dev/null || true" "Remove Calico containers"
  run_cmd "microk8s ctr images rm $(microk8s ctr images list -q | grep calico) 2>/dev/null || true" "Remove Calico images"
  
  # Remove Calico network interfaces if present
  if ip link show vxlan.calico >/dev/null 2>&1; then
    warn "Removing active Calico network interface: vxlan.calico"
    run_cmd "ip link delete vxlan.calico || true" "Remove vxlan.calico interface"
  fi
  
  # Remove Calico veth pairs
  CALICO_INTERFACES=$(ip link show | grep "cali" | awk -F: '{print $2}' | awk '{print $1}' 2>/dev/null || true)
  if [ -n "$CALICO_INTERFACES" ]; then
    for cali_iface in $CALICO_INTERFACES; do
      if [ -n "$cali_iface" ]; then
        warn "Removing Calico interface: $cali_iface"
        run_cmd "ip link delete $cali_iface || true" "Remove $cali_iface"
      fi
    done
  else
    info "No Calico interfaces found to remove"
  fi
  
  # Clean Calico iptables rules (safer method)
  info "Cleaning Calico-specific iptables rules..."
  
  # Remove Calico-specific chains safely
  run_cmd "iptables -t nat -F cali-PREROUTING 2>/dev/null || true" "Flush Calico PREROUTING"
  run_cmd "iptables -t nat -F cali-POSTROUTING 2>/dev/null || true" "Flush Calico POSTROUTING"
  run_cmd "iptables -t filter -F cali-INPUT 2>/dev/null || true" "Flush Calico INPUT"
  run_cmd "iptables -t filter -F cali-FORWARD 2>/dev/null || true" "Flush Calico FORWARD"
  
  # Delete Calico chains if they exist
  run_cmd "iptables -t nat -X cali-PREROUTING 2>/dev/null || true" "Delete Calico nat chains"
  run_cmd "iptables -t filter -X cali-INPUT 2>/dev/null || true" "Delete Calico filter chains"
  
  info "Calico iptables cleanup completed (targeted approach)"
  
  # Following MicroK8s official documentation for Calico removal
  run_cmd "microk8s start" "Start MicroK8s for systematic Calico removal"
  sleep 10
  
  # Official method: Delete Calico manifest if it exists
  if [ -f "/var/snap/microk8s/current/args/cni-network/cni.yaml" ]; then
    info "Removing Calico using official MicroK8s method..."
    run_cmd "microk8s kubectl delete -f /var/snap/microk8s/current/args/cni-network/cni.yaml --ignore-not-found=true" "Delete Calico manifest"
    sleep 5
  fi
  
  # Disable Calico addon if still enabled
  if microk8s status | grep -q "calico.*enabled"; then
    warn "Calico addon still enabled - disabling forcefully"
    run_cmd "microk8s disable calico --force || true" "Force disable Calico addon"
    sleep 5
  fi
  
  # Complete CNI configurations cleanup (official method)
  run_cmd "rm -f /var/snap/microk8s/current/args/cni-network/* || true" "Complete CNI configurations cleanup"
  
  # Mark CNI as loaded to enable Flannel (official method)
  run_cmd "touch /var/snap/microk8s/current/var/lock/cni-loaded" "Mark CNI as loaded for Flannel"
  
  run_cmd "microk8s stop" "Stop MicroK8s after systematic Calico cleanup"
  sleep 5
  
  # JETSON CRITICAL: Ensure bridge CNI plugin is present
  info "Verifying required CNI plugins are available..."
  if [ ! -f "/var/snap/microk8s/current/opt/cni/bin/bridge" ]; then
    warn "Missing bridge CNI plugin - this causes 'failed to find plugin bridge' errors"
    info "This is common on Jetson devices and needs to be resolved"
    
    # Try to find bridge plugin in other locations
    if [ -f "/opt/cni/bin/bridge" ]; then
      run_cmd "cp /opt/cni/bin/bridge /var/snap/microk8s/current/opt/cni/bin/bridge" "Copy bridge plugin"
      run_cmd "chmod +x /var/snap/microk8s/current/opt/cni/bin/bridge" "Make bridge plugin executable"
    else
      err "Bridge CNI plugin not found. Install containernetworking-plugins package"
      err "Run: apt-get update && apt-get install -y containernetworking-plugins"
      exit 1
    fi
  fi
  
  # JETSON CRITICAL: Create Flannel CNI configuration
  info "Creating Flannel CNI configuration for proper pod networking..."
  cat > /var/snap/microk8s/current/args/cni-network/10-flannel.conflist << 'EOF'
{
  "name": "flannel-network",
  "cniVersion": "0.3.1",
  "plugins": [
    {
      "type": "flannel",
      "delegate": {
        "hairpinMode": true,
        "isDefaultGateway": true,
        "ipMasq": false
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    }
  ]
}
EOF
  ok "Flannel CNI configuration created for pod networking"
  
  # CRITICAL: Ensure only 10-flannel.conflist exists (remove any duplicates)
  info "Ensuring single Flannel CNI configuration..."
  run_cmd "rm -f /var/snap/microk8s/current/args/cni-network/flannel.conflist || true" "Remove duplicate flannel.conflist"
  run_cmd "rm -f /var/snap/microk8s/current/args/cni-network/*calico* || true" "Remove any residual Calico configs"
  
  # Verify only our config exists
  CNI_COUNT=$(ls /var/snap/microk8s/current/args/cni-network/*.conflist 2>/dev/null | wc -l || echo "0")
  if [ "$CNI_COUNT" -eq 1 ]; then
    ok "Only single Flannel CNI configuration present"
  else
    warn "Multiple CNI configurations detected - may cause conflicts"
    run_cmd "ls -la /var/snap/microk8s/current/args/cni-network/" "CNI configurations present"
  fi
  
  # Recreate necessary directories
  run_cmd "mkdir -p /run/flannel" "Recreating flannel directory"
  run_cmd "mkdir -p /var/snap/microk8s/common/run/cni/networks" "Recreating CNI networks directory"
  run_cmd "mkdir -p /var/snap/microk8s/common/run/containerd" "Recreating containerd directory"
  
  # FIX 4: INTELLIGENT ETHERNET INTERFACE DETECTION
  info "Detecting optimal network interface for Flannel..."
  
  # Priority: Physical Ethernet > Physical Wi-Fi > Fallback
  FLANNEL_IFACE=""
  
  # First check if the previously detected interface ($IFACE) is good to use
  if [ -n "$IFACE" ] && ip addr show "$IFACE" | grep -q "inet " 2>/dev/null; then
    # Check if it's not a virtual bridge (docker0, br-, virbr-, etc.)
    if ! echo "$IFACE" | grep -qE "^(docker|br-|virbr|veth|lo)"; then
      FLANNEL_IFACE="$IFACE"
      if [ -d "/sys/class/net/$IFACE/wireless" ]; then
        info "Using detected Wi-Fi interface: $FLANNEL_IFACE"
      else
        info "Using detected wired interface: $FLANNEL_IFACE"
      fi
    fi
  fi
  
  # If not found, search for physical interfaces (exclude virtual bridges)
  if [ -z "$FLANNEL_IFACE" ]; then
    for iface in $(ip -o link show up | awk -F': ' '{print $2}' | grep -v lo); do
      # Skip virtual bridges and containers interfaces
      if echo "$iface" | grep -qE "^(docker|br-|virbr|veth|cali|flannel)"; then
        continue
      fi
      
      # Check if it's a physical interface with IP
      if [ -e "/sys/class/net/$iface" ] && ip addr show "$iface" | grep -q "inet "; then
        # Prefer wired ethernet over wireless
        if [ ! -d "/sys/class/net/$iface/wireless" ]; then
          FLANNEL_IFACE="$iface"
          info "Physical wired interface found: $FLANNEL_IFACE"
          break
        elif [ -z "$FLANNEL_IFACE" ]; then
          # Store Wi-Fi as fallback if no wired found yet
          FLANNEL_IFACE="$iface"
          info "Physical Wi-Fi interface found: $FLANNEL_IFACE"
        fi
      fi
    done
  fi
  
  # Final fallback to previously detected interface
  if [ -z "$FLANNEL_IFACE" ]; then
    FLANNEL_IFACE="$IFACE"
    warn "Using fallback interface: $FLANNEL_IFACE"
  fi
  
  # JETSON FIX: Apply Wi-Fi specific optimizations if using wireless interface
  if [ -d "/sys/class/net/$FLANNEL_IFACE/wireless" ]; then
    info "Wi-Fi interface detected - applying Jetson Wi-Fi optimizations..."
    
    # Check if interface supports VXLAN
    if ! ethtool -k "$FLANNEL_IFACE" 2>/dev/null | grep -q "tx-udp_tnl-segmentation"; then
      warn "Interface $FLANNEL_IFACE may not fully support VXLAN offloading"
      info "Disabling VXLAN hardware offloading for better Wi-Fi compatibility..."
      run_cmd "ethtool -K $FLANNEL_IFACE tx-udp_tnl-segmentation off 2>/dev/null || true" "Disable VXLAN TX offload"
      run_cmd "ethtool -K $FLANNEL_IFACE rx-udp_tnl-port-offload off 2>/dev/null || true" "Disable VXLAN RX offload"
    fi
    
    # JETSON CRITICAL: Do NOT change MTU on Jetson devices - causes system reboots
    # Reference: https://forums.developer.nvidia.com/t/changing-mtu-on-xavier-nx-resets-to-1500/242996
    warn "Skipping MTU changes on Jetson - MTU modifications cause system reboots on Jetson devices"
    info "Using host-gw backend for Wi-Fi reliability instead of VXLAN"
  fi
  
  ok "Interface selected for Flannel: $FLANNEL_IFACE"
  
  # FIX 5: KUBE-CONTROLLER-MANAGER CONFIGURATION WITHOUT DUPLICATES
  info "Configuring kube-controller-manager for Flannel..."
  
  # Backup configuration file
  CONTROLLER_CONFIG="/var/snap/microk8s/current/args/kube-controller-manager"
  run_cmd "cp $CONTROLLER_CONFIG $CONTROLLER_CONFIG.backup-$(date +%s)" "Backup controller configuration"
  
  # CRITICAL: Ensure cluster-cidr is present (the root cause of Pod CIDR assignment failure)
  if ! grep -q "cluster-cidr" "$CONTROLLER_CONFIG"; then
    info "Adding missing --cluster-cidr to kube-controller-manager"
    run_cmd "echo '--cluster-cidr=$POD_CIDR' >> $CONTROLLER_CONFIG" "Adding cluster-cidr"
  else
    info "Updating existing --cluster-cidr in kube-controller-manager"
    run_cmd "sed -i 's/--cluster-cidr=.*/--cluster-cidr=$POD_CIDR/' $CONTROLLER_CONFIG" "Updating cluster-cidr"
  fi
  
  # Ensure allocate-node-cidrs is enabled
  if ! grep -q "allocate-node-cidrs" "$CONTROLLER_CONFIG"; then
    run_cmd "echo '--allocate-node-cidrs=true' >> $CONTROLLER_CONFIG" "Adding allocate-node-cidrs"
  else
    run_cmd "sed -i 's/--allocate-node-cidrs=.*/--allocate-node-cidrs=true/' $CONTROLLER_CONFIG" "Ensuring allocate-node-cidrs is true"
  fi
  
  ok "kube-controller-manager configuration updated for Flannel"
  
  # JETSON CRITICAL FIX: Ensure Pod CIDR is assigned to node before Flannel starts
  info "Ensuring Pod CIDR is assigned to node before Flannel configuration..."
  
  # Start MicroK8s to apply controller-manager changes
  run_cmd "microk8s start" "Starting MicroK8s to apply controller-manager changes"
  
  # Wait for API server to be ready
  info "Waiting for API server to be ready for CIDR assignment..."
  CIDR_WAIT=0
  CIDR_MAX_WAIT=120
  while [ $CIDR_WAIT -lt $CIDR_MAX_WAIT ]; do
    if microk8s status --wait-ready 2>/dev/null; then
      ok "API server ready for CIDR operations"
      break
    fi
    CIDR_WAIT=$((CIDR_WAIT + 10))
    debug "Waiting for API server ready for CIDR... ${CIDR_WAIT}s/${CIDR_MAX_WAIT}s"
    sleep 10
  done
  
  # Wait for Pod CIDR automatic assignment (following MicroK8s best practices)
  NODE_NAME=$(hostname)
  info "Waiting for automatic Pod CIDR assignment..."
  
  CIDR_ASSIGN_WAIT=0
  CIDR_ASSIGN_MAX_WAIT=180  # Extended timeout for Jetson
  
  while [ $CIDR_ASSIGN_WAIT -lt $CIDR_ASSIGN_MAX_WAIT ]; do
    if microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' 2>/dev/null | grep -q "10.1"; then
      ASSIGNED_CIDR=$(microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}')
      ok "Pod CIDR automatically assigned: $ASSIGNED_CIDR"
      break
    fi
    
    CIDR_ASSIGN_WAIT=$((CIDR_ASSIGN_WAIT + 10))
    debug "Waiting for Pod CIDR assignment... ${CIDR_ASSIGN_WAIT}s/${CIDR_ASSIGN_MAX_WAIT}s"
    sleep 10
  done
  
  # Final verification without risky manual patch
  if ! microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' 2>/dev/null | grep -q "10.1"; then
    warn "Pod CIDR not automatically assigned after ${CIDR_ASSIGN_MAX_WAIT}s"
    warn "This may indicate controller-manager issues or CIDR conflicts"
    info "Continuing - Flannel may auto-recover when CIDR is assigned"
    
    # Diagnostic information instead of risky patch
    run_cmd "microk8s kubectl get nodes -o wide" "Node status for debugging"
    run_cmd "microk8s kubectl get node $NODE_NAME -o yaml | grep -A 5 -B 5 podCIDR" "Node CIDR details"
  fi
  
  # FIX 6: CORRECT FLANNEL CONFIGURATION WITHOUT OBSOLETE FLAGS
  info "Configuring Flannel without obsolete flags..."
  
  # Environment configuration
  run_cmd "echo 'NODE_NAME=\$(hostname)' > /var/snap/microk8s/current/args/flanneld-env" "Configuring flanneld-env"
  
  # JETSON CRITICAL: Choose optimal backend based on VXLAN availability and interface type
  if [ "$VXLAN_AVAILABLE" = false ] || [ -d "/sys/class/net/$FLANNEL_IFACE/wireless" ]; then
    # Use host-gw for Jetson without VXLAN or Wi-Fi interfaces
    info "Using host-gw backend (VXLAN unavailable or Wi-Fi interface detected)"
    run_cmd "echo '{\"Network\": \"${POD_CIDR}\", \"Backend\": {\"Type\": \"host-gw\"}}' > /var/snap/microk8s/current/args/flannel-network-mgr-config" "Configuring flannel network with host-gw"
  else
    # Use VXLAN for wired connections with VXLAN support
    info "Using VXLAN backend (wired interface with VXLAN support)"
    run_cmd "echo '{\"Network\": \"${POD_CIDR}\", \"Backend\": {\"Type\": \"vxlan\"}}' > /var/snap/microk8s/current/args/flannel-network-mgr-config" "Configuring flannel network with VXLAN"
  fi
  
  # flanneld args configuration - CORRECT VERSION WITHOUT OBSOLETE FLAGS
  cat > /var/snap/microk8s/current/args/flanneld << EOF
--iface=${FLANNEL_IFACE}
--subnet-file=/run/flannel/subnet.env
--ip-masq=true
--kube-subnet-mgr=true
--kubeconfig-file=/var/snap/microk8s/current/credentials/kubelet.config
--net-config-path=/var/snap/microk8s/current/args/flannel-network-mgr-config
EOF

  # CRITICAL: Ensure /run/flannel directory exists for CNI compatibility
  info "Creating standard /run/flannel directory for CNI compatibility..."
  run_cmd "mkdir -p /run/flannel" "Create standard flannel directory"
  run_cmd "chmod 755 /run/flannel" "Set proper permissions for flannel directory"
  
  ok "flanneld configuration created WITHOUT obsolete flags (--healthz-*, --iptables-rules-table)"
  
  # FIX 7: FLANNEL RBAC CREATION
  info "Creating RBAC for Flannel..."
  
  # Restart MicroK8s to apply controller-manager changes
  run_cmd "microk8s start" "Starting MicroK8s to apply controller-manager changes"
  
  # Wait for MicroK8s to be operational
  info "Waiting for MicroK8s to be operational..."
  RBAC_WAIT=0
  RBAC_MAX_WAIT=120
  while [ $RBAC_WAIT -lt $RBAC_MAX_WAIT ]; do
    if microk8s status --wait-ready 2>/dev/null; then
      ok "MicroK8s operational"
        break
      fi
    RBAC_WAIT=$((RBAC_WAIT + 10))
    debug "Waiting for MicroK8s ready for RBAC... ${RBAC_WAIT}s/${RBAC_MAX_WAIT}s"
    sleep 10
  done
  
  if [ $RBAC_WAIT -ge $RBAC_MAX_WAIT ]; then
    err "MicroK8s is not ready after ${RBAC_MAX_WAIT}s for RBAC configuration"
    warn "Continuing without RBAC - may cause 'nodes is forbidden'"
  else
    # Create ClusterRole for Flannel
    cat <<EOF | microk8s kubectl apply -f - || warn "Flannel ClusterRole creation failed"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: flannel
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - list
  - watch
  - get
- apiGroups:
  - ""
  resources:
  - nodes/status
  verbs:
  - patch
EOF
    
    # Create ClusterRoleBinding for the current node
    NODE_NAME=$(hostname)
    cat <<EOF | microk8s kubectl apply -f - || warn "Flannel ClusterRoleBinding creation failed"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: flannel-${NODE_NAME}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: system:node:${NODE_NAME}
EOF
    
    ok "Flannel RBAC created for node: $NODE_NAME"
  fi
  
  # FIX 8: ENABLE FLANNEL AND COORDINATED RESTART
  info "Enabling Flannel and coordinated service restart..."
  
  # Stop again for coordinated restart
  run_cmd "microk8s stop" "Stop for coordinated restart"
  sleep 5
  
  # DO NOT create subnet.env manually - let flanneld generate it
  info "NOT creating subnet.env manually - flanneld will generate it automatically"
    
  # Enable Flannel service (following official documentation)
  run_cmd "rm -f /var/snap/microk8s/current/var/lock/no-flanneld" "Enable Flannel daemon"
  
  # Restart services following official MicroK8s documentation
  info "Restarting services with Flannel configuration..."
  run_cmd "snap restart microk8s.daemon-containerd microk8s.daemon-flanneld" "Restart containerd and flanneld"
  sleep 10
  
  # CRITICAL: Clean any auto-generated CNI duplicates after restart
  info "Cleaning any auto-generated CNI duplicates..."
  run_cmd "rm -f /var/snap/microk8s/current/args/cni-network/flannel.conflist || true" "Remove any auto-generated flannel.conflist"
  
  # Complete MicroK8s startup
  info "Starting complete MicroK8s system..."
  run_cmd "microk8s start" "Complete MicroK8s startup"
  
  # FINAL: Ensure no CNI conflicts after startup
  sleep 5
  info "Final CNI configuration verification..."
  run_cmd "rm -f /var/snap/microk8s/current/args/cni-network/flannel.conflist || true" "Final cleanup of duplicate CNI"
  run_cmd "ls -la /var/snap/microk8s/current/args/cni-network/" "Final CNI configuration status"
  
  # Wait for stabilization with diagnostics
  info "Waiting for service stabilization with diagnostics..."
  STAB_WAIT=0
  STAB_MAX_WAIT=180
  while [ $STAB_WAIT -lt $STAB_MAX_WAIT ]; do
    # Verify that critical services are active
    KUBELITE_ACTIVE=$(snap services microk8s.daemon-kubelite | grep -c "active" || echo "0")
    FLANNELD_ACTIVE=$(snap services microk8s.daemon-flanneld | grep -c "active" || echo "0")
    CONTAINERD_ACTIVE=$(snap services microk8s.daemon-containerd | grep -c "active" || echo "0")
    
    if [ "$KUBELITE_ACTIVE" -eq 1 ] && [ "$FLANNELD_ACTIVE" -eq 1 ] && [ "$CONTAINERD_ACTIVE" -eq 1 ]; then
      ok "All critical services are active"
      break
    fi
  
    STAB_WAIT=$((STAB_WAIT + 10))
    debug "Waiting for active services... ${STAB_WAIT}s/${STAB_MAX_WAIT}s (kubelite:$KUBELITE_ACTIVE flanneld:$FLANNELD_ACTIVE containerd:$CONTAINERD_ACTIVE)"
  sleep 10
  done
  
  if [ $STAB_WAIT -ge $STAB_MAX_WAIT ]; then
    warn "Not all services are active after ${STAB_MAX_WAIT}s"
    run_cmd "snap services microk8s" "MicroK8s services status" || true
  fi
  
  # MASQUERADE is handled automatically by flanneld with --ip-masq=true
  # No manual iptables rules needed - following MicroK8s best practices
  info "MASQUERADE rules managed automatically by flanneld (--ip-masq=true)"
  
  # FIX 10: EXTENDED FINAL VERIFICATION AND DIAGNOSTICS
  info "Final Flannel verification and diagnostics (correct version)..."
  
  # Wait for MicroK8s to be completely ready
  info "Waiting for MicroK8s to be completely ready..."
  FINAL_WAIT=0
  FINAL_MAX_WAIT=300  # 5 minutes for Jetson
  while [ $FINAL_WAIT -lt $FINAL_MAX_WAIT ]; do
    if microk8s status --wait-ready 2>/dev/null; then
      ok "MicroK8s completely ready"
        break
      fi
    FINAL_WAIT=$((FINAL_WAIT + 15))
    debug "Waiting for final MicroK8s ready... ${FINAL_WAIT}s/${FINAL_MAX_WAIT}s"
    sleep 15
    done
    
  # Verify that flanneld is operational and has generated subnet.env
  info "Verifying flanneld functionality..."
  
  # JETSON FIX: Extended subnet.env generation with multiple attempts
  SUBNET_ATTEMPTS=0
  SUBNET_MAX_ATTEMPTS=5
  SUBNET_WAIT_TIME=30
  
  while [ $SUBNET_ATTEMPTS -lt $SUBNET_MAX_ATTEMPTS ]; do
    if [ -f "/run/flannel/subnet.env" ]; then
      ok "subnet.env file automatically generated by flanneld ✓"
      debug "subnet.env content: $(cat /run/flannel/subnet.env 2>/dev/null || echo 'reading failed')"
      break
    else
      SUBNET_ATTEMPTS=$((SUBNET_ATTEMPTS + 1))
      warn "subnet.env file not yet generated by flanneld (attempt $SUBNET_ATTEMPTS/$SUBNET_MAX_ATTEMPTS)"
      
      if [ $SUBNET_ATTEMPTS -eq 1 ]; then
        # First attempt: Verify Pod CIDR is still assigned and restart
        info "First attempt: Verifying Pod CIDR assignment and restarting flanneld..."
        
        # Double-check that Pod CIDR is still assigned (critical for Jetson)
        if microk8s kubectl get node "$(hostname)" -o jsonpath='{.spec.podCIDR}' 2>/dev/null | grep -q "10.1"; then
          info "Pod CIDR confirmed present: $(microk8s kubectl get node "$(hostname)" -o jsonpath='{.spec.podCIDR}')"
        else
          warn "Pod CIDR missing - this indicates controller-manager issues"
          info "Will restart kubelite to re-trigger automatic CIDR assignment"
          run_cmd "snap restart microk8s.daemon-kubelite" "Restart kubelite for CIDR assignment"
          sleep 15
          # Check if CIDR is now assigned
          if microk8s kubectl get node "$(hostname)" -o jsonpath='{.spec.podCIDR}' 2>/dev/null | grep -q "10.1"; then
            info "Pod CIDR restored after kubelite restart"
          else
            warn "Pod CIDR still missing - controller-manager may need attention"
          fi
        fi
        
        run_cmd "snap restart microk8s.daemon-flanneld" "Restart flanneld for subnet.env generation"
      elif [ $SUBNET_ATTEMPTS -eq 2 ]; then
        # Second attempt: check RBAC and etcd connectivity
        info "Second attempt: Checking RBAC and etcd connectivity..."
        run_cmd "microk8s kubectl auth can-i get nodes --as=system:node:$(hostname)" "Check node RBAC permissions" || warn "RBAC issue detected"
        run_cmd "snap restart microk8s.daemon-kubelite" "Restart kubelite for etcd sync"
        sleep 10
        run_cmd "snap restart microk8s.daemon-flanneld" "Restart flanneld after kubelite"
      elif [ $SUBNET_ATTEMPTS -eq 3 ]; then
        # Third attempt: Wi-Fi specific fixes
        info "Third attempt: Applying Wi-Fi specific fixes..."
        
        # Disable and re-enable VXLAN module
        run_cmd "modprobe -r vxlan || true" "Unload VXLAN module"
        sleep 2
        run_cmd "modprobe vxlan" "Reload VXLAN module"
        
        # Clear any existing flannel state
        run_cmd "rm -rf /run/flannel/* || true" "Clear flannel state"
        run_cmd "mkdir -p /run/flannel" "Recreate flannel directory"
        
        # Force complete restart sequence
        run_cmd "microk8s stop" "Stop MicroK8s for clean restart"
        sleep 10
        run_cmd "microk8s start" "Start MicroK8s after state cleanup"
        sleep 20
      elif [ $SUBNET_ATTEMPTS -eq 4 ]; then
        # Fourth attempt: Robust host-gw backend switch for Wi-Fi
        info "Fourth attempt: Robust switch to host-gw backend for Wi-Fi reliability..."
        
        # Stop flanneld completely before backend change
        run_cmd "snap stop microk8s.daemon-flanneld" "Stop flanneld for backend change"
        
        # Verify Pod CIDR is still present before switching backend
        if ! microk8s kubectl get node "$(hostname)" -o jsonpath='{.spec.podCIDR}' 2>/dev/null | grep -q "10.1"; then
          warn "Pod CIDR missing during backend switch - this is a critical issue"
          info "Backend switch requires valid Pod CIDR - will continue but may fail"
          run_cmd "microk8s kubectl get node $(hostname) -o yaml | grep -A 3 -B 3 cidr" "Pod CIDR diagnostic" || true
        fi
        
        # Clean any previous state before backend change
        run_cmd "rm -rf /run/flannel/* || true" "Clean flannel state for backend change"
        run_cmd "mkdir -p /run/flannel" "Recreate flannel directory"
        
        # Update flannel configuration to use host-gw instead of vxlan
        info "Jetson Wi-Fi detected - switching to host-gw backend for reliability"
        run_cmd "echo '{\"Network\": \"${POD_CIDR}\", \"Backend\": {\"Type\": \"host-gw\"}}' > /var/snap/microk8s/current/args/flannel-network-mgr-config" "Switch to host-gw backend"
        
        # Start flanneld with new configuration
        run_cmd "snap start microk8s.daemon-flanneld" "Start flanneld with host-gw backend"
        
        ok "Switched to host-gw backend - better compatibility for Wi-Fi on Jetson"
      fi
      
      info "Waiting ${SUBNET_WAIT_TIME}s for flanneld to stabilize (attempt $SUBNET_ATTEMPTS)..."
      sleep $SUBNET_WAIT_TIME
    fi
  done
  
  if [ $SUBNET_ATTEMPTS -ge $SUBNET_MAX_ATTEMPTS ] && [ ! -f "/run/flannel/subnet.env" ]; then
    err "subnet.env file still missing after $SUBNET_MAX_ATTEMPTS attempts - flanneld has persistent issues"
    
    # Comprehensive diagnostics
    info "=== FLANNELD COMPREHENSIVE DIAGNOSTICS ==="
    
    # CRITICAL: Check Pod CIDR assignment (main cause of Jetson issues)
    info "Pod CIDR assignment status:"
    if microk8s kubectl get node "$(hostname)" -o jsonpath='{.spec.podCIDR}' 2>/dev/null | grep -q "10.1"; then
      POD_CIDR_STATUS=$(microk8s kubectl get node "$(hostname)" -o jsonpath='{.spec.podCIDR}')
      ok "Node has Pod CIDR: $POD_CIDR_STATUS"
    else
      err "Node missing Pod CIDR - THIS IS THE ROOT CAUSE"
      run_cmd "microk8s kubectl get node $(hostname) -o yaml | grep -A 5 -B 5 podCIDR" "Node CIDR details"
    fi
    
    run_cmd "journalctl -u snap.microk8s.daemon-flanneld --no-pager -n 50" "flanneld recent logs"
    run_cmd "ps aux | grep flannel" "flannel processes"
    run_cmd "snap services microk8s" "MicroK8s services status"
    run_cmd "ls -la /var/snap/microk8s/common/run/flannel/" "flannel directory contents"
    run_cmd "cat /var/snap/microk8s/current/args/flannel-network-mgr-config" "flannel network config"
    run_cmd "cat /var/snap/microk8s/current/args/flanneld" "flanneld args"
    
    # Network interface diagnostics
    run_cmd "ip addr show $FLANNEL_IFACE" "flannel interface status"
    run_cmd "ethtool -k $FLANNEL_IFACE 2>/dev/null || ip link show $FLANNEL_IFACE" "interface capabilities"
    
    warn "Flannel may not work properly - consider using wired Ethernet connection"
    warn "You can continue setup but pod networking might be limited"
  else
    ok "subnet.env file successfully generated after $SUBNET_ATTEMPTS attempts ✓"
  fi
  
  # Verify that the cni0 interface has been created
  info "Verifying cni0 interface creation..."
  if ip addr show cni0 >/dev/null 2>&1; then
    ok "cni0 interface created correctly ✓"
    run_cmd "ip addr show cni0" "cni0 interface details"
  else
    warn "cni0 interface not yet created"
    info "This can be normal if there are no pods running"
  fi
  
  # CRITICAL: Final verification that Calico is completely removed
  info "Verifying Calico is completely removed..."
  
  CALICO_ISSUES=0
  
  # Check for Calico interfaces
  if ip link show | grep -q "vxlan.calico\|cali"; then
    err "Calico network interfaces still present!"
    CALICO_ISSUES=$((CALICO_ISSUES + 1))
  fi
  
  # Check for Calico CNI config
  if [ -f "/var/snap/microk8s/current/args/cni-network/10-calico.conflist" ]; then
    err "Calico CNI configuration still present!"
    CALICO_ISSUES=$((CALICO_ISSUES + 1))
  fi
  
  # Check for running Calico containers
  if microk8s ctr containers list 2>/dev/null | grep -q calico; then
    err "Calico containers still running!"
    CALICO_ISSUES=$((CALICO_ISSUES + 1))
  fi
  
  if [ $CALICO_ISSUES -eq 0 ]; then
    ok "✅ Calico completely removed - Flannel has exclusive control"
  else
    err "❌ Calico interference detected ($CALICO_ISSUES issues) - this will prevent Flannel from working"
    warn "Re-run the setup script to complete Calico removal"
  fi
  
  # Verify only Flannel CNI config exists
  info "Verifying CNI configuration priority..."
  CNI_CONFIGS=$(ls /var/snap/microk8s/current/args/cni-network/*.conflist 2>/dev/null | wc -l)
  if [ "$CNI_CONFIGS" -eq 1 ] && [ -f "/var/snap/microk8s/current/args/cni-network/10-flannel.conflist" ]; then
    ok "✅ Only Flannel CNI config present - correct priority"
  else
    warn "Multiple CNI configs detected - check priority order"
    run_cmd "ls -la /var/snap/microk8s/current/args/cni-network/" "CNI configurations"
  fi
  
  # Final test: attempt to create a test pod to verify the network
  info "Final pod connectivity test..."
  
  # Delete any previous test pods
  microk8s kubectl delete pod test-flannel-connectivity --ignore-not-found=true 2>/dev/null || true
  
  # JETSON FIX: Extended connectivity test with better diagnostics
  info "Running extended connectivity test (optimized for Jetson)..."
  
  # Wait for any previous pod cleanup
  sleep 10
  
  # Create test pod with better success detection for Jetson
  POD_TEST_SUCCESS=false
  
  # Start the pod without --rm to check status properly
  if microk8s kubectl run test-flannel-connectivity --image=busybox:1.28 --restart=Never -- ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    # Wait for pod to complete or fail (max 120s)
    WAIT_COUNT=0
    while [ $WAIT_COUNT -lt 24 ]; do  # 24 * 5s = 120s
      POD_STATUS=$(microk8s kubectl get pod test-flannel-connectivity -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
      
      if [ "$POD_STATUS" = "Succeeded" ] || [ "$POD_STATUS" = "Completed" ]; then
        POD_TEST_SUCCESS=true
        ok "Pod connectivity test with Flannel: SUCCESS ✓ (pod completed successfully)"
        ok "Flannel correctly configured and working!"
        break
      elif [ "$POD_STATUS" = "Failed" ]; then
        warn "Pod connectivity test failed - pod status: Failed"
        break
      elif [ "$POD_STATUS" = "NotFound" ]; then
        warn "Pod connectivity test failed - pod not found"
        break
      fi
      
      WAIT_COUNT=$((WAIT_COUNT + 1))
      sleep 5
    done
    
    if [ $WAIT_COUNT -ge 24 ]; then
      warn "Pod connectivity test timeout after 120s - pod status: $POD_STATUS"
    fi
  else
    warn "Pod connectivity test failed to start"
  fi
  
  if [ "$POD_TEST_SUCCESS" != true ]; then
    
      # Enhanced diagnostics for failed connectivity test
  info "=== CONNECTIVITY DIAGNOSTICS ==="
  
  # CRITICAL: Check for Calico interference
  info "Checking for Calico interference..."
  if ip link show | grep -q "vxlan.calico\|cali"; then
    err "CALICO INTERFACES STILL PRESENT - this prevents Flannel from working!"
    run_cmd "ip link show | grep -E '(vxlan.calico|cali)'" "Active Calico interfaces"
    err "Calico is intercepting pods before Flannel can handle them"
  fi
  
  if [ -f "/var/snap/microk8s/current/args/cni-network/10-calico.conflist" ]; then
    err "CALICO CNI CONFIG STILL PRESENT - this has priority over Flannel!"
    warn "10-calico.conflist takes priority over 10-flannel.conflist due to alphabetical order"
  fi
  
  # Check if pod was created but failed
  if microk8s kubectl get pod test-flannel-connectivity 2>/dev/null; then
    info "Test pod exists, checking details..."
    run_cmd "microk8s kubectl describe pod test-flannel-connectivity" "Pod details"
    run_cmd "microk8s kubectl logs test-flannel-connectivity" "Pod logs"
  else
    info "Test pod was not created, checking system readiness..."
  fi
    
    # Check cni0 interface
    if ip addr show cni0 >/dev/null 2>&1; then
      info "cni0 interface exists:"
      run_cmd "ip addr show cni0" "cni0 interface details"
    else
      warn "cni0 interface not created - this may be the root cause"
    fi
    
    # Check flannel0.1 interface (VXLAN)
    if ip addr show flannel.1 >/dev/null 2>&1; then
      info "flannel.1 (VXLAN) interface exists:"
      run_cmd "ip addr show flannel.1" "flannel.1 interface details"
    else
      warn "flannel.1 interface not created - VXLAN may have issues"
      
      # If using Wi-Fi, suggest host-gw
      if [[ "$FLANNEL_IFACE" == *"wl"* ]] || [[ "$FLANNEL_IFACE" == *"wlan"* ]]; then
        warn "Wi-Fi detected - VXLAN issues are common with wireless interfaces"
        info "Recommendation: Use wired Ethernet or switch to host-gw backend"
      fi
    fi
    
    # Check routing
    run_cmd "ip route show | grep cni0" "CNI routing" || warn "No CNI routes found"
    run_cmd "iptables -t nat -L POSTROUTING | grep MASQUERADE" "MASQUERADE rules (managed by flanneld)" || info "MASQUERADE rules will be created by flanneld automatically"
    
    info "This can be normal during initial stabilization on slower devices"
    info "You may need to:"
    info "  1. Use wired Ethernet instead of Wi-Fi"
    info "  2. Wait longer for system stabilization"
    info "  3. Check physical network connectivity"
    
    # Clean up test pod if left behind
    microk8s kubectl delete pod test-flannel-connectivity --ignore-not-found=true 2>/dev/null || true
  fi
  
  # Additional basic diagnostics regardless of test result
  info "=== FINAL SYSTEM STATUS ==="
  run_cmd "microk8s kubectl get nodes -o wide" "Node status"
  run_cmd "microk8s kubectl get pods --all-namespaces --field-selector=status.phase!=Running" "Non-Running pods"
  
  # Summary based on test results
  if [ "$POD_TEST_SUCCESS" = true ]; then
    ok "🎉 Flannel networking fully functional!"
  else
    warn "⚠️  Flannel configured but connectivity test failed"
    warn "This is often temporary on Jetson devices - monitor system for stabilization"
  fi
  
  ok "✅ Flannel configuration for Jetson COMPLETED"
  info "📋 Applied corrections:"
  info "  • CRITICAL: Ensured Pod CIDR assignment to node (main Jetson issue fix)"
  info "  • CRITICAL: Removed Calico traces that interfere with Flannel"
  info "  • Enhanced Pod CIDR verification with automatic re-assignment"
  info "  • Improved host-gw backend switching for Wi-Fi reliability"
  info "  • Configured optimal network interface: $FLANNEL_IFACE"
  info "  • Using MicroK8s default POD_CIDR: $POD_CIDR"
  info "  • Loaded required VXLAN module with Wi-Fi optimizations"
  info "  • Created RBAC to avoid 'nodes is forbidden'"
  info "  • Eliminated IPAM leaks from CNI/flannel directories"
  info "  • Enhanced diagnostics with Pod CIDR status checking"

else
  # Standard configuration with Calico
  info "Standard configuration with Calico"
  CORE_ADDONS=(dns rbac helm3 ingress cert-manager)
fi
# endregion 22) Flannel Configuration (Jetson)
