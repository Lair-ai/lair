#!/usr/bin/env bash

# region 29) Quick final verification
if [[ "${IS_PRIMARY_NODE:-false}" == "true" ]]; then
  info "🏗️  PRIMARY NODE: Final cluster verification..."
  debug "Essential cluster information"
  run_cmd "microk8s kubectl get nodes -o wide" "Cluster nodes status"

  # Verify Longhorn pods only if not on Jetson
  if ! $IS_JETSON; then
    run_cmd "microk8s kubectl -n longhorn-system get pods --no-headers | wc -l" "Longhorn pod count"
  else
    info "Jetson system: skip Longhorn pod verification (not installed)"
  fi

  run_cmd "microk8s kubectl get sc" "Storage classes" || true

  # Light diagnostics instead of full inspect
  debug "Light MicroK8s diagnostics"
  run_cmd "microk8s status" "MicroK8s status"

elif [[ "${IS_SECONDARY_NODE:-false}" == "true" ]]; then
  info "🔗 SECONDARY NODE: Final verification..."
  debug "Verifying node joined cluster successfully"
  
  # Check if node appears in cluster
  run_cmd "microk8s kubectl get nodes -o wide" "Cluster nodes status"
  
  # Verify this node is in the cluster
  NODE_NAME=$(hostname)
  if microk8s kubectl get nodes | grep -q "$NODE_NAME"; then
    ok "Node $NODE_NAME successfully joined cluster"
  else
    warn "Node $NODE_NAME not found in cluster node list"
  fi
  
  # Check basic connectivity to cluster
  run_cmd "microk8s kubectl get pods --all-namespaces" "Cluster pods status" || true
  
  # Light diagnostics
  debug "Light MicroK8s diagnostics for secondary node"
  run_cmd "microk8s status" "MicroK8s status"
fi

# Full diagnostics only if explicitly requested
FULL_DIAGNOSTICS=${FULL_DIAGNOSTICS:-false}
if $FULL_DIAGNOSTICS; then
  warn "Full diagnostics requested - this will take several minutes..."
  run_cmd "microk8s kubectl get pv,pvc --all-namespaces" "Persistent volumes" || true
  run_cmd "microk8s kubectl get all --all-namespaces" "All cluster objects" || true
  
  # Inspect only if full diagnostics
  info "Running microk8s inspect (may take 2-3 minutes)..."
  run_cmd "microk8s inspect" "Full MicroK8s inspection"
else
  ok "Quick diagnostics completed - bootstrap proceeds without interruptions"
  info "💡 For full diagnostics: FULL_DIAGNOSTICS=true sudo ./setup_microk8s.sh"
fi
# endregion 29) Quick final verification

# region 30) Save essential logs
# Save only essential logs by default
debug "Saving essential logs"
run_cmd "mkdir -p $LOGDIR/diagnostic" "Creating diagnostic directory"

# Essential logs always saved (different for primary vs secondary)
if [[ "${IS_PRIMARY_NODE:-false}" == "true" ]]; then
  run_cmd "microk8s kubectl get nodes,sc,pv,pvc --all-namespaces -o wide > $LOGDIR/diagnostic/cluster-summary.txt" "Cluster summary"
elif [[ "${IS_SECONDARY_NODE:-false}" == "true" ]]; then
  run_cmd "microk8s kubectl get nodes -o wide > $LOGDIR/diagnostic/cluster-nodes.txt" "Cluster nodes"
  run_cmd "microk8s kubectl get pods --all-namespaces > $LOGDIR/diagnostic/cluster-pods.txt" "Cluster pods" || true
fi
run_cmd "microk8s status > $LOGDIR/diagnostic/microk8s-status.txt" "MicroK8s status"

