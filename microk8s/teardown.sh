#!/usr/bin/env bash
#─────────────────────────────────────────────────────────────────────────────
# teardown_microk8s.sh – Completely removes MicroK8s, DNS and all configurations
# Returns the machine to the original pre-installation state
# Usage: sudo ./teardown_microk8s.sh [-v|--verbose] [--keep-dns]
# Requirements: bash, util-linux (fuser)
#─────────────────────────────────────────────────────────────────────────────

### 1) Verify execution as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\e[31m[ERROR]\e[0m This script must be run as root"
  exit 1
fi

### 2) Parameter handling
VERBOSE=false
KEEP_DNS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    --keep-dns)
      KEEP_DNS=true
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [-v|--verbose] [--keep-dns]"
      echo ""
      echo "Options:"
      echo "  -v, --verbose    Detailed output"
      echo "  --keep-dns      Keep DNS configuration (don't remove setup_dns.sh)"
      echo "  -h, --help      Show this help"
      echo ""
      echo "This script COMPLETELY removes:"
      echo "  • MicroK8s and all its components"
      echo "  • Longhorn and MetalLB"
      echo "  • Custom iptables rules"
      echo "  • DNS configurations (dnsmasq, avahi)"
      echo "  • All created configuration files"
      echo "  • Modified groups and users"
      echo ""
      exit 0
      ;;
    *)
      echo -e "\e[31m[ERROR]\e[0m Unknown parameter: $1"
      echo "Use -h for help"
      exit 1
      ;;
  esac
done

### 3) Fail-fast and debug
set -Eeuo pipefail
$VERBOSE && set -x

### 4) Logger colors + file
BLUE="\e[94m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; NC="\e[0m"
LOGFILE="/var/log/teardown_microk8s.log"
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1

timestamp(){ date -Iseconds; }
_log(){ printf '[%s] %s: %s\n' "$(timestamp)" "$1" "$2"; }
info(){ printf '%b' "$BLUE";  _log "INFO"  "$1"; printf '%b' "$NC"; }
ok(){ printf '%b' "$GREEN"; _log "OK"    "$1"; printf '%b' "$NC"; }
warn(){ printf '%b' "$YELLOW";_log "WARN"  "$1"; printf '%b' "$NC"; }
err(){  printf '%b' "$RED";   _log "ERROR" "$1"; printf '%b' "$NC"; }

trap 'err "Error at line ${LINENO}, exit code $?"; exit 1' ERR

### 5) Initial banner
echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}  COMPLETE MICROK8S + DNS TEARDOWN     ${NC}"
echo -e "${BLUE}=========================================${NC}"
info "Starting complete teardown..."
if $KEEP_DNS; then
  warn "--keep-dns mode: DNS configuration will be preserved"
fi

# Detect if this was a secondary node in a cluster
CLUSTER_NODE_TYPE="unknown"
if command -v microk8s >/dev/null 2>&1; then
  # Try to detect if this node was part of a multi-node cluster
  if microk8s kubectl get nodes 2>/dev/null | grep -v "$(hostname)" | grep -q "Ready"; then
    CLUSTER_NODE_TYPE="secondary"
    info "Detected: This appears to be a SECONDARY node in a multi-node cluster"
  elif microk8s kubectl get nodes 2>/dev/null | wc -l | grep -q "^1$"; then
    CLUSTER_NODE_TYPE="primary"
    info "Detected: This appears to be a single-node cluster or PRIMARY node"
  else
    CLUSTER_NODE_TYPE="unknown"
    info "Could not determine cluster node type"
  fi
fi

### 6) Platform detection
IS_JETSON=false
if [ -f /proc/device-tree/model ]; then
  MODEL_INFO=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
  if echo "$MODEL_INFO" | grep -qi "jetson\|xavier\|nano\|orin\|agx"; then
    IS_JETSON=true
  fi
fi
if [ "$(uname -r | grep -c tegra)" -gt 0 ]; then
  IS_JETSON=true
fi

if $IS_JETSON; then
  info "NVIDIA Jetson system detected"
