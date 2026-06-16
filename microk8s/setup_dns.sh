#!/usr/bin/env bash
#─────────────────────────────────────────────────────────────────────────────
# setup_dns.sh – Complete DNS management for local machine in enterprise environment - LAN ONLY MODE
# Usage: sudo ./setup_dns.sh [test|install|enable-network|disable-network|status]
#─────────────────────────────────────────────────────────────────────────────

# OS Detection
OS_TYPE="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  OS_TYPE="linux"
elif [[ "$OSTYPE" == "darwin"* ]]; then
  OS_TYPE="macos"
fi

# Colors for output (with multi-OS support)
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  # Use tput if available (more compatible)
  BLUE=$(tput setaf 4)
  GREEN=$(tput setaf 2) 
  YELLOW=$(tput setaf 3)
  RED=$(tput setaf 1)
  NC=$(tput sgr0)
else
  # Fallback to ANSI codes
  BLUE="\033[94m"
  GREEN="\033[32m"
  YELLOW="\033[33m"
  RED="\033[31m"
  NC="\033[0m"
fi

# Logging functions (without echo -e for better compatibility)
info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
ok() { printf "${GREEN}[✓]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[⚠]${NC} %s\n" "$1"; }
err() { printf "${RED}[✗]${NC} %s\n" "$1"; }

# Functions for multi-OS network detection
get_local_ip() {
  if [ "$OS_TYPE" = "linux" ]; then
    hostname -I | awk '{print $1}' 2>/dev/null
  elif [ "$OS_TYPE" = "macos" ]; then
    ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n1 2>/dev/null
  else
    echo "127.0.0.1"
  fi
}

get_gateway_ip() {
  if [ "$OS_TYPE" = "linux" ]; then
    ip route | grep default | awk '{print $3}' | head -n1 2>/dev/null
  elif [ "$OS_TYPE" = "macos" ]; then
    route -n get default 2>/dev/null | grep gateway | awk '{print $2}' | head -n1
  else
    echo "192.168.1.1"
  fi
}

# Global variables
HOSTNAME=$(hostname | sed 's/\.local$//')  # Remove .local if present
CURRENT_IP=$(get_local_ip)
GATEWAY_IP=$(get_gateway_ip)
DNSMASQ_CONF="/etc/dnsmasq.conf"
DNSMASQ_HOSTS="/etc/dnsmasq.hosts"

# Directory for backups
BACKUP_DIR="/var/lib/lair-dns-backups"
BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Enhanced Kubernetes detection
K8S_TYPE="none"
KUBECTL_CMD="kubectl"

detect_kubernetes() {
  # Detect MicroK8s
  if command -v microk8s >/dev/null 2>&1 || systemctl is-active snap.microk8s.daemon-containerd >/dev/null 2>&1; then
    K8S_TYPE="microk8s"
    KUBECTL_CMD="microk8s kubectl"
    return
  fi
  
  # Detect K3s
  if command -v k3s >/dev/null 2>&1 || systemctl is-active k3s >/dev/null 2>&1; then
    K8S_TYPE="k3s"
    KUBECTL_CMD="k3s kubectl"
    return
  fi
  
  # Detect vanilla K8s
  if command -v kubectl >/dev/null 2>&1; then
    # Check if kubectl is configured and working
    if kubectl version --short >/dev/null 2>&1; then
      K8S_TYPE="k8s"
      KUBECTL_CMD="kubectl"
      return
    fi
  fi
  
  # Check if there are running pods (alternative method)
  if [ -S /var/run/docker.sock ] || [ -S /var/run/containerd/containerd.sock ]; then
    if docker ps 2>/dev/null | grep -q "kube-apiserver\|k3s\|microk8s" || \
       crictl ps 2>/dev/null | grep -q "kube-apiserver\|coredns"; then
      K8S_TYPE="k8s-detected"
      KUBECTL_CMD="kubectl"
    fi
  fi
}

# Check if port 53 is already in use
check_port_53() {
  local port_in_use=false
  local process_info=""
  
  # Method 1: ss
  if command -v ss >/dev/null 2>&1; then
    if ss -tuln | grep -q ":53 "; then
      port_in_use=true
      process_info=$(ss -tulnp 2>/dev/null | grep ":53 " | head -n1)
    fi
  # Method 2: netstat
  elif command -v netstat >/dev/null 2>&1; then
    if netstat -tuln | grep -q ":53 "; then
      port_in_use=true
      process_info=$(netstat -tulnp 2>/dev/null | grep ":53 " | head -n1)
    fi
  fi
  
  if [ "$port_in_use" = true ]; then
    warn "Port 53 already in use!"
    if [ -n "$process_info" ]; then
      info "Process: $process_info"
    fi
    
    # Identify the service
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
      info "systemd-resolved is active and might be using port 53"
    fi
    
    if [ "$K8S_TYPE" != "none" ]; then
      info "Kubernetes detected ($K8S_TYPE) - CoreDNS might be using port 53"
    fi
    
    return 0
  else
    return 1
  fi
}

# Check OS compatibility
check_os_compatibility() {
  if [ "$OS_TYPE" != "linux" ]; then
    echo ""
    warn "⚠️  WARNING: This script is designed for Linux systems"
    warn "You are running on: $OSTYPE"
    warn "Some features might not work correctly"
    echo ""
    if [ "$OS_TYPE" = "macos" ]; then
      info "On macOS, this script is mainly for TESTING"
      info "Real installation should be done on Linux systems"
    fi
    echo ""
  fi
}

# Help function
show_help() {
  check_os_compatibility
  
  printf "${BLUE}=== DNS SETUP FOR ENTERPRISE ENVIRONMENT ===${NC}\n"
  echo ""
  printf "${GREEN}Usage:${NC} sudo $0 [command]\n"
  echo ""
  printf "${YELLOW}🚀 RECOMMENDED SETUP PROCESS (4 simple steps):${NC}\n"
  echo ""
  printf "${BLUE}Step 1:${NC} ${GREEN}sudo $0 test${NC}           → Check current DNS status (should show: NOT WORKING)\n"
  printf "${BLUE}Step 2:${NC} ${GREEN}sudo $0 install${NC}        → Install wildcard DNS (*.hostname.local → your IP)\n"
  printf "${BLUE}Step 3:${NC} ${GREEN}sudo $0 test${NC}           → Verify DNS is working (should show: WORKING)\n"
  printf "${BLUE}Step 4:${NC} ${GREEN}sudo $0 enable-network${NC}  → Allow other devices to use this machine as DNS\n"
  echo ""
  printf "${YELLOW}📋 What you get:${NC}\n"
  printf "  • ${GREEN}*.${HOSTNAME}.local${NC} → $CURRENT_IP (any subdomain works)\n"
  printf "  • Examples: ${GREEN}n8n.${HOSTNAME}.local${NC}, ${GREEN}grafana.${HOSTNAME}.local${NC}\n"
  printf "  • Other LAN devices can use this machine as DNS server\n"
  echo ""
  printf "${YELLOW}Other commands:${NC}\n"
  printf "  ${GREEN}status${NC}           - Show current status\n"
  printf "${YELLOW}Network management:${NC}\n"
  printf "  ${GREEN}enable-network${NC}   - Enable DNS for other devices\n"
  printf "  ${GREEN}disable-network${NC}  - Disable network DNS (local only)\n"
  echo ""
  printf "${YELLOW}Backup and Restore:${NC}\n"
  printf "  ${GREEN}backup${NC}           - Save current configuration\n"
  printf "  ${GREEN}restore${NC}          - Restore original configuration\n"
  printf "  ${GREEN}list-backups${NC}     - Show available backups\n"
  echo ""
  printf "${YELLOW}Maintenance:${NC}\n"
  printf "  ${GREEN}restart${NC}          - Restart DNS services\n"
  printf "  ${GREEN}repair${NC}           - Repair DNS configuration after reboot\n"
  printf "  ${GREEN}logs${NC}             - Show DNS logs\n"
  printf "  ${GREEN}fix-microk8s${NC}     - Fix conflicts with MicroK8s/CoreDNS\n"
  printf "  ${GREEN}clean-systemd-resolved${NC} - Remove systemd-resolved delegation\n"
  echo ""
  printf "${YELLOW}Protection:${NC}\n"
  printf "  ${GREEN}protect-dns${NC}      - Protect resolv.conf from changes\n"
  printf "  ${GREEN}unprotect-dns${NC}    - Remove resolv.conf protection\n"
  echo ""
  printf "${YELLOW}Typical examples:${NC}\n"
  echo "  sudo $0 backup          # ALWAYS before install!"
  echo "  sudo $0 test            # Test configuration"
  echo "  sudo $0 install         # Complete installation"
  echo "  sudo $0 clean-systemd-resolved  # Remove delegation if needed"
  echo "  sudo $0 restore         # If something goes wrong"
  echo ""
  printf "${YELLOW}Configured wildcard DNS:${NC}\n"
  printf "  ${GREEN}*.${HOSTNAME}.local${NC} → $CURRENT_IP\n"
  echo "  Examples: n8n.${HOSTNAME}.local, grafana.${HOSTNAME}.local, etc."
  
  # Show K8s status if detected
  detect_kubernetes
  if [ "$K8S_TYPE" != "none" ]; then
    echo ""
    printf "${YELLOW}Kubernetes detected:${NC} $K8S_TYPE\n"
    info "Script will configure DNS to coexist with CoreDNS"
  fi
}

