#!/usr/bin/env bash

# region 0) Pre-flight checks
# ANSI colors for early output (before complete logger)
PRE_BLUE="\e[94m"; PRE_GREEN="\e[32m"; PRE_YELLOW="\e[33m"; PRE_RED="\e[31m"; PRE_NC="\e[0m"
echo -e "${PRE_BLUE}[INFO]${PRE_NC} Running pre-startup checks..."

# Check operating system compatibility
if [[ "$(uname -s)" != "Linux" ]]; then
  echo -e "${PRE_RED}[ERROR]${PRE_NC} MicroK8s setup is only supported on Linux (Ubuntu 24.04 recommended)."
  echo -e "${PRE_YELLOW}[INFO]${PRE_NC}  Current OS: $(uname -s)"
  echo -e "${PRE_YELLOW}[INFO]${PRE_NC}  Please run this script on Ubuntu 24.04 or another supported Linux distribution."
  echo ""
  echo -e "${PRE_BLUE}[HINT]${PRE_NC}  If you're on macOS/Windows:"
  echo -e "${PRE_BLUE}[HINT]${PRE_NC}  • Use a Ubuntu 24.04 VM (VirtualBox, VMware, Parallels)"
  echo -e "${PRE_BLUE}[HINT]${PRE_NC}  • Use a cloud instance (AWS EC2, GCP, Azure, DigitalOcean)"
  echo -e "${PRE_BLUE}[HINT]${PRE_NC}  • For managed Kubernetes, use: ./k8s-managed/setup.sh"
  exit 1
fi

# Check if running on Ubuntu (recommended)
if [[ -f /etc/os-release ]]; then
  source /etc/os-release
  if [[ "$ID" != "ubuntu" ]]; then
    echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} Not running on Ubuntu. This script is tested on Ubuntu 24.04."
    echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} Current distribution: $PRETTY_NAME"
    echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} Continuing anyway, but some features may not work correctly."
  elif [[ "$VERSION_ID" != "24.04" ]]; then
    echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} Not running on Ubuntu 24.04. This script is optimized for Ubuntu 24.04."
    echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} Current version: $PRETTY_NAME"
    echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} Continuing anyway, but some features may not work correctly."
  else
    echo -e "${PRE_GREEN}[OK]${PRE_NC} Running on Ubuntu 24.04 (recommended)."
  fi
fi

# endregion 0) Pre-flight checks

# region 1) Basic internet connectivity check
# Basic internet connectivity check
if ! ping -c 1 -W 3 google.com &>/dev/null && ! ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
  echo -e "${PRE_RED}[ERROR]${PRE_NC} No internet connection detected. Check your network and DNS." 
  echo -e "${PRE_YELLOW}[HINT]${PRE_NC}  Try: ping 8.8.8.8"
echo -e "${PRE_YELLOW}[HINT]${PRE_NC}  If ping to 8.8.8.8 works, it might be a DNS problem. Check /etc/resolv.conf." 
  exit 1
else
  echo -e "${PRE_GREEN}[OK]${PRE_NC} Basic internet connection verified."
fi
# endregion 1) Basic internet connectivity check

# region 1.5) Safe system DNS configuration with systemd-resolved
# SAFE DNS STRATEGY: 
# 1. Check if systemd-resolved is available and working
# 2. If yes: configure the correct symbolic link to /run/systemd/resolve/resolv.conf
# 3. If no: fallback to static file with delimited section for safe cleanup
# 4. teardown_microk8s.sh will restore the original configuration
#
# Note: For secondary nodes, DNS configuration is less critical as they join existing cluster
#
# Save the original DNS configuration for teardown
DNS_BACKUP_DIR="/tmp/lair-dns-backup"
mkdir -p "$DNS_BACKUP_DIR"

# Backup of original DNS configuration
if [ -L /etc/resolv.conf ]; then
  # It's a symbolic link - save the target
  readlink /etc/resolv.conf > "$DNS_BACKUP_DIR/resolv.conf.link"
  echo "SYMLINK" > "$DNS_BACKUP_DIR/resolv.conf.type"
elif [ -f /etc/resolv.conf ]; then
  # It's a normal file - save the content
  cp /etc/resolv.conf "$DNS_BACKUP_DIR/resolv.conf.backup" 2>/dev/null || true
  echo "FILE" > "$DNS_BACKUP_DIR/resolv.conf.type"
else
  # Doesn't exist
  echo "MISSING" > "$DNS_BACKUP_DIR/resolv.conf.type"
fi