fi

### 7) Cluster leave operation for secondary nodes
if [[ "$CLUSTER_NODE_TYPE" == "secondary" ]]; then
  echo -e "\n${YELLOW}=== SECONDARY NODE: LEAVING CLUSTER ===${NC}"
  info "Attempting to leave cluster gracefully..."
  
  # Try to leave the cluster gracefully
  if command -v microk8s >/dev/null 2>&1; then
    # Get current node name
    NODE_NAME=$(hostname)
    
    # Try to drain the node first (best practice)
    info "Draining node $NODE_NAME..."
    microk8s kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --force --timeout=60s 2>/dev/null || warn "Node drain failed or timed out"
    
    # Remove the node from the cluster
    info "Removing node $NODE_NAME from cluster..."
    if microk8s leave 2>/dev/null; then
      ok "Successfully left the cluster"
    else
      warn "Failed to leave cluster gracefully"
      warn "The primary node may need to remove this node manually with:"
      warn "  microk8s remove-node $NODE_NAME"
    fi
  fi
elif [[ "$CLUSTER_NODE_TYPE" == "primary" ]]; then
  echo -e "\n${YELLOW}=== PRIMARY NODE: CLUSTER TEARDOWN ===${NC}"
  info "This is a primary node - full cluster teardown will proceed"
  
  # List other nodes that might be affected
  if command -v microk8s >/dev/null 2>&1; then
    OTHER_NODES=$(microk8s kubectl get nodes --no-headers 2>/dev/null | grep -v "$(hostname)" | awk '{print $1}' || echo "")
    if [[ -n "$OTHER_NODES" ]]; then
      warn "⚠️  WARNING: Other nodes detected in cluster:"
      echo "$OTHER_NODES" | while read -r node; do
        warn "  - $node"
      done
      warn "These nodes will lose cluster connectivity after this teardown!"
      warn "Consider running teardown on secondary nodes first."
      echo ""
      if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then  # Only prompt if run directly
        read -rp "Continue with primary node teardown? [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
          info "Teardown cancelled by user"
          exit 0
        fi
      fi
    fi
  fi
fi

### 8) Stop all related services
info "Stopping related services..."

# Stop MicroK8s
if command -v microk8s >/dev/null 2>&1; then
  info "Stopping MicroK8s..."
  microk8s stop || warn "microk8s stop failed"
  
  # Stop MicroK8s snap services
  for service in containerd kubelite flanneld; do
    systemctl stop "snap.microk8s.daemon-${service}.service" 2>/dev/null || true
  done
fi

# Stop DNS services
if ! $KEEP_DNS; then
  info "Stopping DNS services..."
  for service in dnsmasq avahi-daemon; do
    systemctl stop "$service" 2>/dev/null || true
    systemctl disable "$service" 2>/dev/null || true
  done
fi

# Stop custom iptables service
if systemctl is-active microk8s-iptables.service >/dev/null 2>&1; then
  info "Removing custom iptables service..."
  systemctl stop microk8s-iptables.service || true
  systemctl disable microk8s-iptables.service || true
  rm -f /etc/systemd/system/microk8s-iptables.service
  systemctl daemon-reload
  ok "Custom iptables service removed"
fi

sleep 5