# Quick DNS test
test_dns() {
  check_os_compatibility
  
  echo -e "${BLUE}=== QUICK DNS TEST ===${NC}"
  info "Hostname: $HOSTNAME.local"
  info "Local IP: $CURRENT_IP"
  info "Gateway: $GATEWAY_IP"
  info "Wildcard: *.${HOSTNAME}.local → $CURRENT_IP"
  echo ""
  
  # Test local resolution
  echo -e "${YELLOW}Local resolution test (.local):${NC}"
  local local_ok=0
  
  # Test base hostname
  if ping -c 1 -W 2 "${HOSTNAME}.local" >/dev/null 2>&1; then
    ok "${HOSTNAME}.local ✓"
    ((local_ok++))
  else
    err "${HOSTNAME}.local ✗"
  fi
  
  # Test wildcard with examples
  for subdomain in "n8n" "test" "any-service"; do
    if ping -c 1 -W 2 "${subdomain}.${HOSTNAME}.local" >/dev/null 2>&1; then
      ok "${subdomain}.${HOSTNAME}.local ✓ (wildcard)"
      ((local_ok++))
    else
      err "${subdomain}.${HOSTNAME}.local ✗ (wildcard)"
    fi
  done
  
  # Test internet resolution
  echo ""
  echo -e "${YELLOW}Internet resolution test:${NC}"
  local internet_ok=0
  for domain in "google.com" "github.com"; do
    if ping -c 1 -W 3 "$domain" >/dev/null 2>&1; then
      ok "$domain ✓"
      ((internet_ok++))
    else
      err "$domain ✗"
    fi
  done
  
  # Result
  echo ""
  echo -e "${BLUE}=== RESULT ===${NC}"
  if [ $local_ok -ge 2 ]; then
    ok "Local wildcard DNS: WORKING"
    info "Any *.${HOSTNAME}.local points to $CURRENT_IP"
  else
    err "Local wildcard DNS: NOT WORKING"
    echo -e "  ${YELLOW}→ Run: sudo $0 install${NC}"
  fi
  
  if [ $internet_ok -eq 2 ]; then
    ok "Internet DNS: WORKING"
  else
    warn "Internet DNS: ISSUES (check connection)"
  fi
  
  # Additional DNS status check for MicroK8s
  detect_kubernetes
  DNS_PORT=53
  if [ "$K8S_TYPE" != "none" ] && [ -f "$DNSMASQ_CONF" ] && grep -q "^port=5353" "$DNSMASQ_CONF"; then
    DNS_PORT=5353
    info "dnsmasq configured on port 5353 (Kubernetes compatible mode)"
  fi
  
  # Recommendations
  echo ""
  echo -e "${YELLOW}=== NEXT STEPS ===${NC}"
  if [ $local_ok -lt 2 ]; then
    echo -e "1. ${GREEN}sudo $0 install${NC}          - Configure wildcard DNS"
    echo -e "2. ${GREEN}sudo $0 enable-network${NC}   - For other devices"
    if [ "$K8S_TYPE" != "none" ]; then
      echo -e "   ${YELLOW}Note: Will use port $DNS_PORT to coexist with MicroK8s CoreDNS${NC}"
    fi
  else
    echo -e "1. ${GREEN}sudo $0 enable-network${NC}   - For other PCs/tablets"
    if [ $DNS_PORT -eq 5353 ]; then
      echo -e "   ${YELLOW}⚠️  Other devices will need to use port 5353${NC}"
      echo -e "   ${YELLOW}   Configure DNS as: ${CURRENT_IP}:5353${NC}"
    fi
    echo "2. Configure services on different ports and use names like:"
    echo -e "   ${GREEN}http://n8n.${HOSTNAME}.local:8080${NC}"
    echo -e "   ${GREEN}http://grafana.${HOSTNAME}.local:3000${NC}"
    if [ $DNS_PORT -eq 5353 ]; then
      echo -e "   ${YELLOW}Note: Using port 5353 for DNS (MicroK8s compatibility)${NC}"
    fi
  fi
}

