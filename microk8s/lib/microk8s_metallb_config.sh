#!/usr/bin/env bash

# region 11) Verifica e installazione di ping (per la scansione pool)
info "Verifico presenza di ping..."
if ! command -v ping &>/dev/null; then
  info "ping non trovato: installo iputils-ping..."
  DEBIAN_FRONTEND=noninteractive apt update && DEBIAN_FRONTEND=noninteractive apt install -y iputils-ping
  ok "ping installato"
else
  ok "ping già presente"
fi
# endregion 9.4) Verifica e installazione di ping (per la scansione pool)

# region 12) Scelta modalità di accesso: LAN vs Public (loop finché non è valida)
ACCESS_MODE="lan"
if $INTERACTIVE; then
  while :; do
    read -rp "🌐 Modalità di accesso? [lan/public] (default: lan): " choice
    choice="${choice,,}"
    if [[ -z "$choice" || "$choice" == "lan" ]]; then
      ACCESS_MODE="lan"
      break
    elif [[ "$choice" == "public" ]]; then
      ACCESS_MODE="public"
      break
    else
      warn "Scelta non valida: inserisci 'lan' o 'public'."
    fi
  done
else
  info "Non-interattivo: modalità predefinita 'lan'"
fi
ok "Modalità scelta: $ACCESS_MODE"
# endregion 12) Scelta modalità di accesso: LAN vs Public (loop finché non è valida)

# region 13) MetalLB pool calculation based on mode, with always fallback
case "$ACCESS_MODE" in

  lan)
    # Extract local IP without CIDR
    LOCAL_IP=$(echo "$LOC_CIDR" | cut -d/ -f1)
    
    info "LAN mode: using local machine IP ($LOCAL_IP) for MetalLB"
    suggested_pool="${LOCAL_IP}-${LOCAL_IP}"
    
    if $INTERACTIVE; then
      read -rp "🌐 Proposed MetalLB pool (machine IP): $suggested_pool. Confirm? [Y/n]: " yn
      if [[ "$yn" =~ ^([nN])$ ]]; then
        read -rp "Enter manual MetalLB pool: " METALLB_RANGES
      else
        METALLB_RANGES="$suggested_pool"
      fi
    else
      METALLB_RANGES="$suggested_pool"
      info "Non-interactive: automatically using machine IP for MetalLB"
    fi
    ;;

  public)
    # Improved public IP detection with multiple methods
    info "Detecting public IP with multiple methods..."
    
    # Install necessary tools if missing
    if ! command -v curl &>/dev/null || ! command -v dig &>/dev/null; then
      info "Installing necessary network tools..."
      DEBIAN_FRONTEND=noninteractive apt update -y > /dev/null 2>&1
      DEBIAN_FRONTEND=noninteractive apt install -y curl dnsutils > /dev/null 2>&1
    fi
    
    # Function to check if an IP is valid
    is_valid_ip() {
      local ip=$1
      [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
      
      # Check that each octet is between 0 and 255
      local IFS='.'
      local -a octets=($ip)
      for octet in "${octets[@]}"; do
        (( octet >= 0 && octet <= 255 )) || return 1
      done
      
      return 0
    }
    
    # Function to validate MetalLB IP ranges (supports single IPs, ranges, and comma-separated lists)
    is_valid_metallb_range() {
      local range_input=$1
      
      # Split by comma for multiple ranges
      IFS=',' read -ra RANGES <<< "$range_input"
      
      for range in "${RANGES[@]}"; do
        # Trim whitespace
        range=$(echo "$range" | xargs)
        
        if [[ "$range" == *"-"* ]]; then
          # It's a range (IP1-IP2)
          local start_ip=$(echo "$range" | cut -d'-' -f1 | xargs)
          local end_ip=$(echo "$range" | cut -d'-' -f2 | xargs)
          
          if ! is_valid_ip "$start_ip" || ! is_valid_ip "$end_ip"; then
            return 1
          fi
        else
          # It's a single IP
          if ! is_valid_ip "$range"; then
            return 1
          fi
        fi
      done
      
      return 0
    }
    
    # Function to check if an IP is probably a private IP
    is_private_ip() {
      local ip=$1
      [[ $ip =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.) ]] && return 0
      [[ $ip =~ ^169\.254\. ]] && return 0  # APIPA
      return 1
    }
    
    # Array of IP detection methods
    declare -a PUB_IP_METHODS
    PUB_IP_METHODS=(
      "curl -s https://api.ipify.org"
      "curl -s https://ipinfo.io/ip"
      "curl -s https://ifconfig.me/ip"
      "dig +short myip.opendns.com @resolver1.opendns.com"
      "dig +short whoami.akamai.net @ns1-1.akamaitech.net"
    )
    
    # Detect IP with different methods, stopping at the first valid and non-private one
    PUB_IP=""
    for method in "${PUB_IP_METHODS[@]}"; do
      debug "Trying IP detection with: $method"
      ip_result=$(eval "$method" 2>/dev/null || echo "")
      
      if ! is_empty "$ip_result" && is_valid_ip "$ip_result" && ! is_private_ip "$ip_result"; then
        PUB_IP="$ip_result"
        ok "Public IP detected successfully: $PUB_IP"
        break
      else
        debug "Method failed or returned a private IP: $ip_result"
      fi
    done
    
    # If all online methods fail, use the interface IP as fallback
    if is_empty "$PUB_IP"; then
      warn "Unable to detect public IP with online services, using interface IP"
      # Extract IP without CIDR
      LOC_IP=$(echo "$LOC_CIDR" | cut -d/ -f1)
      PUB_IP="$LOC_IP"
    fi
    
    if $INTERACTIVE; then
      # Ask for confirmation or new value from user (can be single IP or MetalLB range)
      read -rp "🌍 Enter your public IP or MetalLB range [$PUB_IP]: " USER_INPUT
      USER_INPUT="${USER_INPUT:-$PUB_IP}"
      
      # Check if user provided a MetalLB range or single IP
      if [[ "$USER_INPUT" == *"-"* ]]; then
        # User provided a range (contains hyphen)
        if is_valid_metallb_range "$USER_INPUT"; then
          METALLB_RANGES="$USER_INPUT"
          info "Using MetalLB range: $METALLB_RANGES"
          # Extract first IP for scenario detection
          PUB_IP=$(echo "$USER_INPUT" | cut -d',' -f1 | cut -d'-' -f1 | xargs)
        else
          err "Invalid MetalLB range format. Cannot proceed."
          exit 1
        fi
      elif is_valid_ip "$USER_INPUT"; then
        # User provided a single IP - convert to range format for MetalLB
        PUB_IP="$USER_INPUT"
        METALLB_RANGES="${PUB_IP}-${PUB_IP}"
        info "Converting single IP to MetalLB range: $METALLB_RANGES"
      else
        err "Invalid IP or MetalLB range format. Cannot proceed."
        exit 1
      fi
    else
      # Non-interactive mode, validate single IP
      if is_empty "$PUB_IP" || ! is_valid_ip "$PUB_IP"; then
        err "Invalid public IP. Cannot proceed."
        exit 1
      fi
    fi
    
    # NEW: Determine if we are in Cloud or On-Premises scenario
    LOCAL_IP=$(echo "$LOC_CIDR" | cut -d/ -f1)
    IS_CLOUD_PUBLIC=false
    IS_ONPREMISES_PUBLIC=false
    
    # Check if the public IP is actually assigned to a local interface
    if ip addr show | grep -q "$PUB_IP"; then
      IS_CLOUD_PUBLIC=true
      info "Detected scenario: CLOUD PUBLIC (public IP assigned directly to machine)"
      info "Configuration: Standard for cloud providers (AWS, GCP, Azure, etc.)"
      info "Ingress: Accessible directly from internet on $PUB_IP"
    else
      IS_ONPREMISES_PUBLIC=true
      info "Detected scenario: ON-PREMISES PUBLIC (public IP belongs to router/gateway)"
      info "Configuration: Optimized for NAT/port forwarding"
      info "Local machine IP: $LOCAL_IP"
      info "Router public IP: $PUB_IP"
      info "Ingress: Accessible from internet via router port forwarding"
      
      # Check if the public IP is reachable (optional test)
      if ping -c 1 -W 3 "$PUB_IP" >/dev/null 2>&1; then
        info "✓ Public IP ($PUB_IP) reachable - NAT configuration working"
      else
        warn "⚠ Public IP ($PUB_IP) not reachable from this machine"
        warn "  This is normal in NAT/router configurations"
        warn "  Make sure port forwarding is configured correctly"
      fi
    fi
    
    # Set METALLB_RANGES only if not already set by user input
    if [[ -z "${METALLB_RANGES:-}" ]]; then
      METALLB_RANGES="${PUB_IP}-${PUB_IP}"
    fi
    ;;

  *)
    # SHOULD NEVER HAPPEN, but if it does fallback to LAN
    warn "Unexpected mode '$ACCESS_MODE': using 'lan' and asking for manual pool."
    read -rp "🌐 MetalLB Pool: " METALLB_RANGES
    ;;