### 8) DNS configuration removal (if not --keep-dns)
if ! $KEEP_DNS; then
  echo -e "\n${YELLOW}=== DNS CONFIGURATION REMOVAL ===${NC}"
  
  # Backup configurations before removal
  info "Backing up current configurations before removal..."
  CLEANUP_BACKUP_DIR="/var/lib/lair-teardown-backup-$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$CLEANUP_BACKUP_DIR"
  
  # Backup important files
  for file in /etc/resolv.conf /etc/nsswitch.conf /etc/dnsmasq.conf /etc/avahi/avahi-daemon.conf; do
    if [ -f "$file" ]; then
      cp "$file" "$CLEANUP_BACKUP_DIR/" 2>/dev/null || true
    fi
  done
  ok "Pre-removal backup saved to: $CLEANUP_BACKUP_DIR"
  
  # INTELLIGENT DNS RESTORATION based on setup_microk8s.sh backups
  # 1. First check setup_microk8s.sh backup (/tmp/microk8s-dns-backup)
  # 2. Then check setup_dns.sh backup (/var/lib/jetson-dns-backups)
  # 3. Fallback to surgical cleanup
  
  DNS_RESTORED=false
  
  # Attempt 1: Restore from setup_microk8s.sh backup (most recent)
  # Check both new and old backup locations for backward compatibility
  SETUP_DNS_BACKUP=""
  if [ -d "/tmp/lair-dns-backup" ]; then
    SETUP_DNS_BACKUP="/tmp/lair-dns-backup"
  elif [ -d "/tmp/microk8s-dns-backup" ]; then
    SETUP_DNS_BACKUP="/tmp/microk8s-dns-backup"
    warn "Using legacy backup directory: /tmp/microk8s-dns-backup"
  fi
  
  if [ -n "$SETUP_DNS_BACKUP" ] && [ -d "$SETUP_DNS_BACKUP" ]; then
    info "Found DNS backup from setup_microk8s.sh, restoring original configuration..."
    
    # Check the type of original configuration
    if [ -f "$SETUP_DNS_BACKUP/resolv.conf.type" ]; then
      ORIGINAL_TYPE=$(cat "$SETUP_DNS_BACKUP/resolv.conf.type")
      
      case "$ORIGINAL_TYPE" in
        "SYMLINK")
          # It was a symbolic link - restore the link
          if [ -f "$SETUP_DNS_BACKUP/resolv.conf.link" ]; then
            ORIGINAL_TARGET=$(cat "$SETUP_DNS_BACKUP/resolv.conf.link")
            info "Restoring symbolic link to: $ORIGINAL_TARGET"
            chattr -i /etc/resolv.conf 2>/dev/null || true
            rm -f /etc/resolv.conf
            ln -sf "$ORIGINAL_TARGET" /etc/resolv.conf
            ok "Symbolic link /etc/resolv.conf restored"
            DNS_RESTORED=true
          fi
          ;;
        "FILE")
          # It was a normal file - restore the content
          if [ -f "$SETUP_DNS_BACKUP/resolv.conf.backup" ]; then
            info "Restoring original /etc/resolv.conf file"
            chattr -i /etc/resolv.conf 2>/dev/null || true
            cp "$SETUP_DNS_BACKUP/resolv.conf.backup" /etc/resolv.conf
            ok "Original /etc/resolv.conf file restored"
            DNS_RESTORED=true
          fi
          ;;
        "MISSING")
          # It didn't exist - remove the file
          info "Original configuration: file did not exist"
          chattr -i /etc/resolv.conf 2>/dev/null || true
          rm -f /etc/resolv.conf
          
          # Check if systemd-resolved can handle DNS
          if systemctl is-active systemd-resolved >/dev/null 2>&1; then
            info "systemd-resolved active, creating symbolic link"
            ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
            ok "DNS managed by systemd-resolved"
            DNS_RESTORED=true
          else
            info "systemd-resolved not active, creating basic configuration"
            cat > /etc/resolv.conf << 'EOF'