# Complete installation
install_dns() {
  printf "${BLUE}=== ENTERPRISE DNS INSTALLATION ===${NC}\n"
  
  # Check root
  if [ "$(id -u)" -ne 0 ]; then
    err "This command must be run as root"
    exit 1
  fi
  
  # Detect Kubernetes before proceeding
  detect_kubernetes
  
  # Check port 53 conflicts
  if check_port_53; then
    warn "Detected conflict on port 53"
    if [ "$K8S_TYPE" != "none" ]; then
      info "Kubernetes is present, will configure DNS to coexist"
    else
      warn "May need to disable systemd-resolved or other DNS services"
    fi
  fi
  
  # Automatic backup before installation
  printf "${YELLOW}=== AUTOMATIC BACKUP ===${NC}\n"
  info "Creating safety backup before installation..."
  create_backup
  
  printf "\n${BLUE}=== INSTALLATION ===${NC}\n"
  
  # Detect gateway DNS
  info "Detecting network configuration..."
  GATEWAY_DNS=""
  if [ -f /etc/resolv.conf ]; then
    GATEWAY_DNS=$(grep "^nameserver" /etc/resolv.conf | grep -v "127.0.0.1" | awk '{print $2}' | head -n1)
  fi
  
  if [ -z "$GATEWAY_DNS" ]; then
    GATEWAY_DNS="$GATEWAY_IP"
  fi
  
  if [ -z "$GATEWAY_DNS" ]; then
    GATEWAY_DNS="8.8.8.8"
  fi
  
  info "Gateway DNS detected: $GATEWAY_DNS"
  
  # Install packages
  info "Installing required packages..."
  apt update -y >/dev/null 2>&1
  apt install -y dnsmasq avahi-daemon avahi-utils libnss-mdns >/dev/null 2>&1
  
  # Configure Avahi for mDNS
  info "Configuring Avahi..."
  cat > /etc/avahi/avahi-daemon.conf << EOF
[server]
host-name=$HOSTNAME
domain-name=local
use-ipv4=yes
use-ipv6=no
enable-dbus=yes

[publish]
publish-addresses=yes
publish-domain=yes
EOF
  
  # Configure dnsmasq (intelligent DNS forwarder)
  info "Configuring DNS forwarder..."
  cp "$DNSMASQ_CONF" "${DNSMASQ_CONF}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  
  if [ "$K8S_TYPE" != "none" ]; then
    # With Kubernetes: listen ONLY on external IP, not on localhost
    info "Kubernetes detected ($K8S_TYPE) - compatible configuration"
    cat > "$DNSMASQ_CONF" << EOF
# DNS Forwarder for ${HOSTNAME} - Enterprise Environment (Kubernetes compatible)
# Generated on $(date)

# === BINDING AND INTERFACES ===
# With Kubernetes, we listen ONLY on external IP to avoid conflicts
# Use bind-dynamic for automatic IP resolution on network changes
bind-dynamic
listen-address=${CURRENT_IP}
# DO NOT listen on localhost to avoid interfering with CoreDNS

# === LOCAL RESOLUTION ===
# .local domains are never forwarded
local=/local/
domain-needed
bogus-priv

# === WILDCARD DNS ===
# Wildcard resolution: any *.hostname.local points to machine IP
address=/${HOSTNAME}.local/${CURRENT_IP}
address=/.${HOSTNAME}.local/${CURRENT_IP}

# === UPSTREAM DNS ===
server=${GATEWAY_DNS}      # Gateway/Router
server=1.1.1.1            # Cloudflare
server=8.8.8.8            # Google

# === SETTINGS ===
local=/local/
domain-needed
bogus-priv
cache-size=1000
EOF
  else
    # Without Kubernetes: standard configuration
    cat > "$DNSMASQ_CONF" << EOF
# DNS Forwarder for ${HOSTNAME} - Enterprise Environment
# Generated on $(date)

# === BINDING AND INTERFACES ===
# Use bind-dynamic for automatic IP resolution on network changes
bind-dynamic
interface=lo
# To enable other devices, uncomment:
#listen-address=${CURRENT_IP}

# === LOCAL RESOLUTION ===
# .local domains are never forwarded
local=/local/
domain-needed
bogus-priv

# === WILDCARD DNS ===
# Wildcard resolution: any *.hostname.local points to machine IP
address=/${HOSTNAME}.local/${CURRENT_IP}
address=/.${HOSTNAME}.local/${CURRENT_IP}

# === UPSTREAM DNS ===
server=${GATEWAY_DNS}      # Gateway/Router
server=1.1.1.1            # Cloudflare
server=8.8.8.8            # Google

# Don't forward .local
server=/local/

# === PERFORMANCE ===
cache-size=1000
neg-ttl=60
max-ttl=3600

# === SECURITY ===
domain-needed
bogus-priv
EOF
  fi
  
  # No need for separate hosts file - everything handled by wildcard
  info "Configuring wildcard DNS..."
  info "All services *.${HOSTNAME}.local will point to ${CURRENT_IP}"
  
  # Configure system resolution
  info "Configuring system resolution..."
  
  # Check if Kubernetes is installed
  if [ "$K8S_TYPE" != "none" ]; then
    warn "Kubernetes detected ($K8S_TYPE) - configuring DNS integration"
    info "Local DNS will continue to use Kubernetes CoreDNS"
    info "Other LAN devices can use this DNS server"
    
    # Configure systemd-resolved to delegate .local domains to dnsmasq
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
      info "Configuring systemd-resolved to delegate .local domains to dnsmasq..."
      
      # Create systemd-resolved configuration for .local delegation
      mkdir -p /etc/systemd/resolved.conf.d/
      
      cat > /etc/systemd/resolved.conf.d/local-dns.conf << EOF
[Resolve]
# Delegate .local domains to dnsmasq for wildcard DNS
DNS=${CURRENT_IP}#53
Domains=~local
EOF
      
      # Restart systemd-resolved to apply configuration
      systemctl restart systemd-resolved >/dev/null 2>&1
      ok "systemd-resolved configured to use dnsmasq for .local domains"
      info "Wildcard DNS *.${HOSTNAME}.local will be handled by dnsmasq"
    else
      info "systemd-resolved not active - no additional configuration needed"
    fi
  else
    # Only if Kubernetes is NOT installed, modify resolv.conf
    # SYSTEMD-RESOLVED COMPATIBILITY CHECK
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
      # systemd-resolved is active - test if it works
      if timeout 5 nslookup google.com >/dev/null 2>&1; then
        warn "systemd-resolved active and working - NOT modifying resolv.conf"
        info "System will use systemd-resolved + dnsmasq in coexistent configuration"
      else
        info "systemd-resolved active but not working - configuring manual resolv.conf"
        # Backup and modify
        if [ -f /etc/resolv.conf ]; then
          cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
        fi
        
        chattr -i /etc/resolv.conf 2>/dev/null || true
        cat > /etc/resolv.conf << EOF
# DNS for ${HOSTNAME} - Enterprise system
nameserver 127.0.0.1     # Local DNS (this machine)
nameserver ${GATEWAY_DNS} # Upstream DNS (gateway)
search local
EOF
      fi
    else
      # systemd-resolved not active - normal configuration
      if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf /etc/resolv.conf.backup.$(date +%Y%m%d_%H%M%S)
      fi
      
      chattr -i /etc/resolv.conf 2>/dev/null || true
      cat > /etc/resolv.conf << EOF
# DNS for ${HOSTNAME} - Enterprise system
nameserver 127.0.0.1     # Local DNS (this machine)
nameserver ${GATEWAY_DNS} # Upstream DNS (gateway)
search local
EOF
    fi
  fi
  
  # Configure nsswitch for mDNS
  if ! grep -q "mdns" /etc/nsswitch.conf; then
    cp /etc/nsswitch.conf /etc/nsswitch.conf.backup
    sed -i 's/^hosts:.*/hosts:          files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf
  fi
  
  # Configure systemd service dependencies for reboot resilience
  info "Configuring service dependencies for reboot resilience..."
  
  # Create systemd override for dnsmasq to wait for network
  mkdir -p /etc/systemd/system/dnsmasq.service.d/
  cat > /etc/systemd/system/dnsmasq.service.d/wait-network.conf << EOF
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
Restart=on-failure
RestartSec=5
EOF
  
  # Create DNS check service for post-boot validation
  cat > /etc/systemd/system/lair-dns-check.service << EOF
[Unit]
Description=LAIR DNS Configuration Check and Repair
After=network-online.target dnsmasq.service avahi-daemon.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$(realpath $0) repair
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
  
  # Reload systemd and enable services
  systemctl daemon-reload >/dev/null 2>&1
  systemctl enable dnsmasq avahi-daemon lair-dns-check >/dev/null 2>&1
  
  # Start services with intelligent conflict resolution
  info "Starting DNS services..."
  
  # Intelligent startup for MicroK8s compatibility
  if [ "$K8S_TYPE" != "none" ]; then
    info "Starting dnsmasq in Kubernetes-compatible mode..."
    
    # Try normal startup first
    systemctl restart avahi-daemon >/dev/null 2>&1
    systemctl restart dnsmasq >/dev/null 2>&1
    sleep 2
    
    # Check if dnsmasq started successfully
    if ! systemctl is-active dnsmasq >/dev/null 2>&1; then
      warn "dnsmasq failed to start on port 53, trying automatic conflict resolution..."
      
      # Check what's using port 53
      PORT_53_USER=$(ss -tulnp 2>/dev/null | grep ":53 " | head -n1 | awk '{print $NF}' || echo "unknown")
      info "Port 53 occupied by: $PORT_53_USER"
      
      # Configure dnsmasq to use alternative port 5353
      info "Configuring dnsmasq to use port 5353 to coexist with CoreDNS..."
      echo "port=5353" >> "$DNSMASQ_CONF"
      
      # Restart with new configuration
      systemctl restart dnsmasq >/dev/null 2>&1
      sleep 2
      
      if systemctl is-active dnsmasq >/dev/null 2>&1; then
        ok "dnsmasq started successfully on port 5353"
        warn "⚠️  IMPORTANT: DNS wildcard uses port 5353 due to CoreDNS conflict"
        warn "   Other devices should use: ${CURRENT_IP}:5353 as DNS server"
        warn "   Example: nslookup ${HOSTNAME}.local ${CURRENT_IP} -port=5353"
      else
        err "dnsmasq failed to start even on port 5353"
        journalctl -u dnsmasq -n 5 --no-pager | tail -n 3
      fi
    else
      ok "dnsmasq started successfully on port 53"
    fi
  else
    # Standard startup for non-Kubernetes systems
    systemctl restart dnsmasq avahi-daemon >/dev/null 2>&1
  fi
  
  # Verify installation
  sleep 3
  if systemctl is-active dnsmasq >/dev/null && systemctl is-active avahi-daemon >/dev/null; then
    if [ "$K8S_TYPE" != "none" ] && grep -q "^port=5353" "$DNSMASQ_CONF"; then
      ok "DNS installed and configured correctly on port 5353 (Kubernetes compatible)!"
    else
      ok "DNS installed and configured correctly!"
    fi
    
    # Additional protections for persistence
    if [ "$K8S_TYPE" = "none" ]; then
      # SYSTEMD-RESOLVED COMPATIBILITY CHECK
      # Don't disable systemd-resolved if it's configured correctly and working
      if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        # Test if systemd-resolved is working correctly
        if timeout 5 nslookup google.com >/dev/null 2>&1; then
          warn "systemd-resolved ACTIVE and working - NOT disabling it"
          warn "To avoid conflicts, dnsmasq will use an alternative port"
          info "Local DNS: dnsmasq on port 5353, systemd-resolved on port 53"
          
          # Configure dnsmasq to use alternative port
          if ! grep -q "^port=5353" "$DNSMASQ_CONF"; then
            echo "port=5353" >> "$DNSMASQ_CONF"
            systemctl restart dnsmasq
          fi
          
          warn "⚠️  IMPORTANT: Other devices will need to use port 5353"
          warn "   Example: nslookup ${HOSTNAME}.local ${CURRENT_IP} -port=5353"
        else
          info "systemd-resolved active but not working - disabling it"
          systemctl disable --now systemd-resolved >/dev/null 2>&1
          
          # Recreate resolv.conf only if necessary
          if [ -L /etc/resolv.conf ] || ! grep -q "nameserver 127.0.0.1" /etc/resolv.conf 2>/dev/null; then
            chattr -i /etc/resolv.conf 2>/dev/null || true
            rm -f /etc/resolv.conf
            echo "# DNS for ${HOSTNAME} - Enterprise system" > /etc/resolv.conf
            echo "nameserver 127.0.0.1     # Local DNS (this machine)" >> /etc/resolv.conf
            echo "nameserver ${GATEWAY_DNS} # Upstream DNS (gateway)" >> /etc/resolv.conf
            echo "search local" >> /etc/resolv.conf
          fi
        fi
      fi
      
      # Protect resolv.conf from changes only if not managed by systemd-resolved
      if ! systemctl is-active systemd-resolved >/dev/null 2>&1; then
        info "Protecting resolv.conf file..."
        chattr +i /etc/resolv.conf 2>/dev/null || true
        ok "resolv.conf file protected from system changes"
        
        # Additional protection against NetworkManager and DHCP overwrites
        info "Configuring additional DNS protection..."
        
        # Configure NetworkManager to not manage DNS
        mkdir -p /etc/NetworkManager/conf.d/
        cat > /etc/NetworkManager/conf.d/90-dns-none.conf << EOF
# Prevent NetworkManager from overwriting DNS configuration
# Generated by LAIR DNS setup script
[main]
dns=none
EOF
        
        # Create dhclient hook to prevent DNS updates
        mkdir -p /etc/dhcp/dhclient-enter-hooks.d/
        cat > /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate << 'EOF'
#!/bin/bash
# Prevent dhclient from updating DNS configuration
# Generated by LAIR DNS setup script
make_resolv_conf() {
    # Override function to prevent DNS updates
    return 0
}
EOF
        chmod +x /etc/dhcp/dhclient-enter-hooks.d/nodnsupdate
        
        # Restart NetworkManager if active to apply configuration
        if systemctl is-active NetworkManager >/dev/null 2>&1; then
          systemctl restart NetworkManager >/dev/null 2>&1
          info "NetworkManager reconfigured to preserve DNS settings"
        fi
        
        ok "Enhanced DNS protection configured for reboot resilience"
      else
        info "resolv.conf managed by systemd-resolved - not protected"
      fi
    fi
    
    # Verify that services are really enabled
    for service in dnsmasq avahi-daemon; do
      if systemctl is-enabled "$service" >/dev/null 2>&1; then
        ok "$service enabled at startup"
      else
        warn "$service NOT enabled at startup - re-enabling"
        systemctl enable "$service" >/dev/null 2>&1
      fi
    done
    
    printf "\n${GREEN}=== SERVICES CONFIGURED ===${NC}\n"
    printf "\n${BLUE}=== REBOOT RESILIENCE ===${NC}\n"
    ok "✅ Service dependencies configured for automatic startup"
    ok "✅ Post-boot validation service enabled (lair-dns-check)"
    ok "✅ Enhanced protection against DNS configuration overwrites"
    ok "✅ Dynamic IP address handling configured"
    printf "\n${YELLOW}=== NEXT STEPS ===${NC}\n"
    printf "1. Test: ${GREEN}sudo $0 test${NC}\n"
    printf "2. For other PCs: ${GREEN}sudo $0 enable-network${NC}\n"
    printf "3. Verify: ${GREEN}sudo $0 status${NC}\n"
    printf "\n${CYAN}=== REBOOT TEST ===${NC}\n"
    printf "Your DNS configuration is now resilient to reboots.\n"
    printf "After reboot, DNS should work automatically.\n"
    printf "If issues occur: ${GREEN}sudo $0 repair${NC}\n"
    
  else
    err "Installation error. Check the logs:"
    echo "  sudo journalctl -u dnsmasq -n 20"
    echo "  sudo journalctl -u avahi-daemon -n 20"
  fi
}