# Full logs only if requested
if $FULL_DIAGNOSTICS; then
  info "Saving full diagnostics..."
  run_cmd "microk8s kubectl get all --all-namespaces -o yaml > $LOGDIR/diagnostic/all-resources.yaml" "Complete resources export"
  run_cmd "microk8s inspect > $LOGDIR/diagnostic/microk8s-inspect.txt" "Full inspect save"
  run_cmd "journalctl -u snap.microk8s.* --no-pager > $LOGDIR/diagnostic/microk8s-journal.txt" "Journal save"
  run_cmd "tar -czf $LOGDIR/microk8s-diagnostic-logs.tar.gz -C $LOGDIR diagnostic *.log" "Creating full diagnostics archive"
  ok "Full diagnostics saved in $LOGDIR/microk8s-diagnostic-logs.tar.gz"
else
  run_cmd "tar -czf $LOGDIR/microk8s-essential-logs.tar.gz -C $LOGDIR diagnostic *.log" "Creating essential logs archive"
  ok "Essential logs saved in $LOGDIR/microk8s-essential-logs.tar.gz"
fi

run_cmd "rm -rf $LOGDIR/diagnostic" "Cleaning temporary directory"

ok "Bootstrap completed!"
info "Logs available in $LOGDIR/"
if $FULL_DIAGNOSTICS; then
  info "For full diagnostics: $LOGDIR/microk8s-diagnostic-logs.tar.gz"
else
  info "For essential logs: $LOGDIR/microk8s-essential-logs.tar.gz"
  info "💡 For full diagnostics in future: FULL_DIAGNOSTICS=true sudo ./setup_microk8s.sh"
fi
# endregion 30) Save essential logs

# region 31) Access token extraction and saving
info "Extracting MicroK8s access tokens..."
TOKEN_FILE="$SCRIPT_DIR/microk8s-access-tokens.txt"
install -m 600 /dev/null "$TOKEN_FILE"
echo "=== MicroK8s Access Tokens ===" > "$TOKEN_FILE"
echo "Generated on: $(date)" >> "$TOKEN_FILE"
echo "=============================" >> "$TOKEN_FILE"
echo "" >> "$TOKEN_FILE"

# region 31.1) Extract admin token
info "Extracting Admin token..."
ADMIN_TOKEN="extraction_failed" # Default to failed

# Try first with microk8s config
KUBECONFIG_OUTPUT=$(microk8s config 2>/dev/null || echo "")

if [ -n "$KUBECONFIG_OUTPUT" ]; then
  debug "Kubeconfig output obtained, searching for token..."
  
  # Method 1: Search for "token:" in kubeconfig
  if echo "$KUBECONFIG_OUTPUT" | grep -q "token:"; then
    ADMIN_TOKEN=$(echo "$KUBECONFIG_OUTPUT" | grep "token:" | head -n1 | awk '{print $2}' | tr -d '"' | tr -d "'")
    if [ -n "$ADMIN_TOKEN" ] && [ "$ADMIN_TOKEN" != "token:" ]; then
      ok "Admin token extracted from kubeconfig"
    else
      ADMIN_TOKEN="extraction_failed"
    fi
  fi
  
  # Method 2: If no token, try with client-certificate-data (uses certificates instead of token)
  if [ "$ADMIN_TOKEN" = "extraction_failed" ]; then
    if echo "$KUBECONFIG_OUTPUT" | grep -q "client-certificate-data:"; then
      ADMIN_TOKEN="certificate_based_auth"
      info "Certificate-based authentication (no token)"
    fi
  fi
else
  warn "Unable to get kubeconfig from microk8s config"
fi
# endregion 31.1) Extract admin token

# region 31.2) Extract admin token
# Method 3: Try direct extraction from snap file
if [ "$ADMIN_TOKEN" = "extraction_failed" ]; then
  info "Attempting token extraction from snap file..."
  
  if [ -f "/var/snap/microk8s/current/credentials/known_tokens.csv" ]; then
    SNAP_TOKEN=$(head -n1 /var/snap/microk8s/current/credentials/known_tokens.csv 2>/dev/null | cut -d',' -f1 || echo "")
    if [ -n "$SNAP_TOKEN" ]; then
      ADMIN_TOKEN="$SNAP_TOKEN"
      ok "Token extracted from known_tokens.csv"
    fi
  fi