# Check if systemd-resolved is available and can be used
SYSTEMD_RESOLVED_AVAILABLE=false
if command -v systemctl &>/dev/null; then
  if systemctl is-available systemd-resolved >/dev/null 2>&1; then
    # Enable and start systemd-resolved if not active
    if ! systemctl is-active systemd-resolved >/dev/null 2>&1; then
      echo -e "${PRE_BLUE}[INFO]${PRE_NC} Enabling systemd-resolved for modern DNS..."
      systemctl enable systemd-resolved >/dev/null 2>&1 || true
      systemctl start systemd-resolved >/dev/null 2>&1 || true
      sleep 2
    fi
    
    # Verify that systemd-resolved is operational
    if systemctl is-active systemd-resolved >/dev/null 2>&1; then
      SYSTEMD_RESOLVED_AVAILABLE=true
    fi
  fi
fi

# Check working DNS
dns_working() {
  nslookup google.com >/dev/null 2>&1 || dig google.com +short >/dev/null 2>&1
}

# If DNS already works, don't modify anything
if dns_working; then
  echo -e "${PRE_GREEN}[OK]${PRE_NC} DNS already working, no modification needed"
else
  echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} DNS not working - configuration needed for ImagePullBackOff"
  
  if $SYSTEMD_RESOLVED_AVAILABLE; then
    echo -e "${PRE_BLUE}[INFO]${PRE_NC} DNS configuration via systemd-resolved (modern method)..."
    
    # Remove immutable attribute if present
    chattr -i /etc/resolv.conf 2>/dev/null || true
    
    # Configure the correct symbolic link for systemd-resolved
    rm -f /etc/resolv.conf
    ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    
    # Wait for systemd-resolved to stabilize the configuration
    sleep 3
    
    # Verify that DNS works now
    if dns_working; then
      echo -e "${PRE_GREEN}[OK]${PRE_NC} DNS configured via systemd-resolved and working"
    else
      echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} systemd-resolved configured but DNS still not working"
      # Fallback to static file
      echo -e "${PRE_BLUE}[INFO]${PRE_NC} Fallback to static DNS configuration..."
      
      # Remove the symbolic link
      rm -f /etc/resolv.conf
      
      # Create static DNS configuration with delimited section
      cat > /etc/resolv.conf << 'EOF'
# BEGIN MICROK8S DNS CONFIG - Configuration added by setup_microk8s.sh
# Automatic DNS configuration for MicroK8s
# Generated by setup_microk8s.sh to resolve ImagePullBackOff
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options timeout:1 attempts:3
# END MICROK8S DNS CONFIG
EOF
      echo "STATIC_FALLBACK" > "$DNS_BACKUP_DIR/resolv.conf.applied"
      
      # Final test
      if dns_working; then
        echo -e "${PRE_GREEN}[OK]${PRE_NC} DNS configured with static file and working"
      else
        echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} DNS configured but resolution test still failed"
      fi
    fi
    
    echo "SYSTEMD_RESOLVED" > "$DNS_BACKUP_DIR/resolv.conf.applied"
    
  else
    echo -e "${PRE_BLUE}[INFO]${PRE_NC} systemd-resolved not available - static DNS configuration..."
    
    # Check if /etc/resolv.conf exists and is empty or has only comments
    if [ ! -s /etc/resolv.conf ] || [ "$(grep -v '^#' /etc/resolv.conf | grep -v '^$' | wc -l)" -eq 0 ]; then
      # Empty or missing file - create complete file
      echo -e "${PRE_BLUE}[INFO]${PRE_NC} Creating complete DNS configuration..."
      
      # Remove immutable attribute if present
       chattr -i /etc/resolv.conf 2>/dev/null || true
       
       # Create basic DNS configuration with delimited section
       cat > /etc/resolv.conf << 'EOF'
# BEGIN MICROK8S DNS CONFIG - Configuration added by setup_microk8s.sh
# Automatic DNS configuration for MicroK8s
# Generated by setup_microk8s.sh to resolve ImagePullBackOff
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
options timeout:1 attempts:3
# END MICROK8S DNS CONFIG
EOF
      
    else
       # File exists and is not empty - add only our section if not already present
       if grep -q "# BEGIN MICROK8S DNS CONFIG" /etc/resolv.conf; then
         echo -e "${PRE_GREEN}[OK]${PRE_NC} MicroK8s DNS section already present"
       else
         echo -e "${PRE_BLUE}[INFO]${PRE_NC} Adding MicroK8s DNS section to existing file..."
         
         # Remove immutable attribute if present
         chattr -i /etc/resolv.conf 2>/dev/null || true
         
         # Add our section to the end of the existing file
         cat >> /etc/resolv.conf << 'EOF'