# Services status
show_status() {
  printf "${BLUE}=== DNS SYSTEM STATUS ===${NC}\n"
  
  # Detect Kubernetes
  detect_kubernetes
  if [ "$K8S_TYPE" != "none" ]; then
    info "Kubernetes: $K8S_TYPE"
  fi
  
  # Services
  printf "${YELLOW}Services:${NC}\n"
  for service in dnsmasq avahi-daemon; do
    if systemctl is-active "$service" >/dev/null 2>&1; then
      ok "$service: ACTIVE"
    else
      err "$service: NOT ACTIVE"
    fi
  done
  
  # Ports
  printf "\n${YELLOW}DNS Ports:${NC}\n"
  if ss -tuln | grep -q ":53 "; then
    ok "Port 53: LISTENING"
  else
    err "Port 53: NOT LISTENING"
  fi
  
  # Network configuration
  printf "\n${YELLOW}Network access:${NC}\n"
  if [ -f "$DNSMASQ_CONF" ]; then
    if grep -q "^listen-address=${CURRENT_IP}" "$DNSMASQ_CONF" >/dev/null 2>&1; then
      ok "Other devices: CAN use this DNS"
    else
      warn "Other devices: CANNOT use this DNS"
      info "To enable: sudo $0 enable-network"
    fi
  fi
  
  # Wildcard DNS
  printf "\n${YELLOW}Wildcard DNS:${NC}\n"
  if [ -f "$DNSMASQ_CONF" ] && grep -q "address=/\.${HOSTNAME}\.local/" "$DNSMASQ_CONF"; then
    ok "Wildcard *.${HOSTNAME}.local → $CURRENT_IP configured"
    info "Examples: n8n.${HOSTNAME}.local, grafana.${HOSTNAME}.local"
  else
    warn "Wildcard DNS not configured"
  fi
  
  # resolv.conf protection
  printf "\n${YELLOW}Configuration protection:${NC}\n"
  if [ "$K8S_TYPE" = "none" ] && lsattr /etc/resolv.conf 2>/dev/null | grep -q "i-"; then
    ok "/etc/resolv.conf protected from changes (immutable)"
  elif [ "$K8S_TYPE" != "none" ]; then
    info "/etc/resolv.conf managed by Kubernetes/CoreDNS"
  else
    warn "/etc/resolv.conf NOT protected - could be overwritten on reboot"
    info "To protect: sudo chattr +i /etc/resolv.conf"
  fi
  
  # systemd-resolved integration
  printf "\n${YELLOW}systemd-resolved integration:${NC}\n"
  if systemctl is-active systemd-resolved >/dev/null 2>&1; then
    if [ -f /etc/systemd/resolved.conf.d/local-dns.conf ]; then
      ok "systemd-resolved ACTIVE with .local delegation configured"
      info "Wildcard DNS delegated to dnsmasq for *.${HOSTNAME}.local"
    elif [ "$K8S_TYPE" != "none" ]; then
      warn "systemd-resolved ACTIVE but .local delegation NOT configured"
      info "Run: sudo $0 install (to fix delegation)"
    else
      warn "systemd-resolved ACTIVE - might interfere with dnsmasq"
      info "Consider: sudo systemctl disable --now systemd-resolved"
    fi
  else
    ok "systemd-resolved: NOT ACTIVE"
  fi
}

