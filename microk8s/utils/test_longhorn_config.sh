#!/usr/bin/env bash
#─────────────────────────────────────────────────────────────────────────────
# test_longhorn_config.sh – Test Longhorn configuration and installation
# Usage: sudo ./test_longhorn_config.sh
#─────────────────────────────────────────────────────────────────────────────

# Set the base directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required modules
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/helpers.sh"

info "🧪 Testing Longhorn configuration and installation"

# Check if MicroK8s is running
if microk8s status --wait-ready --timeout 10 >/dev/null 2>&1; then
  ok "MicroK8s is running and ready"
else
  warn "MicroK8s is not ready - cannot test Longhorn installation"
  exit 1
fi

# Test the replica count calculation logic
NODE_CNT=$(microk8s kubectl get nodes --no-headers | grep -cw ' Ready ')
REP_CNT=$(( NODE_CNT < 3 ? NODE_CNT : 2 ))     # 1→1, 2→2, ≥3→2
info "Node count calculation:"
echo "  • Ready nodes: ${NODE_CNT}"
echo "  • Calculated replica count: ${REP_CNT}"

# Test the Helm values string generation
LH_VALUES="--set csi.kubeletRootDir=/var/snap/microk8s/common/var/lib/kubelet \
           --set-string defaultSettings.defaultReplicaCount=${REP_CNT} \
           --set storageClass.allowVolumeExpansion=true"

info "Generated Helm values:"
echo "  ${LH_VALUES}"

# Check if Longhorn namespace exists
if microk8s kubectl get namespace longhorn-system >/dev/null 2>&1; then
  ok "Longhorn namespace exists"
else
  warn "Longhorn namespace does not exist"
fi

# Check if Longhorn is installed via Helm
info "Checking Longhorn Helm installation..."
if microk8s helm3 list -n longhorn-system | grep -iq '^longhorn'; then
  ok "Longhorn is installed via Helm"
  microk8s helm3 list -n longhorn-system
else
  warn "Longhorn is not installed via Helm"
fi

# Check Longhorn pods
info "Checking Longhorn pods..."
microk8s kubectl get pods -n longhorn-system 2>/dev/null || warn "No Longhorn pods found"

# Check storage classes
info "Checking storage classes..."
microk8s kubectl get sc 2>/dev/null || warn "Could not get storage classes"

# Check default storage class
DEFAULT_SC=$(microk8s kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "none")
info "Default storage class: ${DEFAULT_SC}"

info "🧪 Longhorn configuration test completed"