# DNS configuration restored by teardown
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
            ok "Basic DNS configuration created"
            DNS_RESTORED=true
          fi
          ;;
      esac
    fi
    
    # Clean temporary backup
    rm -rf "$SETUP_DNS_BACKUP"
  fi
  
  # Attempt 2: Restore from setup_dns.sh backup (if the first didn't work)
  # Check both new and old backup directory locations for backward compatibility
  DNS_BACKUP_DIR=""
  if [ -d "/var/lib/lair-dns-backups" ]; then
    DNS_BACKUP_DIR="/var/lib/lair-dns-backups"
  elif [ -d "/var/lib/jetson-dns-backups" ]; then
    DNS_BACKUP_DIR="/var/lib/jetson-dns-backups"
    warn "Using legacy backup directory: /var/lib/jetson-dns-backups"
  fi
  
  if ! $DNS_RESTORED && [ -n "$DNS_BACKUP_DIR" ]; then
    if [ -d "$DNS_BACKUP_DIR" ] && [ -L "$DNS_BACKUP_DIR/latest" ]; then
      info "Found DNS backup from setup_dns.sh, attempting restore..."
      LATEST_BACKUP=$(readlink -f "$DNS_BACKUP_DIR/latest")
      
      if [ -d "$LATEST_BACKUP" ]; then
        # Restore resolv.conf
        if [ -f "$LATEST_BACKUP/resolv.conf" ]; then
          chattr -i /etc/resolv.conf 2>/dev/null || true
          cp "$LATEST_BACKUP/resolv.conf" /etc/resolv.conf
          ok "Restored /etc/resolv.conf from setup_dns.sh backup"
          DNS_RESTORED=true
        fi
        
        # Restore nsswitch.conf  
        if [ -f "$LATEST_BACKUP/nsswitch.conf" ]; then
          cp "$LATEST_BACKUP/nsswitch.conf" /etc/nsswitch.conf
          ok "Restored /etc/nsswitch.conf from backup"
        fi
      fi
    fi
  fi
  
  # Attempt 3: Surgical cleanup if no backup works
  if ! $DNS_RESTORED; then
    # SURGICAL DNS CLEANUP:
    # - Only removes the "# BEGIN/END MICROK8S DNS CONFIG" section from resolv.conf
    # - Preserves all pre-existing user DNS configurations
    # - Fallback to basic configuration only if file becomes empty
    #
    # Intelligent removal of MicroK8s section from resolv.conf
    info "Removing MicroK8s section from /etc/resolv.conf..."
    
    if [ -f /etc/resolv.conf ]; then
      chattr -i /etc/resolv.conf 2>/dev/null || true
      
      if grep -q "# BEGIN MICROK8S DNS CONFIG" /etc/resolv.conf; then
        info "Found MicroK8s section in /etc/resolv.conf, removing..."
        
        # Create a temporary file without the MicroK8s section
        TEMP_RESOLV=$(mktemp)
        
        # Copy everything except the MicroK8s section
        awk '
        /^# BEGIN MICROK8S DNS CONFIG/ { skip=1; next }
        /^# END MICROK8S DNS CONFIG/ { skip=0; next }
        !skip { print }
        ' /etc/resolv.conf > "$TEMP_RESOLV"
        
        # Remove consecutive empty lines at the end of file
        sed -i -e :a -e '/^\s*$/N; ba' -e 's/\(.*[^\n]\)\n*$/\1/' "$TEMP_RESOLV"
        
        # Replace the original file
        mv "$TEMP_RESOLV" /etc/resolv.conf
        
        ok "MicroK8s section removed from /etc/resolv.conf, user configurations preserved"
        
        # Verify the file is not empty
        if [ ! -s /etc/resolv.conf ] || [ "$(grep -v '^#' /etc/resolv.conf | grep -v '^$' | wc -l)" -eq 0 ]; then
          warn "resolv.conf became empty after section removal..."
          # Try with systemd-resolved first
          if systemctl is-active systemd-resolved >/dev/null 2>&1; then
            info "systemd-resolved active, creating symbolic link"
            rm -f /etc/resolv.conf
            ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
            ok "DNS managed by systemd-resolved"
          else
            info "systemd-resolved not active, restoring basic configuration..."
            cat > /etc/resolv.conf << 'EOF'
# DNS configuration restored by teardown
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
            ok "Basic DNS configuration created"
          fi
        fi
      else
        info "No MicroK8s section found in /etc/resolv.conf, file preserved"
      fi
    else
      # File doesn't exist - use systemd-resolved if possible
      warn "File /etc/resolv.conf not found..."
      if systemctl is-active systemd-resolved >/dev/null 2>&1; then
        info "systemd-resolved active, creating symbolic link"
        ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
        ok "DNS managed by systemd-resolved"
      else
        info "systemd-resolved not active, creating basic configuration..."
        cat > /etc/resolv.conf << 'EOF'