# Enable network access
enable_network() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Command requires root privileges"
    exit 1
  fi
  
  info "Enabling DNS access from other devices..."
  
  if [ ! -f "$DNSMASQ_CONF" ]; then
    err "DNS not installed. Run first: sudo $0 install"
    exit 1
  fi
  
  # Detect Kubernetes
  detect_kubernetes
  
  # Check if Kubernetes is installed
  if [ "$K8S_TYPE" != "none" ]; then
    ok "With Kubernetes, DNS is already enabled on the network!"
    info "dnsmasq listening on ${CURRENT_IP}:53"
  else
    # Without Kubernetes: enable listen-address
    sed -i "s/#listen-address=${CURRENT_IP}/listen-address=${CURRENT_IP}/" "$DNSMASQ_CONF"
    if ! grep -q "^listen-address=${CURRENT_IP}" "$DNSMASQ_CONF"; then
      echo "listen-address=${CURRENT_IP}" >> "$DNSMASQ_CONF"
    fi
    
    systemctl restart dnsmasq
  fi
  
  if systemctl is-active dnsmasq >/dev/null; then
    ok "Network DNS enabled!"
    
    printf "\n${GREEN}=== OTHER DEVICES CONFIGURATION ===${NC}\n"
    printf "${YELLOW}On office PCs/laptops/tablets set:${NC}\n"
    printf "  Primary DNS:   ${GREEN}$CURRENT_IP${NC}\n"
    printf "  Secondary DNS: ${GREEN}$GATEWAY_IP${NC}\n"
    echo ""
    printf "${YELLOW}Test from another device:${NC}\n"
    printf "  ${GREEN}nslookup ${HOSTNAME}.local $CURRENT_IP${NC}\n"
    printf "  ${GREEN}ping n8n.${HOSTNAME}.local${NC}\n"
  else
    err "Error restarting dnsmasq"
  fi
}

# Disable network access
disable_network() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Command requires root privileges"
    exit 1
  fi
  
  info "Disabling DNS access from network..."
  sed -i "s/^listen-address=${CURRENT_IP}/#listen-address=${CURRENT_IP}/" "$DNSMASQ_CONF"
  systemctl restart dnsmasq
  ok "DNS limited to local machine only"
}

# Complete backup function
create_backup() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Command requires root privileges"
    exit 1
  fi
  
  printf "${BLUE}=== DNS CONFIGURATION BACKUP ===${NC}\n"
  info "Creating complete backup..."
  
  # Create backup directory
  mkdir -p "$BACKUP_DIR"
  
  # Backup with timestamp
  local backup_name="backup_${BACKUP_TIMESTAMP}"
  local backup_path="${BACKUP_DIR}/${backup_name}"
  
  mkdir -p "$backup_path"
  
  # Save configuration files
  info "Saving configuration files..."
  
  # resolv.conf
  if [ -f /etc/resolv.conf ]; then
    cp /etc/resolv.conf "${backup_path}/resolv.conf"
    ok "Saved: /etc/resolv.conf"
  fi
  
  # nsswitch.conf
  if [ -f /etc/nsswitch.conf ]; then
    cp /etc/nsswitch.conf "${backup_path}/nsswitch.conf"
    ok "Saved: /etc/nsswitch.conf"
  fi
  
  # dnsmasq.conf (if exists)
  if [ -f "$DNSMASQ_CONF" ]; then
    cp "$DNSMASQ_CONF" "${backup_path}/dnsmasq.conf"
    ok "Saved: $DNSMASQ_CONF"
  fi
  
  # avahi config (if exists)
  if [ -f /etc/avahi/avahi-daemon.conf ]; then
    mkdir -p "${backup_path}/avahi"
    cp /etc/avahi/avahi-daemon.conf "${backup_path}/avahi/avahi-daemon.conf"
    ok "Saved: /etc/avahi/avahi-daemon.conf"
  fi
  
  # systemd-resolved local-dns config (if exists)
  if [ -f /etc/systemd/resolved.conf.d/local-dns.conf ]; then
    mkdir -p "${backup_path}/systemd-resolved"
    cp /etc/systemd/resolved.conf.d/local-dns.conf "${backup_path}/systemd-resolved/local-dns.conf"
    ok "Saved: /etc/systemd/resolved.conf.d/local-dns.conf"
  fi
  
  # Services status
  info "Saving services status..."
  echo "# Services status at backup time" > "${backup_path}/services_status.txt"
  for service in dnsmasq avahi-daemon systemd-resolved; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
      echo "${service}=enabled" >> "${backup_path}/services_status.txt"
    else
      echo "${service}=disabled" >> "${backup_path}/services_status.txt"
    fi
    
    if systemctl is-active "$service" >/dev/null 2>&1; then
      echo "${service}_active=yes" >> "${backup_path}/services_status.txt"
    else
      echo "${service}_active=no" >> "${backup_path}/services_status.txt"
    fi
  done
  
  # System information
  echo "# System information at backup time" > "${backup_path}/system_info.txt"
  echo "hostname=$(hostname)" >> "${backup_path}/system_info.txt"
  echo "ip=$(hostname -I | awk '{print $1}')" >> "${backup_path}/system_info.txt"
  echo "gateway=$(ip route | grep default | awk '{print $3}' | head -n1)" >> "${backup_path}/system_info.txt"
  echo "timestamp=${BACKUP_TIMESTAMP}" >> "${backup_path}/system_info.txt"
  
  # Save symbolic link to latest backup
  ln -sfn "$backup_name" "${BACKUP_DIR}/latest"
  
  ok "Complete backup created: ${backup_path}"
  info "Quick link: ${BACKUP_DIR}/latest"
  
  printf "\n${YELLOW}=== BACKUP CONTENTS ===${NC}\n"
  ls -la "$backup_path"
}

