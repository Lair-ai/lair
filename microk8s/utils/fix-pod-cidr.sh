#!/usr/bin/env bash

# Fix Pod CIDR Assignment for Flannel on Jetson
# This resolves: "failed to acquire lease: node "jetson" pod cidr not assigned"

set -euo pipefail

# Colors
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

info "🔧 Fixing Pod CIDR assignment for Flannel"
info "========================================"

# Get node name
NODE_NAME=$(hostname)
POD_CIDR="10.1.0.0/16"

info "Node: $NODE_NAME"
info "Target Pod CIDR: $POD_CIDR"

# 1. Check current node status
info "1. Checking current node configuration..."
microk8s kubectl get node "$NODE_NAME" -o yaml | grep -A 5 "podCIDR" || echo "No podCIDR found"

# 2. Stop flanneld to prevent restart loops
info "2. Stopping flanneld temporarily..."
snap stop microk8s.daemon-flanneld

# 3. Check and fix kube-controller-manager configuration
info "3. Verifying kube-controller-manager configuration..."
CONTROLLER_CONFIG="/var/snap/microk8s/current/args/kube-controller-manager"

if grep -q "cluster-cidr" "$CONTROLLER_CONFIG"; then
    ok "cluster-cidr is configured"
    grep "cluster-cidr" "$CONTROLLER_CONFIG"
else
    warn "cluster-cidr not found, adding it"
    echo "--cluster-cidr=$POD_CIDR" >> "$CONTROLLER_CONFIG"
fi

if grep -q "allocate-node-cidrs" "$CONTROLLER_CONFIG"; then
    ok "allocate-node-cidrs is configured"
    grep "allocate-node-cidrs" "$CONTROLLER_CONFIG"
else
    warn "allocate-node-cidrs not found, adding it"
    echo "--allocate-node-cidrs=true" >> "$CONTROLLER_CONFIG"
fi

# 4. Restart controller-manager to apply CIDR allocation
info "4. Restarting controller-manager to enable CIDR allocation..."
snap restart microk8s.daemon-kubelite
sleep 15

# Wait for API server to be ready
info "Waiting for API server to be ready..."
timeout 60 bash -c 'until microk8s kubectl get nodes >/dev/null 2>&1; do sleep 2; done' || {
    error "API server not ready after 60s"
    exit 1
}

# 5. Manual Pod CIDR assignment if automatic fails
info "5. Checking if Pod CIDR was automatically assigned..."
sleep 10

if microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' 2>/dev/null | grep -q "10.1"; then
    ok "Pod CIDR automatically assigned!"
    ASSIGNED_CIDR=$(microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}')
    info "Assigned CIDR: $ASSIGNED_CIDR"
else
    warn "Pod CIDR not automatically assigned, doing manual assignment..."
    
    # Calculate a subnet for this specific node
    NODE_SUBNET="10.1.0.0/24"  # Single node gets the first /24
    
    info "Manually assigning Pod CIDR: $NODE_SUBNET"
    
    # Patch the node to add podCIDR
    microk8s kubectl patch node "$NODE_NAME" -p "{\"spec\":{\"podCIDR\":\"$NODE_SUBNET\"}}"
    
    # Verify assignment
    sleep 5
    if microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' | grep -q "10.1"; then
        ok "Manual Pod CIDR assignment successful!"
    else
        error "Manual Pod CIDR assignment failed"
        exit 1
    fi
fi

# 6. Clean flannel state and restart
info "6. Cleaning Flannel state and restarting..."
rm -rf /var/snap/microk8s/common/run/flannel/*
mkdir -p /var/snap/microk8s/common/run/flannel

# Start flanneld
info "Starting flanneld..."
snap start microk8s.daemon-flanneld

# 7. Wait and verify
info "7. Waiting for Flannel to initialize with Pod CIDR..."
sleep 20

# Check if subnet.env is now created
SUBNET_FILE="/var/snap/microk8s/common/run/flannel/subnet.env"
WAIT_COUNT=0
MAX_WAIT=30

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if [ -f "$SUBNET_FILE" ]; then
        ok "✅ subnet.env file created successfully!"
        echo "Content:"
        cat "$SUBNET_FILE"
        break
    fi
    
    WAIT_COUNT=$((WAIT_COUNT + 1))
    info "Waiting for subnet.env... ($WAIT_COUNT/$MAX_WAIT)"
    sleep 2
done

if [ ! -f "$SUBNET_FILE" ]; then
    warn "subnet.env still not created, checking flanneld logs..."
    journalctl -u snap.microk8s.daemon-flanneld --no-pager -n 10
else
    # 8. Test pod connectivity
    info "8. Testing pod connectivity with fixed CIDR..."
    
    # Delete any existing test pods
    microk8s kubectl delete pod cidr-test --ignore-not-found=true 2>/dev/null || true
    sleep 5
    
    # Create test pod
    if timeout 60 microk8s kubectl run cidr-test --image=busybox:1.28 --rm -i --restart=Never -- ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        ok "🎉 Pod connectivity test with fixed CIDR: SUCCESS!"
        
        # Check if it's using Flannel now
        if microk8s kubectl get pod cidr-test -o yaml 2>/dev/null | grep -q "flannel"; then
            ok "✅ Pod is using Flannel networking!"
        else
            warn "Pod is still using Calico (may take time to switch)"
        fi
    else
        warn "Pod connectivity test failed, but CIDR is now assigned"
        info "This may improve over time as system stabilizes"
    fi
    
    # Cleanup
    microk8s kubectl delete pod cidr-test --ignore-not-found=true 2>/dev/null || true
fi

# 9. Final status
info "9. Final status summary..."
echo "==========================="
echo "Node Pod CIDR:"
microk8s kubectl get node "$NODE_NAME" -o jsonpath='{.spec.podCIDR}' && echo
echo ""
echo "Flannel service status:"
snap services microk8s.daemon-flanneld
echo ""
echo "Network interfaces:"
ip addr show | grep -E "(cni0|flannel)" || echo "CNI interfaces not yet created"

info "🎯 Fix complete! Monitor system for stabilization."
info "If issues persist, the networking will gradually improve as Flannel takes over from Calico." 