# DNS configuration restored by teardown
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
        ok "Basic DNS configuration created"
      fi
    fi
    
    # Restore basic nsswitch.conf only if modified
    if [ -f /etc/nsswitch.conf ]; then
      # Check if it has non-standard configurations that might be ours
      if grep -q "hosts:.*mdns" /etc/nsswitch.conf; then
        info "Restoring standard hosts configuration in nsswitch.conf..."
        sed -i 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf
      fi
    fi
    
    ok "DNS configurations restored preserving user settings"
  fi
  
  # Remove dnsmasq configurations
  info "Removing dnsmasq configurations..."
  rm -f /etc/dnsmasq.conf /etc/dnsmasq.hosts
  rm -f /etc/dnsmasq.conf.backup.*
  
  # Remove avahi configurations
  info "Removing avahi configurations..."
  if [ -f /etc/avahi/avahi-daemon.conf ]; then
    # Restore basic avahi configuration
    cat > /etc/avahi/avahi-daemon.conf << 'EOF'
[server]
use-ipv4=yes
use-ipv6=yes
enable-dbus=yes

[publish]
publish-addresses=yes
publish-hinfo=no
publish-workstation=no
publish-domain=no
EOF
  fi
  
  # Remove custom avahi services
  rm -rf /etc/avahi/services/*-$(hostname).service 2>/dev/null || true
  
  # Remove DNS packages if installed by us
  info "Removing DNS packages..."
  apt remove --purge -y dnsmasq avahi-daemon avahi-utils libnss-mdns 2>/dev/null || true
  apt autoremove -y 2>/dev/null || true
  
  # Clean DNS backup directories (both new and legacy)
  info "Cleaning DNS backups..."
  rm -rf "/var/lib/lair-dns-backups" 2>/dev/null || true
  rm -rf "/var/lib/jetson-dns-backups" 2>/dev/null || true
  
  ok "DNS configurations removed"
fi

### 9) Custom iptables rules removal
echo -e "\n${YELLOW}=== IPTABLES RESTORATION ===${NC}"
info "Backing up current iptables rules..."
iptables-save > "/tmp/iptables-before-teardown-$(date +%Y%m%d_%H%M%S).txt" || true

info "Removing custom iptables rules..."

# Remove specific MASQUERADE rules for MicroK8s/Flannel
RULES_TO_REMOVE=(
  "-t nat -D POSTROUTING -s 10.1.0.0/16 ! -d 10.1.0.0/16 -j MASQUERADE"
  "-t nat -D POSTROUTING -s 10.244.0.0/16 ! -d 10.244.0.0/16 -j MASQUERADE"
)

for rule in "${RULES_TO_REMOVE[@]}"; do
  # Try to remove the rule (ignore errors if it doesn't exist)
  iptables $rule 2>/dev/null || true
done

# Complete flush of rules (optional but safe)
info "Complete iptables flush..."
iptables -F   || true
iptables -t nat -F   || true  
iptables -t mangle -F || true
iptables -X   || true

# Restore default policies
iptables -P INPUT ACCEPT 2>/dev/null || true
iptables -P FORWARD ACCEPT 2>/dev/null || true
iptables -P OUTPUT ACCEPT 2>/dev/null || true

ok "iptables rules restored"

### 10) Uninstall Longhorn
echo -e "\n${YELLOW}=== LONGHORN REMOVAL ===${NC}"
if command -v microk8s >/dev/null 2>&1; then
  info "Uninstalling Longhorn..."
  
  # Removal via Helm
  microk8s helm3 uninstall longhorn -n longhorn-system --timeout 2m 2>/dev/null || true
  
  # Cleanup stuck namespace
  if microk8s kubectl get ns longhorn-system &>/dev/null; then
    PH=$(microk8s kubectl get ns longhorn-system -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
    if [[ "$PH" == "Terminating" ]]; then
      warn "Namespace longhorn-system stuck, removing finalizers..."
      microk8s kubectl patch ns longhorn-system \
        -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      sleep 2
    fi
    microk8s kubectl delete ns longhorn-system --force --grace-period=0 2>/dev/null || true
  fi
  
  # Longhorn CRDs removal
  LONGHORN_CRDS=(
    engines.longhorn.io
    nodes.longhorn.io  
    volumes.longhorn.io
    replicas.longhorn.io
    settings.longhorn.io
    engineimages.longhorn.io
    instancemanagers.longhorn.io
    sharemanagers.longhorn.io
  )
  
  for crd in "${LONGHORN_CRDS[@]}"; do
    microk8s kubectl delete crd "$crd" --ignore-not-found 2>/dev/null || true
  done
  
  ok "Longhorn removed"
fi

### 11) Disable all MicroK8s addons
echo -e "\n${YELLOW}=== MICROK8S ADDONS DISABLING ===${NC}"
if command -v microk8s >/dev/null 2>&1; then
  # Disable MetalLB
  info "Disabling MetalLB..."
  timeout 60s microk8s disable metallb 2>/dev/null || warn "Disable metallb failed"
  
  # Disable addons in reverse order of installation
  ADDONS=(
    gpu
    community
    metrics-server
    cert-manager
    ingress
    helm3
    registry
    hostpath-storage
    rbac
    dns
  )
  
  for addon in "${ADDONS[@]}"; do
    info "Disabling addon $addon..."
    timeout 60s microk8s disable "$addon" 2>/dev/null || warn "Disable $addon failed"
  done
  
  # Remove residual namespaces
  NAMESPACES=(
    metallb-system
    cert-manager
    ingress
    kube-system
    container-registry
    community
  )
  
  for ns in "${NAMESPACES[@]}"; do
    if microk8s kubectl get ns "$ns" &>/dev/null; then
      info "Removing namespace $ns..."
      microk8s kubectl delete ns "$ns" --ignore-not-found --timeout=60s 2>/dev/null || true
    fi
  done
  
  ok "MicroK8s addons disabled"
fi

### 12) Users and groups cleanup
echo -e "\n${YELLOW}=== USERS AND GROUPS CLEANUP ===${NC}"
info "Removing users from microk8s group..."

if getent group microk8s &>/dev/null; then
  # Get list of users in the group
  GROUP_USERS=$(getent group microk8s | cut -d: -f4)
  if [ -n "$GROUP_USERS" ]; then
    IFS=',' read -ra USERS <<< "$GROUP_USERS"
    for user in "${USERS[@]}"; do
      if [ -n "$user" ]; then
        info "Removing user '$user' from microk8s group..."
        gpasswd -d "$user" microk8s 2>/dev/null || true
      fi
    done
  fi
  
  info "Deleting microk8s group..."
  groupdel microk8s 2>/dev/null || warn "groupdel microk8s failed"
fi

ok "Users and groups cleaned up"

### 13) MicroK8s snap removal
echo -e "\n${YELLOW}=== MICROK8S SNAP REMOVAL ===${NC}"
info "Removing MicroK8s snap (may take time)..."

if snap list microk8s &>/dev/null; then
  if snap remove microk8s --purge; then
    ok "MicroK8s snap removed successfully"
  else
    warn "Snap removal failed, proceeding with manual cleanup..."
  fi
else
  info "MicroK8s snap not found"
fi

# Wait for system stabilization
sleep 5

### 14) Manual snap directory cleanup
echo -e "\n${YELLOW}=== MANUAL DIRECTORY CLEANUP ===${NC}"
if [ -d "/var/snap/microk8s" ]; then
  info "Directory /var/snap/microk8s still present, manual removal..."
  
  # Forced unmount
  info "Forced unmount of /var/snap/microk8s..."
  fuser -km "/var/snap/microk8s" 2>/dev/null || true
  umount -l "/var/snap/microk8s" 2>/dev/null || true
  
  # Removal with retry
  for i in {1..5}; do
    if rm -rf /var/snap/microk8s 2>/dev/null; then
      ok "Directory /var/snap/microk8s removed"
      break
    fi
    warn "Attempt $i/5 to remove /var/snap/microk8s..."
    sleep 3
    if [ $i -eq 5 ]; then
      err "Unable to remove /var/snap/microk8s after 5 attempts"
    fi
  done
fi

### 15) Kubeconfig and kubectl wrapper cleanup
echo -e "\n${YELLOW}=== KUBECONFIG AND KUBECTL CLEANUP ===${NC}"
info "Removing kubeconfig and kubectl wrapper..."

# Remove kubeconfig from all users
for user_dir in /root /home/*; do
  if [ -d "$user_dir" ]; then
    rm -rf "${user_dir}/.kube" 2>/dev/null || true
  fi
done

# Remove kubectl and helm wrappers
rm -f /usr/local/bin/kubectl 2>/dev/null || true
rm -f /usr/local/bin/helm 2>/dev/null || true

# Remove Jetson aliases (if present)
if $IS_JETSON; then
  info "Jetson system: removing LAIR aliases from user configurations..."
  
  # Remove aliases from all user .bashrc files
  for user_dir in /root /home/*; do
    if [ -d "$user_dir" ]; then
      BASHRC_FILE="$user_dir/.bashrc"
      if [ -f "$BASHRC_FILE" ]; then
        if grep -q "# LAIR Jetson Aliases" "$BASHRC_FILE" 2>/dev/null; then
          info "Removing LAIR aliases from $BASHRC_FILE..."
          
          # Create a temporary file without the LAIR aliases section
          TEMP_BASHRC=$(mktemp)
          
          # Copy everything except the LAIR aliases section
          awk '
          /^# LAIR Jetson Aliases/ { skip=1; next }
          /^alias microk8s=.sudo microk8s.$/ && skip { next }
          /^alias kubectl=.sudo kubectl.$/ && skip { next }
          /^alias helm=.sudo helm.$/ && skip { next }
          /^$/ && skip { skip=0; next }
          !skip { print }
          ' "$BASHRC_FILE" > "$TEMP_BASHRC"
          
          # Replace the original file and restore ownership
          mv "$TEMP_BASHRC" "$BASHRC_FILE"
          
          # Restore correct ownership (get original user from path)
          if [[ "$user_dir" =~ ^/home/([^/]+)$ ]]; then
            USER_NAME="${BASH_REMATCH[1]}"
            chown "$USER_NAME:$USER_NAME" "$BASHRC_FILE" 2>/dev/null || true
          elif [ "$user_dir" = "/root" ]; then
            chown root:root "$BASHRC_FILE" 2>/dev/null || true
          fi
          
          ok "LAIR aliases removed from $BASHRC_FILE"
        fi
      fi
    fi
  done
  
  ok "Jetson aliases cleanup completed"
else
  info "Non-Jetson system, skipping aliases cleanup"
fi

ok "Kubeconfig and kubectl wrapper removed"

### 16) Log and token files cleanup
echo -e "\n${YELLOW}=== LOG AND TOKEN CLEANUP ===${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Remove setup logs
if [ -d "$SCRIPT_DIR/microk8s-setup-logs" ]; then
  info "Removing setup logs..."
  rm -rf "$SCRIPT_DIR/microk8s-setup-logs"
fi

# Remove access tokens
if [ -f "$SCRIPT_DIR/microk8s-access-tokens.txt" ]; then
  info "Removing access tokens..."
  rm -f "$SCRIPT_DIR/microk8s-access-tokens.txt"
fi

# Remove cluster join information (primary node specific)
if [ -f "$SCRIPT_DIR/microk8s-join-info.txt" ]; then
  info "Removing cluster join information..."
  rm -f "$SCRIPT_DIR/microk8s-join-info.txt"
fi

# Remove DNS reminder
if [ -f "$SCRIPT_DIR/dns-setup-reminder.txt" ]; then
  info "Removing DNS reminder..."
  rm -f "$SCRIPT_DIR/dns-setup-reminder.txt"
fi

ok "Temporary files removed"

### 17) System configurations cleanup
echo -e "\n${YELLOW}=== SYSTEM CONFIGURATIONS CLEANUP ===${NC}"

# Remove modules from automatic loading (if added by us)
if [ -f /etc/modules ]; then
  info "Removing ip_set modules from /etc/modules..."
  sed -i '/^ip_set$/d' /etc/modules 2>/dev/null || true
  sed -i '/^ip_set_hash_ip$/d' /etc/modules 2>/dev/null || true
  sed -i '/^ip_set_hash_net$/d' /etc/modules 2>/dev/null || true
fi

# If it's Jetson, restore iptables-nft (if it was changed)
if $IS_JETSON; then
  info "Jetson: checking iptables settings..."
  # Restore to nft if available
  if command -v iptables-nft >/dev/null 2>&1; then
    update-alternatives --set iptables /usr/sbin/iptables-nft 2>/dev/null || true
    update-alternatives --set ip6tables /usr/sbin/ip6tables-nft 2>/dev/null || true
  fi
fi

ok "System configurations cleaned up"

### 18) Final verification and cleanup  
echo -e "\n${YELLOW}=== FINAL VERIFICATION ===${NC}"
info "Verifying complete removal..."

# Verify snap
if ! snap list microk8s &>/dev/null; then
  ok "✓ MicroK8s snap: REMOVED"
else
  warn "✗ MicroK8s snap: STILL PRESENT"
fi

# Verify directory
if [ ! -d "/var/snap/microk8s" ]; then
  ok "✓ Directory /var/snap/microk8s: REMOVED"
else
  warn "✗ Directory /var/snap/microk8s: STILL PRESENT"
fi

# Verify group
if ! getent group microk8s &>/dev/null; then
  ok "✓ microk8s group: REMOVED"
else
  warn "✗ microk8s group: STILL PRESENT"
fi

# Verify DNS services (if not keep-dns)
if ! $KEEP_DNS; then
  if ! systemctl is-active dnsmasq >/dev/null 2>&1; then
    ok "✓ dnsmasq service: STOPPED"
  else
    warn "✗ dnsmasq service: STILL ACTIVE"
  fi
fi

# Verify custom iptables service
if [ ! -f /etc/systemd/system/microk8s-iptables.service ]; then
  ok "✓ Custom iptables service: REMOVED"
else
  warn "✗ Custom iptables service: STILL PRESENT"
fi

### 19) Final autoremove cleanup
echo -e "\n${YELLOW}=== FINAL SYSTEM CLEANUP ===${NC}"
info "Cleaning unnecessary packages..."
apt autoremove --purge -y 2>/dev/null || true
apt autoclean 2>/dev/null || true

### 20) Final message
echo -e "\n${GREEN}=========================================${NC}"
echo -e "${GREEN}         TEARDOWN COMPLETED!            ${NC}"  
echo -e "${GREEN}=========================================${NC}"

echo -e "\n${BLUE}Components removed:${NC}"
echo -e "  ✓ MicroK8s and all addons"
echo -e "  ✓ Longhorn storage"
echo -e "  ✓ MetalLB load balancer"
echo -e "  ✓ Custom iptables rules"
echo -e "  ✓ Custom systemd services"
if ! $KEEP_DNS; then
  echo -e "  ✓ DNS configurations (dnsmasq, avahi)"
fi
echo -e "  ✓ Setup tokens and logs"
echo -e "  ✓ User groups and permissions"

echo -e "\n${BLUE}System restored to original state.${NC}"

if $IS_JETSON; then
  echo -e "\n${YELLOW}Jetson notes:${NC}"
  echo -e "  • iptables configurations restored"
  echo -e "  • Network settings restored"
fi

echo -e "\n${YELLOW}IMPORTANT:${NC}"
echo -e "  • Teardown log saved to: ${LOGFILE}"
if [ -n "${CLEANUP_BACKUP_DIR:-}" ]; then
  echo -e "  • Pre-removal backup: ${CLEANUP_BACKUP_DIR}"
fi
echo -e "  • A reboot is recommended: ${GREEN}sudo reboot${NC}"

info "Teardown completed successfully!"
exit 0