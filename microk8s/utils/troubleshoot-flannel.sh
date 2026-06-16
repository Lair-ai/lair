#!/usr/bin/env bash

# Flannel Troubleshooting Script for Jetson
# Usage: ./troubleshoot-flannel.sh

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
   exit 1
fi

info "🔍 Flannel Troubleshooting Script for Jetson"
info "========================================"

# 1. Check MicroK8s status
info "1. Checking MicroK8s status..."
if microk8s status --wait-ready 2>/dev/null; then
    ok "MicroK8s is running"
else
    error "MicroK8s is not ready"
    microk8s status
fi

# 2. Check Flannel services
info "2. Checking Flannel services..."
echo "MicroK8s services status:"
snap services microk8s

# Check flanneld specifically
if snap services microk8s.daemon-flanneld | grep -q "active"; then
    ok "flanneld service is active"
else
    warn "flanneld service is not active"
fi

# 3. Check subnet.env file
info "3. Checking subnet.env file..."
SUBNET_FILE="/var/snap/microk8s/common/run/flannel/subnet.env"
if [ -f "$SUBNET_FILE" ]; then
    ok "subnet.env file exists"
    echo "Content:"
    cat "$SUBNET_FILE"
else
    error "subnet.env file is missing"
    info "Flannel directory contents:"
    ls -la /var/snap/microk8s/common/run/flannel/ || echo "Directory does not exist"
fi

# 4. Check network interfaces
info "4. Checking network interfaces..."

# Check cni0
if ip addr show cni0 >/dev/null 2>&1; then
    ok "cni0 interface exists"
    ip addr show cni0
else
    warn "cni0 interface does not exist"
fi

# Check flannel.1
if ip addr show flannel.1 >/dev/null 2>&1; then
    ok "flannel.1 (VXLAN) interface exists"
    ip addr show flannel.1
else
    warn "flannel.1 interface does not exist"
fi

# Check main interface
MAIN_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
info "Main network interface: $MAIN_IFACE"
if [[ "$MAIN_IFACE" == *"wl"* ]] || [[ "$MAIN_IFACE" == *"wlan"* ]]; then
    warn "Using Wi-Fi interface - VXLAN may have issues"
    echo "Wi-Fi interface details:"
    ip addr show "$MAIN_IFACE"
    
    # Check if VXLAN offloading is enabled
    info "Checking VXLAN offloading capabilities..."
    ethtool -k "$MAIN_IFACE" 2>/dev/null | grep -E "(udp|tunnel|segmentation)" || echo "ethtool info not available"
else
    ok "Using wired interface"
fi

# 5. Check VXLAN module
info "5. Checking VXLAN kernel module..."
if lsmod | grep -q vxlan; then
    ok "VXLAN module is loaded"
else
    warn "VXLAN module is not loaded"
    info "Attempting to load VXLAN module..."
    modprobe vxlan && ok "VXLAN module loaded successfully" || error "Failed to load VXLAN module"
fi

# 6. Check iptables rules
info "6. Checking iptables MASQUERADE rules..."
if iptables -t nat -L POSTROUTING | grep -q MASQUERADE; then
    ok "MASQUERADE rules found"
    iptables -t nat -L POSTROUTING | grep MASQUERADE
else
    warn "No MASQUERADE rules found"
fi

# 7. Check routing
info "7. Checking routing table..."
echo "Routes related to CNI:"
ip route show | grep cni0 || echo "No CNI routes found"

echo "Default route:"
ip route show default

# 8. Check flanneld logs
info "8. Checking flanneld logs (last 30 lines)..."
journalctl -u snap.microk8s.daemon-flanneld --no-pager -n 30

# 9. Check flanneld configuration
info "9. Checking flanneld configuration..."
echo "Flannel network configuration:"
cat /var/snap/microk8s/current/args/flannel-network-mgr-config 2>/dev/null || echo "Config file not found"

echo "Flanneld arguments:"
cat /var/snap/microk8s/current/args/flanneld 2>/dev/null || echo "Args file not found"

# 10. Test pod connectivity
info "10. Testing pod connectivity..."
kubectl delete pod flannel-test --ignore-not-found=true 2>/dev/null || true
sleep 5

info "Creating test pod..."
if timeout 60 kubectl run flannel-test --image=busybox:1.28 --rm -i --restart=Never -- ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    ok "Pod connectivity test: SUCCESS ✅"
else
    warn "Pod connectivity test: FAILED ❌"
    
    # Check if pod exists
    if kubectl get pod flannel-test 2>/dev/null; then
        echo "Pod details:"
        kubectl describe pod flannel-test
        echo "Pod logs:"
        kubectl logs flannel-test 2>/dev/null || echo "No logs available"
    fi
    
    # Cleanup
    kubectl delete pod flannel-test --ignore-not-found=true 2>/dev/null || true
fi

# 11. Recommendations
info "11. Recommendations and solutions..."

if [[ "$MAIN_IFACE" == *"wl"* ]] || [[ "$MAIN_IFACE" == *"wlan"* ]]; then
    warn "🔧 Wi-Fi detected - Common issues and solutions:"
    echo "   1. Use wired Ethernet connection if possible"
    echo "   2. Switch to host-gw backend instead of VXLAN:"
    echo "      sudo echo '{\"Network\": \"10.1.0.0/16\", \"Backend\": {\"Type\": \"host-gw\"}}' > /var/snap/microk8s/current/args/flannel-network-mgr-config"
    echo "      sudo snap restart microk8s.daemon-flanneld"
    echo "   3. Disable VXLAN hardware offloading:"
    echo "      sudo ethtool -K $MAIN_IFACE tx-udp_tnl-segmentation off 2>/dev/null || true"
    echo "      sudo ethtool -K $MAIN_IFACE rx-udp_tnl-port-offload off 2>/dev/null || true"
fi

if [ ! -f "$SUBNET_FILE" ]; then
    warn "🔧 subnet.env missing - Try these solutions:"
    echo "   1. Restart flanneld: sudo snap restart microk8s.daemon-flanneld"
    echo "   2. Check RBAC permissions: microk8s kubectl auth can-i get nodes --as=system:node:\$(hostname)"
    echo "   3. Complete restart: sudo microk8s stop && sleep 10 && sudo microk8s start"
fi

if ! ip addr show cni0 >/dev/null 2>&1; then
    warn "🔧 cni0 interface missing - This usually means:"
    echo "   1. No pods have been scheduled yet (normal)"
    echo "   2. CNI configuration issues"
    echo "   3. Try creating a test pod to trigger interface creation"
fi

info "🎯 Quick fix commands:"
echo "# Force complete Flannel restart:"
echo "sudo microk8s stop && sudo rm -rf /var/snap/microk8s/common/run/flannel/* && sudo microk8s start"
echo ""
echo "# Switch to host-gw backend (for Wi-Fi issues):"
echo "sudo echo '{\"Network\": \"10.1.0.0/16\", \"Backend\": {\"Type\": \"host-gw\"}}' > /var/snap/microk8s/current/args/flannel-network-mgr-config"
echo "sudo snap restart microk8s.daemon-flanneld"
echo ""
echo "# Check real-time flanneld logs:"
echo "journalctl -u snap.microk8s.daemon-flanneld -f"

ok "🏁 Troubleshooting complete!" 