#!/usr/bin/env bash

# Debug script to check Velero setup status
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required libraries
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/helpers.sh"
source "$LIB_DIR/microk8s_velero.sh"

info "🔍 Debugging Velero setup status"

# Check if MicroK8s is running
if microk8s status --wait-ready >/dev/null 2>&1; then
  ok "MicroK8s is running and ready"
else
  err "MicroK8s is not running or ready"
  exit 1
fi

# Check for Velero configuration files
info "📁 Checking for Velero configuration files..."

OLD_CONFIG="/tmp/lair_velero_config.env"
NEW_CONFIG="/etc/lair_velero_config.env"

if [[ -f "$OLD_CONFIG" ]]; then
  warn "Found old config file at $OLD_CONFIG"
  echo "Contents:"
  cat "$OLD_CONFIG" | head -10
  echo ""
fi

if [[ -f "$NEW_CONFIG" ]]; then
  ok "Found new config file at $NEW_CONFIG"
  echo "Contents:"
  cat "$NEW_CONFIG" | head -10
  echo ""
  
  # Load and show configuration
  source "$NEW_CONFIG"
  info "Loaded configuration:"
  echo "  • LAIR_VELERO_ENABLE: ${LAIR_VELERO_ENABLE:-<not set>}"
  echo "  • LAIR_VELERO_NAMESPACE: ${LAIR_VELERO_NAMESPACE:-<not set>}"
  echo "  • LAIR_VELERO_PROVIDER: ${LAIR_VELERO_PROVIDER:-<not set>}"
  echo "  • LAIR_VELERO_BUCKET: ${LAIR_VELERO_BUCKET:-<not set>}"
  echo "  • LAIR_VELERO_REGION: ${LAIR_VELERO_REGION:-<not set>}"
  echo "  • LAIR_VELERO_S3URL: ${LAIR_VELERO_S3URL:-<not set>}"
  echo ""
else
  warn "No new config file found at $NEW_CONFIG"
fi

# Check Velero namespace
info "🔍 Checking Velero namespace..."
if microk8s kubectl get namespace "${LAIR_VELERO_NAMESPACE:-velero}" >/dev/null 2>&1; then
  ok "Velero namespace exists"
else
  warn "Velero namespace does not exist"
fi

# Check Velero pods
info "🔍 Checking Velero pods..."
if microk8s kubectl get pods -n "${LAIR_VELERO_NAMESPACE:-velero}" >/dev/null 2>&1; then
  ok "Velero pods found:"
  microk8s kubectl get pods -n "${LAIR_VELERO_NAMESPACE:-velero}" -o wide
else
  warn "No Velero pods found"
fi

# Check Helm releases
info "🔍 Checking Helm releases..."
if helm list -n "${LAIR_VELERO_NAMESPACE:-velero}" | grep -q "velero"; then
  ok "Velero Helm release found:"
  helm list -n "${LAIR_VELERO_NAMESPACE:-velero}"
else
  warn "No Velero Helm release found"
fi

# Test manual installation if needed
if [[ "$LAIR_VELERO_ENABLE" == "true" ]] && [[ -f "$NEW_CONFIG" ]]; then
  echo ""
  info "🧪 Would you like to test manual Velero installation? (y/n)"
  read -r response
  if [[ "$response" =~ ^[Yy]$ ]]; then
    info "🚀 Testing manual Velero installation..."
    install_velero
  fi
fi

info "🔍 Velero debug completed"
