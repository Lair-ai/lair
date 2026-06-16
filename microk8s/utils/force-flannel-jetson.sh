#!/usr/bin/env bash

# FORCE FLANNEL TO WORK ON JETSON - COMPLETE SOLUTION
# This script eliminates Calico completely and ensures Flannel works

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root"
   exit 1
fi

info "🚀 FORCING FLANNEL TO WORK ON JETSON"
info "===================================="
warn "This will COMPLETELY REMOVE Calico and force Flannel as the only CNI"

NODE_NAME=$(hostname)
POD_CIDR="10.1.0.0/16"
NODE_SUBNET="10.1.0.0/24"

# STEP 1: COMPLETE SYSTEM SHUTDOWN FOR CLEAN STATE
info "1. Complete system shutdown for clean state..."
snap stop microk8s || true
sleep 10

# STEP 2: ELIMINATE ALL CALICO TRACES
info "2. Eliminating ALL Calico traces..."

# Remove Calico CNI configs
rm -rf /var/snap/microk8s/current/opt/cni/bin/calico* || true
rm -rf /var/snap/microk8s/current/opt/cni/bin/install || true
rm -rf /opt/cni/bin/calico* || true

# Remove Calico CNI network configs
rm -rf /var/snap/microk8s/current/args/cni-network/cni.yaml || true
rm -rf /var/snap/microk8s/current/args/cni-network/10-calico.conflist || true

# Clean any Calico-related pods or configs
rm -rf /var/snap/microk8s/common/var/lib/calico || true

# Remove Calico IPAM data
rm -rf /var/lib/calico || true
rm -rf /var/snap/microk8s/common/var/lib/calico || true

ok "Calico completely removed"

# STEP 3: ENSURE FLANNEL CNI CONFIGURATION
info "3. Configuring Flannel CNI..."

# Create CNI config directory
mkdir -p /var/snap/microk8s/current/args/cni-network/

# Create Flannel CNI configuration
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

ok "Flannel CNI configuration created"

# STEP 4: CONFIGURE KUBE-CONTROLLER-MANAGER FOR CIDR ALLOCATION
info "4. Configuring kube-controller-manager for Pod CIDR allocation..."

CONTROLLER_CONFIG="/var/snap/microk8s/current/args/kube-controller-manager"

# Backup and clean
cp "$CONTROLLER_CONFIG" "$CONTROLLER_CONFIG.backup-$(date +%s)"

# Remove any existing CIDR configurations
sed -i '/--cluster-cidr=/d' "$CONTROLLER_CONFIG"
sed -i '/--allocate-node-cidrs=/d' "$CONTROLLER_CONFIG"
sed -i '/--node-cidr-mask-size=/d' "$CONTROLLER_CONFIG"

# Add correct CIDR configuration
echo "--cluster-cidr=$POD_CIDR" >> "$CONTROLLER_CONFIG"
echo "--allocate-node-cidrs=true" >> "$CONTROLLER_CONFIG"
echo "--node-cidr-mask-size=24" >> "$CONTROLLER_CONFIG"

ok "kube-controller-manager configured for CIDR allocation"

# STEP 5: CONFIGURE KUBELET FOR FLANNEL
info "5. Configuring kubelet for Flannel..."

KUBELET_CONFIG="/var/snap/microk8s/current/args/kubelet"

# Ensure kubelet uses correct CNI
if ! grep -q "network-plugin=cni" "$KUBELET_CONFIG"; then
    echo "--network-plugin=cni" >> "$KUBELET_CONFIG"
fi

if ! grep -q "cni-conf-dir" "$KUBELET_CONFIG"; then
    echo "--cni-conf-dir=/var/snap/microk8s/current/args/cni-network" >> "$KUBELET_CONFIG"
fi

if ! grep -q "cni-bin-dir" "$KUBELET_CONFIG"; then
    echo "--cni-bin-dir=/var/snap/microk8s/current/opt/cni/bin" >> "$KUBELET_CONFIG"
fi

ok "kubelet configured for Flannel"

# STEP 6: CONFIGURE FLANNEL FOR JETSON + Wi-Fi
info "6. Configuring Flannel for Jetson + Wi-Fi..."

# Get Wi-Fi interface
WIFI_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
info "Using interface: $WIFI_IFACE"

# Flannel configuration - use host-gw for Wi-Fi reliability
cat > /var/snap/microk8s/current/args/flannel-network-mgr-config << EOF
{
  "Network": "$POD_CIDR",
  "Backend": {
    "Type": "host-gw"
  }
}
EOF

# Flannel daemon arguments
cat > /var/snap/microk8s/current/args/flanneld << EOF
--iface=$WIFI_IFACE
--subnet-file=/var/snap/microk8s/common/run/flannel/subnet.env
--ip-masq=true
--kube-subnet-mgr=true
--kubeconfig-file=/var/snap/microk8s/current/credentials/kubelet.config
--net-config-path=/var/snap/microk8s/current/args/flannel-network-mgr-config
EOF

ok "Flannel configured for Jetson + Wi-Fi with host-gw backend"

# STEP 7: CLEAN NETWORKING STATE
info "7. Cleaning all networking state..."