fi
# endregion 31.2) Extract admin token

# region 31.3) Extract admin token
# Method 4: Try with kubectl to get service account token
if [ "$ADMIN_TOKEN" = "extraction_failed" ]; then
  info "Attempting token extraction from service account..."
  
  # Create admin service account if it doesn't exist
  if ! microk8s kubectl get serviceaccount admin-user -n kube-system >/dev/null 2>&1; then
    microk8s kubectl create serviceaccount admin-user -n kube-system >/dev/null 2>&1 || true
    microk8s kubectl create clusterrolebinding admin-user --clusterrole=cluster-admin --serviceaccount=kube-system:admin-user >/dev/null 2>&1 || true
  fi
  
  # Extract service account token
  SA_TOKEN=$(microk8s kubectl -n kube-system get secret $(microk8s kubectl -n kube-system get serviceaccount admin-user -o jsonpath='{.secrets[0].name}' 2>/dev/null) -o jsonpath='{.data.token}' 2>/dev/null | base64 --decode 2>/dev/null || echo "")
  
  if [ -n "$SA_TOKEN" ]; then
    ADMIN_TOKEN="$SA_TOKEN"
    ok "Token extracted from service account"
  fi
fi

echo "Admin Token:" >> "$TOKEN_FILE"
echo "$ADMIN_TOKEN" >> "$TOKEN_FILE"
echo "" >> "$TOKEN_FILE"
# endregion 31.3) Extract admin token

# region 31.4) Extract client certificate
# Extract client certificate
info "Extracting Client Certificate..."
echo "Client Certificate:" >> "$TOKEN_FILE"
if [ -n "$KUBECONFIG_OUTPUT" ] && echo "$KUBECONFIG_OUTPUT" | grep -q "client-certificate-data:"; then
  echo "$KUBECONFIG_OUTPUT" | awk '/client-certificate-data:/,/client-key-data:/' | grep -v "client-key-data:" >> "$TOKEN_FILE"
else
  echo "extraction_failed" >> "$TOKEN_FILE"
fi
echo "" >> "$TOKEN_FILE"
# endregion 31.4) Extract client certificate

# region 31.5) Extract client key
# Extract client key
info "Extracting Client Key..."
echo "Client Key:" >> "$TOKEN_FILE"
if [ -n "$KUBECONFIG_OUTPUT" ] && echo "$KUBECONFIG_OUTPUT" | grep -q "client-key-data:"; then
  echo "$KUBECONFIG_OUTPUT" | awk '/client-key-data:/,/certificate-authority-data:/' | grep -v "certificate-authority-data:" >> "$TOKEN_FILE"
else
  echo "extraction_failed" >> "$TOKEN_FILE"
fi
echo "" >> "$TOKEN_FILE"
# endregion 31.5) Extract client key

# region 31.6) Extract CA certificate
# Extract CA certificate
info "Extracting CA Certificate..."
echo "CA Certificate:" >> "$TOKEN_FILE"
if [ -n "$KUBECONFIG_OUTPUT" ] && echo "$KUBECONFIG_OUTPUT" | grep -q "certificate-authority-data:"; then
  echo "$KUBECONFIG_OUTPUT" | awk '/certificate-authority-data:/,/server:/' | grep -v "server:" >> "$TOKEN_FILE"
else
  echo "extraction_failed" >> "$TOKEN_FILE"
fi
echo "" >> "$TOKEN_FILE"
# endregion 31.6) Extract CA certificate

# region 31.7) Extract server endpoint
# Extract server endpoint
info "Extracting Server Endpoint..."
SERVER_ENDPOINT="extraction_failed"
if [ -n "$KUBECONFIG_OUTPUT" ] && echo "$KUBECONFIG_OUTPUT" | grep -q "server:"; then
  SERVER_ENDPOINT=$(echo "$KUBECONFIG_OUTPUT" | grep "server:" | awk '{print $2}' | head -n1)
  if [ -n "$SERVER_ENDPOINT" ]; then
    ok "Server endpoint extracted"
  else
    SERVER_ENDPOINT="extraction_failed"
  fi
