#!/usr/bin/env bash
#─────────────────────────────────────────────────────────────────────────────
# test_velero_config.sh – Test Velero configuration and installation
# Usage: sudo ./test_velero_config.sh
#─────────────────────────────────────────────────────────────────────────────

# Set the base directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required modules
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/helpers.sh"
source "$LIB_DIR/microk8s_velero.sh"

info "🧪 Testing Velero configuration and installation"

# Check if Velero configuration exists
if [[ -f "/etc/lair_velero_config.env" ]]; then
  ok "Velero configuration file found at /etc/lair_velero_config.env"
  source "/etc/lair_velero_config.env"
  
  info "Configuration loaded:"
  echo "  • LAIR_VELERO_ENABLE: ${LAIR_VELERO_ENABLE}"
  echo "  • LAIR_VELERO_NAMESPACE: ${LAIR_VELERO_NAMESPACE}"
  echo "  • LAIR_VELERO_PROVIDER: ${LAIR_VELERO_PROVIDER}"
  echo "  • LAIR_VELERO_BUCKET: ${LAIR_VELERO_BUCKET}"
  echo "  • LAIR_VELERO_REGION: ${LAIR_VELERO_REGION}"
  echo "  • LAIR_VELERO_S3URL: ${LAIR_VELERO_S3URL}"
  echo "  • Access Key: ${LAIR_VELERO_ACCESS_KEY:0:8}..."
else
  warn "Velero configuration file not found at /etc/lair_velero_config.env"
  info "This means Velero was not configured during setup"
  exit 0
fi

# Check if MicroK8s is running
if microk8s status --wait-ready --timeout 10 >/dev/null 2>&1; then
  ok "MicroK8s is running and ready"
else
  warn "MicroK8s is not ready - cannot test Velero installation"
  exit 1
fi

# Check if Velero namespace exists
if microk8s kubectl get namespace velero >/dev/null 2>&1; then
  ok "Velero namespace exists"
else
  warn "Velero namespace does not exist"
fi

# Check if Velero pods are running
info "Checking Velero pods..."
microk8s kubectl get pods -n velero 2>/dev/null || warn "No Velero pods found"

# Check if Velero is installed via Helm
info "Checking Helm releases..."
helm list -n velero 2>/dev/null || warn "No Helm releases found in velero namespace"

info "🧪 Velero configuration test completed"