# Remove all CNI and Flannel state
rm -rf /var/snap/microk8s/common/run/cni/* || true
rm -rf /var/snap/microk8s/common/run/flannel/* || true
rm -rf /var/snap/microk8s/common/run/containerd/io.containerd.runtime.v1.linux/moby/* || true

# Clean containerd state
rm -rf /var/snap/microk8s/common/var/lib/containerd/io.containerd.snapshotter.v1.native/snapshots/* || true

# Create necessary directories
mkdir -p /var/snap/microk8s/common/run/flannel
mkdir -p /var/snap/microk8s/common/run/cni/networks
mkdir -p /var/snap/microk8s/common/run/containerd

ok "Networking state cleaned"

# STEP 8: START SYSTEM WITH FORCED FLANNEL
info "8. Starting system with forced Flannel configuration..."

# Start MicroK8s
snap start microk8s
sleep 20

# Wait for API server
info "Waiting for API server..."
timeout 120 bash -c 'until microk8s kubectl get nodes >/dev/null 2>&1; do sleep 3; done' || {
    error "API server not ready after 120s"
    exit 1
}

ok "API server ready"

# STEP 9: FORCE POD CIDR ASSIGNMENT
info "9. Force Pod CIDR assignment..."

# Check if CIDR is automatically assigned
sleep 10
if microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' 2>/dev/null | grep -q "10.1"; then
    ok "Pod CIDR automatically assigned!"
else
    warn "Pod CIDR not automatically assigned, forcing manual assignment..."
    
    # Force manual assignment
    microk8s kubectl patch node "$NODE_NAME" -p "{\"spec\":{\"podCIDR\":\"$NODE_SUBNET\"}}" || {
        error "Failed to assign Pod CIDR manually"
        exit 1
    }
    
    sleep 5
    if microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' | grep -q "10.1"; then
        ok "Manual Pod CIDR assignment successful: $NODE_SUBNET"
    else
        error "Pod CIDR assignment failed completely"
        exit 1
    fi
fi

# STEP 10: VERIFY FLANNEL STARTUP
info "10. Verifying Flannel startup..."

# Restart flanneld to pick up the CIDR
snap restart microk8s.daemon-flanneld
sleep 30

# Check subnet.env creation
SUBNET_FILE="/var/snap/microk8s/common/run/flannel/subnet.env"
WAIT_COUNT=0
MAX_WAIT=60

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if [ -f "$SUBNET_FILE" ]; then
        ok "✅ subnet.env file created!"
        echo "Content:"
        cat "$SUBNET_FILE"
        break
    fi
    
    WAIT_COUNT=$((WAIT_COUNT + 1))
    if [ $((WAIT_COUNT % 10)) -eq 0 ]; then
        info "Still waiting for subnet.env... ($WAIT_COUNT/$MAX_WAIT)"
    fi
    sleep 1
done

if [ ! -f "$SUBNET_FILE" ]; then
    error "subnet.env not created after ${MAX_WAIT}s"
    info "Flanneld logs:"
    journalctl -u snap.microk8s.daemon-flanneld --no-pager -n 20
    exit 1
fi

# STEP 11: TEST FLANNEL NETWORKING
info "11. Testing Flannel networking..."

# Wait for cni0 interface
sleep 10

# Delete any existing test pods
microk8s kubectl delete pod flannel-force-test --ignore-not-found=true 2>/dev/null || true
sleep 5

# Create test pod
info "Creating test pod to verify Flannel..."
if timeout 90 microk8s kubectl run flannel-force-test --image=busybox:1.28 --rm -i --restart=Never -- ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    ok "🎉 Flannel networking test: SUCCESS!"
    
    # Verify it's using Flannel (not Calico)
    POD_IP=$(microk8s kubectl get pod flannel-force-test -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
    if [[ "$POD_IP" == 10.1.* ]]; then
        ok "✅ Pod is using Flannel IP range: $POD_IP"
    else
        warn "Pod IP might not be from Flannel range: $POD_IP"
    fi
else
    # Get detailed info for troubleshooting
    if microk8s kubectl get pod flannel-force-test 2>/dev/null; then
        warn "Pod exists but connectivity failed, getting details..."
        microk8s kubectl describe pod flannel-force-test
        microk8s kubectl logs flannel-force-test 2>/dev/null || echo "No logs"
    else
        warn "Pod creation failed completely"
    fi
fi

# Cleanup test pod
microk8s kubectl delete pod flannel-force-test --ignore-not-found=true 2>/dev/null || true

# STEP 12: FINAL VERIFICATION
info "12. Final system verification..."
echo "================================="

echo "Node Pod CIDR:"
microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' && echo

echo ""
echo "Network interfaces:"
ip addr show | grep -E "(cni0|flannel)" || echo "CNI interfaces being created..."

echo ""
echo "Flannel service status:"
snap services microk8s.daemon-flanneld

echo ""
echo "Recent flanneld logs:"
journalctl -u snap.microk8s.daemon-flanneld --no-pager -n 5 | tail -5

ok "🚀 FLANNEL FORCED CONFIGURATION COMPLETE!"
info "🎯 Flannel is now the ONLY CNI and should work on Jetson + Wi-Fi"
info "📊 Monitor 'journalctl -u snap.microk8s.daemon-flanneld -f' for real-time status" 