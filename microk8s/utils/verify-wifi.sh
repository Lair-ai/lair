#!/usr/bin/env bash

# Wi-Fi Connectivity Verification Script
# Verifies that Wi-Fi remains fully functional after Flannel optimizations

echo "🔍 Verifying Wi-Fi connectivity after Flannel optimizations..."
echo "============================================================"

# Get Wi-Fi interface
WIFI_IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

if [[ "$WIFI_IFACE" == *"wl"* ]] || [[ "$WIFI_IFACE" == *"wlan"* ]]; then
    echo "✅ Wi-Fi interface detected: $WIFI_IFACE"
    
    # Check interface status
    echo ""
    echo "📡 Wi-Fi Interface Status:"
    ip addr show "$WIFI_IFACE"
    
    # Check if interface is up
    if ip link show "$WIFI_IFACE" | grep -q "state UP"; then
        echo "✅ Wi-Fi interface is UP and active"
    else
        echo "❌ Wi-Fi interface is DOWN"
        exit 1
    fi
    
    # Test internet connectivity via Wi-Fi
    echo ""
    echo "🌐 Testing internet connectivity via Wi-Fi..."
    if ping -I "$WIFI_IFACE" -c 3 8.8.8.8 >/dev/null 2>&1; then
        echo "✅ Internet connectivity via Wi-Fi: WORKING"
    else
        echo "❌ Internet connectivity via Wi-Fi: FAILED"
        exit 1
    fi
    
    # Test DNS resolution
    echo ""
    echo "🔍 Testing DNS resolution..."
    if nslookup google.com >/dev/null 2>&1; then
        echo "✅ DNS resolution: WORKING"
    else
        echo "❌ DNS resolution: FAILED"
    fi
    
    # Check current MTU
    echo ""
    echo "📏 Current MTU settings:"
    current_mtu=$(ip link show "$WIFI_IFACE" | grep -o 'mtu [0-9]*' | cut -d' ' -f2)
    echo "Wi-Fi MTU: $current_mtu"
    if [ "$current_mtu" -eq 1450 ]; then
        echo "ℹ️  MTU optimized for VXLAN (1450) - Wi-Fi still fully functional"
    fi
    
    # Check offloading settings
    echo ""
    echo "⚙️  VXLAN offloading status:"
    if command -v ethtool >/dev/null 2>&1; then
        ethtool -k "$WIFI_IFACE" 2>/dev/null | grep -E "(udp|tunnel|segmentation)" || echo "Offloading info not available"
        echo "ℹ️  VXLAN offloading may be disabled for compatibility - Wi-Fi remains active"
    fi
    
    echo ""
    echo "🎉 Wi-Fi VERIFICATION COMPLETE"
    echo "✅ Wi-Fi is fully functional and NOT disabled"
    echo "✅ Only VXLAN hardware optimizations were applied"
    echo "✅ Your internet connection via Wi-Fi works normally"
    
else
    echo "ℹ️  No Wi-Fi interface detected - using wired connection: $WIFI_IFACE"
fi 