# Complete restore function
restore_backup() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Command requires root privileges"
    exit 1
  fi
  
  printf "${BLUE}=== DNS CONFIGURATION RESTORE ===${NC}\n"
  
  # Find backup to use
  local backup_path=""
  if [ "$1" ]; then
    backup_path="${BACKUP_DIR}/$1"
  elif [ -L "${BACKUP_DIR}/latest" ]; then
    backup_path=$(readlink -f "${BACKUP_DIR}/latest")
  else
    err "No backup specified and no 'latest' backup found"
    info "Available backups:"
    ls -1 "$BACKUP_DIR" 2>/dev/null | grep "^backup_" || echo "No backups found"
    exit 1
  fi
  
  if [ ! -d "$backup_path" ]; then
    err "Backup not found: $backup_path"
    exit 1
  fi
  
  info "Restoring from: $backup_path"
  
  # User confirmation
  read -rp "⚠️  This will restore ALL DNS configuration. Continue? [y/N]: " confirm
  if [[ ! "$confirm" =~ ^([yY])$ ]]; then
    warn "Restore cancelled by user"
    exit 0
  fi
  
  # Stop services before restore
  info "Stopping DNS services..."
  systemctl stop dnsmasq 2>/dev/null || true
  systemctl stop avahi-daemon 2>/dev/null || true
  
  # Restore configuration files
  info "Restoring configuration files..."
  
  if [ -f "${backup_path}/resolv.conf" ]; then
    chattr -i /etc/resolv.conf 2>/dev/null || true  # Remove protection
    cp "${backup_path}/resolv.conf" /etc/resolv.conf
    ok "Restored: /etc/resolv.conf"
  fi
  
  if [ -f "${backup_path}/nsswitch.conf" ]; then
    cp "${backup_path}/nsswitch.conf" /etc/nsswitch.conf
    ok "Restored: /etc/nsswitch.conf"
  fi
  
  if [ -f "${backup_path}/dnsmasq.conf" ]; then
    cp "${backup_path}/dnsmasq.conf" "$DNSMASQ_CONF"
    ok "Restored: $DNSMASQ_CONF"
  fi
  
  if [ -f "${backup_path}/avahi/avahi-daemon.conf" ]; then
    cp "${backup_path}/avahi/avahi-daemon.conf" /etc/avahi/avahi-daemon.conf
    ok "Restored: /etc/avahi/avahi-daemon.conf"
  fi
  
  # Restore systemd-resolved configuration
  if [ -f "${backup_path}/systemd-resolved/local-dns.conf" ]; then
    mkdir -p /etc/systemd/resolved.conf.d/
    cp "${backup_path}/systemd-resolved/local-dns.conf" /etc/systemd/resolved.conf.d/local-dns.conf
    ok "Restored: /etc/systemd/resolved.conf.d/local-dns.conf"
  else
    # Remove the configuration if it wasn't in backup (clean restore)
    if [ -f /etc/systemd/resolved.conf.d/local-dns.conf ]; then
      rm -f /etc/systemd/resolved.conf.d/local-dns.conf
      ok "Removed: /etc/systemd/resolved.conf.d/local-dns.conf (not in backup)"
    fi
  fi
  
  # Restore services status
  if [ -f "${backup_path}/services_status.txt" ]; then
    info "Restoring services status..."
    
    while IFS='=' read -r service status; do
      case "$service" in
        dnsmasq|avahi-daemon|systemd-resolved)
          if [ "$status" = "enabled" ]; then
            systemctl enable "$service" >/dev/null 2>&1 || true
          else
            systemctl disable "$service" >/dev/null 2>&1 || true
          fi
          ;;
        *_active)
          service_name=${service%_active}
          if [ "$status" = "yes" ]; then
            systemctl start "$service_name" >/dev/null 2>&1 || true
          fi
          ;;
      esac
    done < "${backup_path}/services_status.txt"
  fi
  
  # Restart systemd-resolved if active (to apply any configuration changes)
  if systemctl is-active systemd-resolved >/dev/null 2>&1; then
    info "Restarting systemd-resolved to apply configuration changes..."
    systemctl restart systemd-resolved >/dev/null 2>&1 || true
  fi
  
  # Remove files created by our script
  info "Cleaning up script-created files..."
  rm -f "$DNSMASQ_HOSTS" 2>/dev/null || true
  rm -rf /etc/avahi/services/*-${HOSTNAME}.service 2>/dev/null || true
  
  ok "Restore completed!"
  
  printf "\n${YELLOW}=== RESTORE VERIFICATION ===${NC}\n"
  info "Check that everything is back to normal:"
  echo "  1. Test connection: ping google.com"
  echo "  2. Verify DNS: nslookup google.com"
  echo "  3. Reboot if necessary: sudo reboot"
}

# Function to list backups
list_backups() {
  printf "${BLUE}=== AVAILABLE BACKUPS ===${NC}\n"
  
  if [ ! -d "$BACKUP_DIR" ]; then
    warn "Backup directory not found: $BACKUP_DIR"
    return
  fi
  
  local backups=($(ls -1 "$BACKUP_DIR" 2>/dev/null | grep "^backup_" | sort -r))
  
  if [ ${#backups[@]} -eq 0 ]; then
    warn "No backups found"
    info "Create a backup with: sudo $0 backup"
    return
  fi
  
  for backup in "${backups[@]}"; do
    local backup_path="${BACKUP_DIR}/${backup}"
    local info_file="${backup_path}/system_info.txt"
    
    printf "\n${GREEN}${backup}${NC}\n"
    
    if [ -f "$info_file" ]; then
      local timestamp=$(grep "timestamp=" "$info_file" | cut -d= -f2)
      local hostname_bak=$(grep "hostname=" "$info_file" | cut -d= -f2)
      local ip_bak=$(grep "ip=" "$info_file" | cut -d= -f2)
      
      # Format timestamp
      local date_formatted=""
      if [ -n "$timestamp" ]; then
        date_formatted=$(date -d "${timestamp:0:8} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2}" "+%d/%m/%Y %H:%M:%S" 2>/dev/null || echo "$timestamp")
      fi
      
      info "  Date: ${date_formatted:-Unknown}"
      info "  Hostname: ${hostname_bak:-Unknown}"
      info "  IP: ${ip_bak:-Unknown}"
    fi
    
    info "  Path: $backup_path"
    
    # Show if it's the latest
    if [ -L "${BACKUP_DIR}/latest" ] && [ "$(readlink "${BACKUP_DIR}/latest")" = "$backup" ]; then
      info "  ${YELLOW}(Latest backup)${NC}"
    fi
  done
  
  printf "\n${YELLOW}Restore commands:${NC}\n"
  echo "  sudo $0 restore                    # Use latest backup"
  echo "  sudo $0 restore backup_YYYYMMDD_HHMMSS  # Use specific backup"
}

# Fix conflicts with MicroK8s/Kubernetes
fix_microk8s_conflict() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Command requires root privileges"
    exit 1
  fi
  
  printf "${BLUE}=== FIX DNS CONFLICT WITH KUBERNETES ===${NC}\n"
  
  # Detect Kubernetes
  detect_kubernetes
  
  # Check if there's actually a conflict
  if [ "$K8S_TYPE" = "none" ]; then
    warn "Kubernetes not detected, no conflict to resolve"
    return
  fi
  
  info "Kubernetes detected ($K8S_TYPE), resolving DNS conflict..."
  
  # 1. Stop dnsmasq temporarily
  info "Temporarily stopping dnsmasq..."
  systemctl stop dnsmasq 2>/dev/null || true
  
  # 2. Restore resolv.conf if pointing to localhost
  if grep -q "^nameserver 127.0.0.1" /etc/resolv.conf; then
    info "Restoring resolv.conf..."
    if ls /etc/resolv.conf.backup.* >/dev/null 2>&1; then
      # Use the most recent backup
      LATEST_BACKUP=$(ls -t /etc/resolv.conf.backup.* 2>/dev/null | head -n1)
      cp "$LATEST_BACKUP" /etc/resolv.conf
      ok "Restored from: $LATEST_BACKUP"
    else
      # Create a minimal resolv.conf
      echo "nameserver 8.8.8.8" > /etc/resolv.conf
      warn "No backup found, using Google DNS"
    fi
  fi
  
  # 3. Reconfigure dnsmasq to not listen on localhost
  if [ -f "$DNSMASQ_CONF" ]; then
    info "Reconfiguring dnsmasq to coexist with CoreDNS..."
    
    # Current backup
    cp "$DNSMASQ_CONF" "${DNSMASQ_CONF}.backup.conflict.$(date +%Y%m%d_%H%M%S)"
    
    # Recreate compatible configuration
    cat > "$DNSMASQ_CONF" << EOF
# DNS Forwarder for ${HOSTNAME} - Kubernetes compatible
# Generated on $(date) - POST CONFLICT FIX

# === BINDING - EXTERNAL IP ONLY ===
bind-interfaces
listen-address=${CURRENT_IP}
# DON'T listen on localhost to avoid conflicts with CoreDNS

# === WILDCARD DNS ===
address=/${HOSTNAME}.local/${CURRENT_IP}
address=/.${HOSTNAME}.local/${CURRENT_IP}

# === UPSTREAM DNS ===
server=${GATEWAY_IP}
server=1.1.1.1
server=8.8.8.8

# === SETTINGS ===
local=/local/
domain-needed
bogus-priv
cache-size=1000
EOF
  fi
  
  # 4. Restart dnsmasq
  info "Restarting dnsmasq..."
  systemctl start dnsmasq
  
  # 5. Restart CoreDNS (using the correct command for each K8s)
  info "Restarting Kubernetes CoreDNS..."
  case "$K8S_TYPE" in
    microk8s)
      if $KUBECTL_CMD delete pod -n kube-system -l k8s-app=kube-dns 2>/dev/null; then
        ok "CoreDNS restarted successfully"
      else
        warn "Unable to restart CoreDNS automatically"
        info "Try manually: microk8s kubectl delete pod -n kube-system -l k8s-app=kube-dns"
      fi
      ;;
    k3s)
      if $KUBECTL_CMD delete pod -n kube-system -l k8s-app=kube-dns 2>/dev/null; then
        ok "CoreDNS restarted successfully"
      else
        warn "Unable to restart CoreDNS automatically"
        info "Try manually: k3s kubectl delete pod -n kube-system -l k8s-app=kube-dns"
      fi
      ;;
    k8s|k8s-detected)
      if $KUBECTL_CMD delete pod -n kube-system -l k8s-app=kube-dns 2>/dev/null; then
        ok "CoreDNS restarted successfully"
      else
        warn "Unable to restart CoreDNS automatically"
        info "Try manually: kubectl delete pod -n kube-system -l k8s-app=kube-dns"
      fi
      ;;
  esac
  
  # 6. Verify
  sleep 3
  printf "\n${YELLOW}=== STATUS VERIFICATION ===${NC}\n"
  
  if systemctl is-active dnsmasq >/dev/null; then
    ok "dnsmasq: ACTIVE on ${CURRENT_IP}:53"
  else
    err "dnsmasq: NOT ACTIVE"
  fi
  
  if ss -tuln | grep -q "${CURRENT_IP}:53"; then
    ok "Port 53: LISTENING on ${CURRENT_IP}"
  else
    err "Port 53: NOT LISTENING on ${CURRENT_IP}"
  fi
  
  printf "\n${GREEN}=== CONFIGURATION COMPLETED ===${NC}\n"
  info "dnsmasq now listens only on ${CURRENT_IP}:53 for LAN devices"
  info "CoreDNS continues to handle 127.0.0.1:53 for the local system"
  echo ""
  printf "${YELLOW}Local DNS test:${NC}\n"
  echo "  $KUBECTL_CMD get pods -n kube-system | grep coredns"
  echo ""
  printf "${YELLOW}For LAN devices:${NC}\n"
  printf "  DNS Server: ${GREEN}${CURRENT_IP}${NC}\n"
  echo "  Will resolve: *.${HOSTNAME}.local → ${CURRENT_IP}"
}

# Clean systemd-resolved delegation
clean_systemd_resolved() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Command requires root privileges"
    exit 1
  fi
  
  printf "${BLUE}=== CLEAN SYSTEMD-RESOLVED DELEGATION ===${NC}\n"
  
  if [ -f /etc/systemd/resolved.conf.d/local-dns.conf ]; then
    info "Removing systemd-resolved .local delegation..."
    rm -f /etc/systemd/resolved.conf.d/local-dns.conf
    
    # Restart systemd-resolved if active
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
      systemctl restart systemd-resolved >/dev/null 2>&1
      ok "systemd-resolved delegation removed and service restarted"
    else
      ok "systemd-resolved delegation file removed"
    fi
    
    warn "Wildcard DNS *.${HOSTNAME}.local will no longer work from local system"
    info "Other LAN devices can still use dnsmasq directly: ${CURRENT_IP}:53"
  else
    info "No systemd-resolved delegation found - nothing to clean"
  fi
}

# Interactive wizard
interactive_wizard() {
  # Check root privileges
  if [ "$(id -u)" -ne 0 ]; then
    err "This wizard must be run as root"
    echo ""
    printf "${YELLOW}Please run: ${GREEN}sudo $0${NC}\n"
    exit 1
  fi
  
  check_os_compatibility
  
  printf "${BLUE}=== INTERACTIVE DNS SETUP WIZARD ===${NC}\n"
  echo ""
  printf "${GREEN}Welcome to the DNS Configuration Wizard!${NC}\n"
  echo ""
  printf "This wizard will guide you through setting up wildcard DNS resolution\n"
  printf "for your ${GREEN}${HOSTNAME}${NC} machine on the local network.\n"
  echo ""
  printf "${YELLOW}🎯 What this does:${NC}\n"
  printf "  • Makes ${GREEN}*.${HOSTNAME}.local${NC} point to ${GREEN}$CURRENT_IP${NC}\n"
  printf "  • Examples: ${CYAN}n8n.${HOSTNAME}.local${NC}, ${CYAN}grafana.${HOSTNAME}.local${NC}\n"
  printf "  • Allows other devices to use this machine as DNS server\n"
  echo ""
  printf "${YELLOW}📋 The process has 4 simple steps:${NC}\n"
  printf "  ${BLUE}1.${NC} Test current DNS (should show: NOT WORKING)\n"
  printf "  ${BLUE}2.${NC} Install DNS server\n"
  printf "  ${BLUE}3.${NC} Test again (should show: WORKING)\n"
  printf "  ${BLUE}4.${NC} Enable network access for other devices\n"
  echo ""
  
  read -p "$(printf "${YELLOW}Do you want to proceed? [Y/n]: ${NC}")" -r
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    printf "${YELLOW}Setup cancelled.${NC}\n"
    exit 0
  fi
  
  echo ""
  printf "${BLUE}=== STEP 1: CHECKING CURRENT DNS STATUS ===${NC}\n"
  read -p "$(printf "${YELLOW}Press Enter to test current DNS status...${NC}")" -r
  test_dns
  
  echo ""
  printf "${BLUE}=== STEP 2: INSTALLING DNS SERVER ===${NC}\n"
  read -p "$(printf "${YELLOW}Ready to install DNS? Press Enter to continue...${NC}")" -r
  install_dns
  
  echo ""
  printf "${BLUE}=== STEP 3: VERIFYING DNS INSTALLATION ===${NC}\n"
  read -p "$(printf "${YELLOW}Press Enter to test DNS after installation...${NC}")" -r
  test_dns
  
  echo ""
  printf "${BLUE}=== STEP 4: ENABLE NETWORK ACCESS ===${NC}\n"
  printf "${YELLOW}Do you want to allow other devices on your LAN to use this DNS?${NC}\n"
  printf "This will make wildcard DNS available to:\n"
  printf "  • Other computers\n"
  printf "  • Tablets and phones\n"
  printf "  • Any device on your local network\n"
  echo ""
  read -p "$(printf "${YELLOW}Enable network DNS access? [Y/n]: ${NC}")" -r
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    enable_network
  else
    printf "${YELLOW}Network access not enabled. DNS works only on this machine.${NC}\n"
    printf "${CYAN}You can enable it later with: sudo $0 enable-network${NC}\n"
  fi
  
  echo ""
  printf "${GREEN}=== SETUP COMPLETED! ===${NC}\n"
  printf "${YELLOW}Your DNS system is now configured.${NC}\n"
  echo ""
  printf "${CYAN}Quick verification:${NC}\n"
  printf "  • Local test: ${GREEN}ping ${HOSTNAME}.local${NC}\n"
  printf "  • Wildcard test: ${GREEN}ping test.${HOSTNAME}.local${NC}\n"
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    printf "  • From other devices: Set DNS to ${GREEN}$CURRENT_IP${NC}\n"
  fi
  echo ""
  printf "${YELLOW}Need help? Run: sudo $0 help${NC}\n"
}

# Main - Command handling
case "${1:-wizard}" in
  wizard|"")
    interactive_wizard
    ;;
    
  help|--help|-h)
    show_help
    ;;
    
  test)
    test_dns
    ;;
    
  install)
    install_dns
    ;;
    
  status)
    show_status
    ;;
    
  enable-network)
    enable_network
    ;;
    
  disable-network)
    disable_network
    ;;
    
  fix-microk8s|fix-k8s|fix)
    fix_microk8s_conflict
    ;;
    
  clean-systemd-resolved)
    clean_systemd_resolved
    ;;
    
  protect-dns)
    if [ "$(id -u)" -ne 0 ]; then
      err "Command requires root privileges"
      exit 1
    fi
    info "Protecting DNS configuration..."
    if [ -f /etc/resolv.conf ]; then
      chattr +i /etc/resolv.conf 2>/dev/null || true
      ok "/etc/resolv.conf protected from changes"
      info "File cannot be modified until: sudo $0 unprotect-dns"
    else
      err "/etc/resolv.conf not found"
    fi
    ;;
    
  unprotect-dns)
    if [ "$(id -u)" -ne 0 ]; then
      err "Command requires root privileges"
      exit 1
    fi
    info "Removing DNS protection..."
    if [ -f /etc/resolv.conf ]; then
      chattr -i /etc/resolv.conf 2>/dev/null || true
      ok "/etc/resolv.conf now modifiable"
      warn "File might be overwritten on next reboot!"
    fi
    ;;
    
  repair)
    if [ "$(id -u)" -ne 0 ]; then
      err "Command requires root privileges"
      exit 1
    fi
    info "Repairing DNS configuration after system changes..."
    
    # Wait for network to be ready
    info "Waiting for network to be available..."
    for i in {1..30}; do
      if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
    
    # Update current IP (might have changed after reboot)
    # Read OLD_IP from current dnsmasq configuration
    OLD_IP=""
    if [ -f "$DNSMASQ_CONF" ]; then
      OLD_IP=$(grep "^listen-address=" "$DNSMASQ_CONF" | cut -d= -f2 | head -n1)
    fi
    
    # Get current system IP
    CURRENT_IP=$(get_local_ip)
    GATEWAY_IP=$(get_gateway_ip)
    
    if [ -n "$OLD_IP" ] && [ "$OLD_IP" != "$CURRENT_IP" ]; then
      warn "IP address changed from $OLD_IP to $CURRENT_IP - updating configuration"
      
      # Update dnsmasq configuration with new IP
      if [ -f "$DNSMASQ_CONF" ]; then
        sed -i "s/listen-address=${OLD_IP}/listen-address=${CURRENT_IP}/g" "$DNSMASQ_CONF" 2>/dev/null || true
        sed -i "s/address=\/${HOSTNAME}\.local\/${OLD_IP}/address=\/${HOSTNAME}\.local\/${CURRENT_IP}/g" "$DNSMASQ_CONF" 2>/dev/null || true
        sed -i "s/address=\/\.${HOSTNAME}\.local\/${OLD_IP}/address=\/\.${HOSTNAME}\.local\/${CURRENT_IP}/g" "$DNSMASQ_CONF" 2>/dev/null || true
        info "Updated dnsmasq configuration with new IP: $CURRENT_IP"
        
        # Restart dnsmasq to apply new configuration
        systemctl restart dnsmasq >/dev/null 2>&1 || true
        sleep 2
        ok "dnsmasq restarted with new IP configuration"
      fi
      
      # Update systemd-resolved delegation if it exists
      if [ -f /etc/systemd/resolved.conf.d/local-dns.conf ]; then
        sed -i "s/DNS=${OLD_IP}#53/DNS=${CURRENT_IP}#53/g" /etc/systemd/resolved.conf.d/local-dns.conf 2>/dev/null || true
        info "Updated systemd-resolved delegation with new IP"
      fi
    else
      if [ -n "$OLD_IP" ] && [ "$OLD_IP" = "$CURRENT_IP" ]; then
        info "IP address unchanged ($CURRENT_IP) - no configuration update needed"
      elif [ -z "$OLD_IP" ]; then
        warn "Could not detect previous IP from dnsmasq configuration"
      fi
    fi
    
    # Detect Kubernetes
    detect_kubernetes
    
    # Restart services if not active
    for service in dnsmasq avahi-daemon; do
      if ! systemctl is-active "$service" >/dev/null 2>&1; then
        warn "$service not active - restarting..."
        systemctl start "$service" >/dev/null 2>&1 || true
        sleep 2
        
        # Check again and try restart if still not active
        if ! systemctl is-active "$service" >/dev/null 2>&1; then
          warn "Retrying $service startup..."
          systemctl restart "$service" >/dev/null 2>&1 || true
          sleep 3
        fi
      fi
    done
    
    # Verify and fix resolv.conf if necessary (only for non-Kubernetes systems)
    if [ "$K8S_TYPE" = "none" ] && ! grep -q "nameserver 127.0.0.1" /etc/resolv.conf 2>/dev/null; then
      warn "resolv.conf not pointing to local DNS - restoring..."
      chattr -i /etc/resolv.conf 2>/dev/null || true
      echo "# DNS for ${HOSTNAME} - Enterprise system (restored after reboot)" > /etc/resolv.conf
      echo "nameserver 127.0.0.1     # Local DNS (this machine)" >> /etc/resolv.conf
      echo "nameserver ${GATEWAY_IP:-8.8.8.8} # Upstream DNS" >> /etc/resolv.conf
      echo "search local" >> /etc/resolv.conf
      chattr +i /etc/resolv.conf 2>/dev/null || true
      ok "resolv.conf restored"
    fi
    
    # Restart systemd-resolved if needed for delegation to take effect
    if [ "$K8S_TYPE" != "none" ] && systemctl is-active systemd-resolved >/dev/null 2>&1; then
      if [ -f /etc/systemd/resolved.conf.d/local-dns.conf ]; then
        systemctl restart systemd-resolved >/dev/null 2>&1 || true
        info "Restarted systemd-resolved for .local delegation"
      fi
    fi
    
    # Final verification
    sleep 3
    ok "Repair completed"
    info "Verifying DNS functionality..."
    
    # Quick test
    if ping -c 1 -W 3 "${HOSTNAME}.local" >/dev/null 2>&1; then
      ok "DNS repair successful - ${HOSTNAME}.local is reachable"
    else
      warn "DNS may need additional time to propagate"
      info "Try: sudo $0 test (after 30 seconds)"
    fi
    ;;
    
  restart)
    if [ "$(id -u)" -ne 0 ]; then
      err "Command requires root privileges"
      exit 1
    fi
    info "Restarting DNS services..."
    systemctl restart dnsmasq avahi-daemon
    ok "Services restarted"
    ;;
    
  logs)
    printf "${BLUE}=== DNS LOGS (last 20 lines) ===${NC}\n"
    journalctl -u dnsmasq -n 20 --no-pager
    ;;
    
  backup)
    create_backup
    ;;
    
  restore)
    restore_backup "$2"
    ;;
    
  list-backups)
    list_backups
    ;;
    
  *)
    err "Unrecognized command: $1"
    echo ""
    printf "${CYAN}Available options:${NC}\n"
    printf "  ${GREEN}sudo $0${NC}              → Interactive wizard (recommended)\n"
    printf "  ${GREEN}sudo $0 help${NC}         → Show all commands\n"
    printf "  ${GREEN}sudo $0 test${NC}         → Quick DNS test\n"
    printf "  ${GREEN}sudo $0 install${NC}      → Install DNS server\n"
    echo ""
    exit 1
    ;;
esac