esac
ok "MetalLB pool configured: $METALLB_RANGES"
# endregion 13) MetalLB pool calculation based on mode, with always fallback

# region 13.5) Remote cluster access configuration
REMOTE_ACCESS="yes"  # Default: enable remote access
if $INTERACTIVE; then
  echo ""
  echo -e "${BLUE}🔐 CLUSTER ACCESS CONFIGURATION${NC}"
  echo -e "${YELLOW}By default, the Kubernetes cluster will be accessible remotely.${NC}"
  echo -e "${YELLOW}This allows managing the cluster from other computers with kubectl.${NC}"
  echo ""
  echo -e "${GREEN}✅ Remote access enabled:${NC}"
  echo -e "   • Cluster management from other PCs"
  echo -e "   • Integration with remote development tools"
  echo -e "   • Automatic deployments from CI/CD"
  echo ""
  echo -e "${RED}⚠️  Remote access disabled:${NC}"
  echo -e "   • Local access only (SSH + kubectl on machine)"
  echo -e "   • Higher security but less flexibility"
  echo ""
  
  while :; do
    read -rp "🌐 Enable remote cluster access? [Y/n] (default: Y): " choice
    choice="${choice,,}"
    if [[ -z "$choice" || "$choice" == "y" || "$choice" == "yes" ]]; then
      REMOTE_ACCESS="yes"
      break
    elif [[ "$choice" == "n" || "$choice" == "no" ]]; then
      REMOTE_ACCESS="no"
      break
    else
      warn "Invalid choice: enter 'y' for yes or 'n' for no."
    fi
  done
else
  info "Non-interactive: remote access enabled by default"
fi

if [[ "$REMOTE_ACCESS" == "yes" ]]; then
  ok "Remote cluster access: ENABLED"
  info "The cluster will be accessible remotely after installation"
else
  warn "Remote cluster access: DISABLED"
  info "The cluster will be accessible only locally (SSH required)"
fi
# endregion 13.5) Remote cluster access configuration

# region 14) Hostname setup (moved to separate module)
# Hostname setup is now handled by hostname_setup.sh module
# NEW_HOSTNAME should be available from that module
if [[ -z "${NEW_HOSTNAME:-}" ]]; then
  NEW_HOSTNAME=$(hostname)
  warn "NEW_HOSTNAME not set, using current hostname: $NEW_HOSTNAME"
fi
# endregion 14) Hostname setup