else
  warn "Server endpoint not found in kubeconfig output"
fi
echo "Server Endpoint:" >> "$TOKEN_FILE"
echo "$SERVER_ENDPOINT" >> "$TOKEN_FILE"
# endregion 31.7) Extract server endpoint

# region 31.8) Additional troubleshooting information
# Additional troubleshooting information
echo "" >> "$TOKEN_FILE"
echo "=== Troubleshooting Info ===" >> "$TOKEN_FILE"
echo "Kubeconfig file location: $PAR_HOME/.kube/config" >> "$TOKEN_FILE"
echo "MicroK8s config command: microk8s config" >> "$TOKEN_FILE"
echo "Alternative auth: Use client certificates if token fails" >> "$TOKEN_FILE"
# endregion 31.8) Additional troubleshooting information

# region 31.9) Set correct permissions
# Set correct permissions
chmod 600 "$TOKEN_FILE"
ok "Tokens saved in $TOKEN_FILE"
# endregion 31.9) Set correct permissions

# region 31.10) Display tokens in console
# Display tokens in console
echo -e "\n${YELLOW}=== MicroK8s Access Tokens ===${NC}"
echo -e "${GREEN}Admin Token:${NC}"
if [ "$ADMIN_TOKEN" = "extraction_failed" ]; then
  echo -e "${RED}❌ Token extraction failed${NC}"
  echo -e "${YELLOW}💡 Use certificate-based auth or run: microk8s config${NC}"
elif [ "$ADMIN_TOKEN" = "certificate_based_auth" ]; then
  echo -e "${YELLOW}🔐 Certificate-based authentication (no bearer token)${NC}"
else
  echo -e "${YELLOW}[PROTECTED] Saved securely in: $TOKEN_FILE${NC}"
fi
echo -e "\n${GREEN}Server Endpoint:${NC}"
echo "$SERVER_ENDPOINT"
echo -e "\n${YELLOW}=============================${NC}"
if [ "$ADMIN_TOKEN" = "extraction_failed" ]; then
  echo -e "${YELLOW}⚠️  Token extraction failed. Use kubeconfig file: $PAR_HOME/.kube/config${NC}"
else
  echo -e "${YELLOW}⚠️  Complete tokens have been saved in $TOKEN_FILE${NC}"
fi
# endregion 31.10) Display tokens in console
# endregion 31) Access token extraction and saving