# BEGIN MICROK8S DNS CONFIG - Configuration added by setup_microk8s.sh
# DNS section for MicroK8s - resolve ImagePullBackOff issues
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
# END MICROK8S DNS CONFIG
EOF
      fi
    fi
    
    echo "STATIC_CONFIG" > "$DNS_BACKUP_DIR/resolv.conf.applied"
    
    # Test that DNS resolution works now
     if dns_working; then
       echo -e "${PRE_GREEN}[OK]${PRE_NC} Static DNS configured and working"
     else
       echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} DNS configured but resolution test still failed"
     fi
   fi
fi
# endregion 1.5) Safe system DNS configuration with systemd-resolved

# region 1.7) Secondary node specific checks
# Additional checks for secondary nodes joining existing cluster
if [[ "${IS_SECONDARY_NODE:-false}" == "true" ]]; then
    echo -e "${PRE_BLUE}[INFO]${PRE_NC} Performing secondary node specific checks..."
    
    # Check if PRIMARY_NODE_IP is accessible
    if [[ -n "${PRIMARY_NODE_IP:-}" ]]; then
        echo -e "${PRE_BLUE}[INFO]${PRE_NC} Testing connectivity to primary node at $PRIMARY_NODE_IP..."
        
        # Test basic connectivity
        if ping -c 3 -W 5 "$PRIMARY_NODE_IP" >/dev/null 2>&1; then
            echo -e "${PRE_GREEN}[OK]${PRE_NC} Primary node is reachable"
        else
            echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} Cannot reach primary node at $PRIMARY_NODE_IP"
            echo -e "${PRE_YELLOW}[HINT]${PRE_NC} Ensure the primary node is running and accessible"
        fi
        
        # Test if MicroK8s API port is accessible
        if command -v nc >/dev/null 2>&1; then
            if timeout 5 nc -z "$PRIMARY_NODE_IP" 16443 2>/dev/null; then
                echo -e "${PRE_GREEN}[OK]${PRE_NC} MicroK8s API port (16443) is accessible"
            else
                echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} MicroK8s API port (16443) not accessible"
                echo -e "${PRE_YELLOW}[HINT]${PRE_NC} Ensure the primary node has MicroK8s running and configured for remote access"
            fi
        fi
        
        # Test if join token format is valid
        if [[ -n "${JOIN_TOKEN:-}" ]]; then
            if [[ "$JOIN_TOKEN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/[a-zA-Z0-9]+$ ]]; then
                echo -e "${PRE_GREEN}[OK]${PRE_NC} Join token format is valid"
            else
                echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} Join token format may be invalid"
                echo -e "${PRE_YELLOW}[HINT]${PRE_NC} Expected format: IP:PORT/TOKEN"
            fi
        else
            echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} No join token provided"
        fi
    else
        echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} No primary node IP specified"
    fi
    
    echo -e "${PRE_BLUE}[INFO]${PRE_NC} Secondary node checks completed"
fi
# endregion 1.7) Secondary node specific checks

# region 2) Time synchronization check (NTP)
# Time synchronization check (NTP)
# Check if timedatectl is available and if NTP is active and synchronized
if command -v timedatectl &>/dev/null; then
  NTP_STATUS=$(timedatectl status 2>/dev/null)
  if echo "$NTP_STATUS" | grep -q "NTP service: active"; then
    if echo "$NTP_STATUS" | grep -q "System clock synchronized: yes"; then
      echo -e "${PRE_GREEN}[OK]${PRE_NC} System clock is synchronized via NTP."
    else
      echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} NTP is active but system clock is NOT synchronized. This could cause problems with apt repositories."
      echo -e "${PRE_YELLOW}[HINT]${PRE_NC}      Try to force resynchronization: sudo timedatectl set-ntp false && sudo timedatectl set-ntp true"
      echo -e "${PRE_YELLOW}[HINT]${PRE_NC}      Wait a few minutes and check with: timedatectl status"
      # We don't exit for this warning, but it's important
    fi
  else
    echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} NTP service is not active. System clock might not be accurate."
    echo -e "${PRE_YELLOW}[HINT]${PRE_NC}      To enable NTP: sudo timedatectl set-ntp true"
  fi
else
  echo -e "${PRE_YELLOW}[WARNING]${PRE_NC} timedatectl not found. Cannot verify NTP status."
fi
# endregion 2) Time synchronization check (NTP)