# region 31.5) Generate join token for primary nodes
if [[ "${IS_PRIMARY_NODE:-false}" == "true" ]]; then
  info "🔗 Generating join token for secondary nodes..."
  
  # Generate join token and save it
  JOIN_INFO_FILE="$SCRIPT_DIR/microk8s-join-info.txt"
  echo "=== MicroK8s Cluster Join Information ===" > "$JOIN_INFO_FILE"
  echo "Generated on: $(date)" >> "$JOIN_INFO_FILE"
  echo "Primary Node: $(hostname)" >> "$JOIN_INFO_FILE"
  echo "Cluster: ${CLUSTER_NAME:-microk8s-cluster}" >> "$JOIN_INFO_FILE"
  echo "=========================================" >> "$JOIN_INFO_FILE"
  echo "" >> "$JOIN_INFO_FILE"
  
  # Generate join token
  if JOIN_COMMAND=$(microk8s add-node 2>/dev/null | head -n1); then
    echo "Join Command:" >> "$JOIN_INFO_FILE"
    echo "$JOIN_COMMAND" >> "$JOIN_INFO_FILE"
    echo "" >> "$JOIN_INFO_FILE"
    
    # Extract just the token part for easier use
    JOIN_TOKEN_ONLY=""
    if [[ "$JOIN_COMMAND" =~ microk8s\ join\ ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/[a-zA-Z0-9]+) ]]; then
      JOIN_TOKEN_ONLY="${BASH_REMATCH[1]}"
      echo "Join Token Only:" >> "$JOIN_INFO_FILE"
      echo "$JOIN_TOKEN_ONLY" >> "$JOIN_INFO_FILE"
      echo "" >> "$JOIN_INFO_FILE"
    else
      # Fallback: try to extract token from the full command
      JOIN_TOKEN_ONLY=$(echo "$JOIN_COMMAND" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/[a-zA-Z0-9]+' || echo "")
      if [[ -n "$JOIN_TOKEN_ONLY" ]]; then
        echo "Join Token Only:" >> "$JOIN_INFO_FILE"
        echo "$JOIN_TOKEN_ONLY" >> "$JOIN_INFO_FILE"
        echo "" >> "$JOIN_INFO_FILE"
      fi
    fi
    
    echo "Instructions for Secondary Nodes:" >> "$JOIN_INFO_FILE"
    echo "1. Run the setup script on the secondary node" >> "$JOIN_INFO_FILE"
    echo "2. Select 'secondary' when prompted for node type" >> "$JOIN_INFO_FILE"
    echo "3. Enter this primary node's IP when requested" >> "$JOIN_INFO_FILE"
    echo "4. Enter the join token when requested" >> "$JOIN_INFO_FILE"
    echo "" >> "$JOIN_INFO_FILE"
    echo "Alternative: Set environment variables:" >> "$JOIN_INFO_FILE"
    echo "export PRIMARY_NODE_IP=\"$(echo "$LOC_CIDR" | cut -d/ -f1)\"" >> "$JOIN_INFO_FILE"
    if [[ -n "$JOIN_TOKEN_ONLY" ]]; then
      echo "export JOIN_TOKEN=\"$JOIN_TOKEN_ONLY\"" >> "$JOIN_INFO_FILE"
    else
      echo "export JOIN_TOKEN=\"<extract_from_join_command>\"" >> "$JOIN_INFO_FILE"
    fi
    echo "sudo ./setup.sh" >> "$JOIN_INFO_FILE"
    
    chmod 600 "$JOIN_INFO_FILE"
    ok "Join information saved to: $JOIN_INFO_FILE"
    
    # Display join information
    echo -e "\n${GREEN}=== 🔗 CLUSTER JOIN INFORMATION ===${NC}"
    echo -e "${YELLOW}To add secondary nodes to this cluster:${NC}"
    echo -e "${GREEN}$JOIN_COMMAND${NC}"
    echo ""
    if [[ -n "$JOIN_TOKEN_ONLY" ]]; then
      echo -e "${YELLOW}Or use just the token:${NC}"
      echo -e "${GREEN}$JOIN_TOKEN_ONLY${NC}"
    fi
    echo ""
    echo -e "${BLUE}Complete join information saved to: $JOIN_INFO_FILE${NC}"
  else
    warn "Failed to generate join token"
    warn "You can generate it manually later with: microk8s add-node"
  fi
fi
# endregion 31.5) Generate join token for primary nodes

# region 32) DNS setup reminder for LAN access
# DNS setup reminder for LAN access
# Initialize variables if not set (for secondary nodes or missing config)
ACCESS_MODE="${ACCESS_MODE:-lan}"
NEW_HOSTNAME="${NEW_HOSTNAME:-$(hostname)}"

if [ "$ACCESS_MODE" = "lan" ]; then
  echo -e "\n${GREEN}=== 🌐 DNS CONFIGURATION REMINDER ===${NC}"
  echo -e "${YELLOW}LAN access mode detected!${NC}"
  echo ""
  echo -e "${BLUE}To access services with easy names like:${NC}"
  echo -e "${GREEN}  • n8n.${NEW_HOSTNAME}.local${NC}"
  echo -e "${GREEN}  • grafana.${NEW_HOSTNAME}.local${NC}"
  echo -e "${GREEN}  • openwebui.${NEW_HOSTNAME}.local${NC}"
  echo -e "${GREEN}  • portainer.${NEW_HOSTNAME}.local${NC}"
  echo ""
  echo -e "${YELLOW}After reboot, run:${NC}"
  echo -e "${GREEN}  sudo ./setup_dns.sh install${NC}"
  echo ""
  
  # Create a reminder file
  cat > "$SCRIPT_DIR/dns-setup-reminder.txt" << EOF
=== 🌐 DNS SETUP REMINDER ===

LAN access mode detected - DNS configuration needed after reboot.

Commands to execute (in order):
1. sudo ./setup_dns.sh backup          # Security backup
2. sudo ./setup_dns.sh install         # Install DNS wildcard
3. sudo ./setup_dns.sh enable-network  # Enable for other PCs

Result:
- *.${NEW_HOSTNAME}.local will point to this machine
- Other network devices can use services with easy names
- Automatic backup for security

File generated: $(date)
EOF
  echo -e "${GREEN}📝 Reminder saved in: $SCRIPT_DIR/dns-setup-reminder.txt${NC}"
  echo ""
fi
# endregion 32) DNS setup suggestion for Jetson LAN

# region 32.5) Remote access information
if [[ "$REMOTE_ACCESS" == "yes" ]]; then
  echo -e "\n${GREEN}=== 🌐 REMOTE ACCESS CONFIGURED ===${NC}"
  
  # Determine IP to display and scenario
  DISPLAY_IP=""
  SCENARIO_TYPE=""
  
  if [[ "$ACCESS_MODE" == "public" && -n "$PUB_IP" ]]; then
    DISPLAY_IP="$PUB_IP"
    if [[ "$IS_CLOUD_PUBLIC" == "true" ]]; then
      SCENARIO_TYPE="☁️ CLOUD PUBLIC"
    elif [[ "$IS_ONPREMISES_PUBLIC" == "true" ]]; then
      SCENARIO_TYPE="🏠 ON-PREMISES PUBLIC"
    else
      SCENARIO_TYPE="🌍 PUBLIC"
    fi
  else
    DISPLAY_IP=$(echo "$LOC_CIDR" | cut -d/ -f1)
    SCENARIO_TYPE="🏢 LAN"
  fi
  
  echo -e "${GREEN}Scenario: ${SCENARIO_TYPE}${NC}"
  echo -e "${YELLOW}Your Kubernetes cluster is accessible from:${NC}"
  echo -e "${GREEN}  🔗 API Server: https://${DISPLAY_IP}:16443${NC}"
  echo -e "${GREEN}  📋 Kubeconfig: ~${PAR_USER}/.kube/config${NC}"
  echo ""
  
  echo -e "${BLUE}To access from another computer:${NC}"
  echo -e "${YELLOW}1. Copy the kubeconfig file:${NC}"
  echo -e "   ${GREEN}scp ${PAR_USER}@${DISPLAY_IP}:~/.kube/config ~/.kube/config${NC}"
  echo -e "${YELLOW}2. Install kubectl on the remote computer${NC}"
  echo -e "${YELLOW}3. Test the connection:${NC}"
  echo -e "   ${GREEN}kubectl get nodes${NC}"
  echo ""
  
  # Specific information for scenario
  if [[ "$SCENARIO_TYPE" == "☁️ CLOUD PUBLIC" ]]; then
    echo -e "${BLUE}📋 CLOUD PUBLIC SCENARIO (AWS/GCP/Azure):${NC}"
    echo -e "${GREEN}✅ Benefits:${NC}"
    echo -e "${GREEN}  • Ingress directly accessible from internet${NC}"
    echo -e "${GREEN}  • Public load balancers work natively${NC}"
    echo -e "${GREEN}  • Automatic SSL certificates with Let's Encrypt${NC}"
    echo -e "${GREEN}  • Simple configuration for public services${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Ingress Configuration:${NC}"
    echo -e "${GREEN}  • MetalLB pool: ${METALLB_RANGES}${NC}"
    echo -e "${GREEN}  • Domains: point directly to ${PUB_IP}${NC}"
    echo -e "${GREEN}  • Certificates: cert-manager + Let's Encrypt${NC}"
    echo ""
    echo -e "${RED}⚠️  IMPORTANT SECURITY:${NC}"
    echo -e "${RED}• Cluster exposed directly on internet${NC}"
    echo -e "${RED}• Configure firewall to limit access${NC}"
    echo -e "${RED}• Use strong authentication (RBAC)${NC}"
    echo -e "${RED}• Monitor access regularly${NC}"
    
  elif [[ "$SCENARIO_TYPE" == "🏠 ON-PREMISES PUBLIC" ]]; then
    echo -e "${BLUE}📋 ON-PREMISES PUBLIC SCENARIO (Home/Office with public IP):${NC}"
    echo -e "${GREEN}✅ Optimal configuration for:${NC}"
    echo -e "${GREEN}  • Home/office servers with static public IP${NC}"
    echo -e "${GREEN}  • Internet access through router/firewall${NC}"
    echo -e "${GREEN}  • Personal/business web domains${NC}"
    echo ""
    LOCAL_IP=$(echo "$LOC_CIDR" | cut -d/ -f1)
    echo -e "${YELLOW}🔧 Ingress Configuration:${NC}"
    echo -e "${GREEN}  • MetalLB pool: ${METALLB_RANGES} (public IP)${NC}"
    echo -e "${GREEN}  • Local machine IP: ${LOCAL_IP}${NC}"
    echo -e "${GREEN}  • Internal services: use ${LOCAL_IP}${NC}"
    echo -e "${GREEN}  • Public services: use ${PUB_IP}${NC}"
    echo ""
    echo -e "${YELLOW}📋 Required Port Forwarding on router:${NC}"
    echo -e "${GREEN}  • 80 (HTTP) → ${LOCAL_IP}:80${NC}"
    echo -e "${GREEN}  • 443 (HTTPS) → ${LOCAL_IP}:443${NC}"
    echo -e "${GREEN}  • 16443 (Kubernetes API) → ${LOCAL_IP}:16443${NC}"
    echo ""
    echo -e "${YELLOW}🌐 DNS domain configuration:${NC}"
    echo -e "${GREEN}  • yourdomain.com A record → ${PUB_IP}${NC}"
    echo -e "${GREEN}  • *.yourdomain.com A record → ${PUB_IP}${NC}"
    echo -e "${GREEN}  • Ingress: host: app.yourdomain.com${NC}"
    echo ""
    echo -e "${RED}⚠️  IMPORTANT CHECKLIST:${NC}"
    echo -e "${RED}• Port forwarding configured on router${NC}"
    echo -e "${RED}• Local firewall open for necessary ports${NC}"
    echo -e "${RED}• DNS domains point to your public IP${NC}"
    echo -e "${RED}• SSL certificates configured (Let's Encrypt)${NC}"
    
  else
    echo -e "${BLUE}📋 LAN SCENARIO (Local Network):${NC}"
    echo -e "${GREEN}✅ Configuration for:${NC}"
    echo -e "${GREEN}  • Development and testing${NC}"
    echo -e "${GREEN}  • Internal company services${NC}"
    echo -e "${GREEN}  • Homelab and experimentation${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Ingress Configuration:${NC}"
    echo -e "${GREEN}  • MetalLB pool: ${METALLB_RANGES}${NC}"
    echo -e "${GREEN}  • Services: http://${DISPLAY_IP} or .local subdomains${NC}"
    echo -e "${GREEN}  • Certificates: self-signed or internal CA${NC}"
    echo ""
    echo -e "${YELLOW}💡 DNS Suggestion:${NC}"
    echo -e "${YELLOW}• For easy access with names:${NC}"
    echo -e "${GREEN}  sudo ./setup_dns.sh install${NC}"
    echo -e "${YELLOW}• Enables: app.${NEW_HOSTNAME}.local${NC}"
  fi
  
  echo -e "\n${BLUE}🔧 Remote access troubleshooting:${NC}"
  echo -e "${YELLOW}If you can't connect:${NC}"
  echo -e "1. ${GREEN}Verify that kube-apiserver responds:${NC}"
  echo -e "   ${GREEN}curl -k https://${DISPLAY_IP}:16443/version${NC}"
  echo -e "2. ${GREEN}Check local firewall:${NC}"
  echo -e "   ${GREEN}sudo ufw status${NC}"
  echo -e "3. ${GREEN}Verify kube-apiserver logs:${NC}"
  echo -e "   ${GREEN}journalctl -u snap.microk8s.daemon-kubelite${NC}"
  echo -e "4. ${GREEN}Test network connectivity:${NC}"
  echo -e "   ${GREEN}telnet ${DISPLAY_IP} 16443${NC}"
  echo ""
  
else
  echo -e "\n${YELLOW}=== 🔒 LOCAL ACCESS ONLY ===${NC}"
  echo -e "${YELLOW}The cluster is configured for local access only${NC}"
  echo -e "${YELLOW}To manage the cluster remotely:${NC}"
  echo -e "${GREEN}  ssh ${PAR_USER}@${DISPLAY_IP:-$(hostname -I | awk '{print $1}')}${NC}"
  echo -e "${GREEN}  kubectl get nodes${NC}"
  echo ""
fi
# endregion 32.5) Remote access information

# region 32.7) Create kubectl wrapper at end of setup
info "Creating kubectl wrapper /usr/local/bin/kubectl..."
cat <<'EOF' >/usr/local/bin/kubectl
#!/usr/bin/env bash
exec microk8s kubectl "$@"
EOF
run_cmd "chmod +x /usr/local/bin/kubectl" "Setting kubectl wrapper executable"
ok "kubectl available globally"
# endregion 32.7) Create kubectl wrapper at end of setup

# region 33) Intelligent reboot based on platform
# Intelligent reboot based on platform
if $IS_JETSON; then
  echo -e "\n${YELLOW}=== Specific notes for NVIDIA Jetson ===${NC}"
  echo -e "${YELLOW}· Configuration: Flannel was used instead of Calico for better Jetson compatibility${NC}"
  echo -e "${YELLOW}· Performance: Jetson devices have limited resources, operations may be slower${NC}"
  echo -e "${YELLOW}· Diagnostics: Complete logs are in $LOGDIR/microk8s-diagnostic-logs.tar.gz${NC}"
  echo -e "${YELLOW}· Suggestion: If you experience issues after reboot, check:${NC}"
  echo -e "${YELLOW}  - sudo journalctl -u snap.microk8s.daemon-containerd${NC}"
  echo -e "${YELLOW}  - sudo journalctl -u snap.microk8s.daemon-flanneld${NC}"
  echo -e "${YELLOW}  - microk8s status${NC}"

  echo -e "\n${YELLOW}⚠️  The system will be rebooted to apply microk8s permissions.${NC}"
  
  # Offer option to skip reboot for debugging
  if $INTERACTIVE; then
    read -rp "Press ENTER to reboot or 'n' to skip reboot (for debugging): " choice
    if [[ "$choice" =~ ^([nN])$ ]]; then
      echo -e "${YELLOW}Reboot cancelled. Remember to reboot manually with 'sudo reboot' when ready.${NC}"
      exit 0
    fi
  fi
else
  echo -e "\n${YELLOW}⚠️  The system will be rebooted to apply microk8s permissions.${NC}"
  
  
  if $INTERACTIVE; then
    read -rp "Press ENTER to reboot or Ctrl+C to cancel..." 
  fi
fi

reboot
# endregion 33) Intelligent reboot based on platform