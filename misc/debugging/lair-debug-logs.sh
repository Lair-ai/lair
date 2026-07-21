#!/bin/bash

DEBUG_DIR="/tmp/lair-debug-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$DEBUG_DIR"

echo "Collecting Lair debug information..."
echo "Debug directory: $DEBUG_DIR"

uname -a > "$DEBUG_DIR/system-info.txt" 2>&1
cat /etc/os-release >> "$DEBUG_DIR/system-info.txt" 2>&1
lsb_release -a >> "$DEBUG_DIR/system-info.txt" 2>&1 || true

# Cluster information
echo "=== Collecting cluster information ==="
kubectl cluster-info > "$DEBUG_DIR/cluster-info.txt" 2>&1
kubectl version > "$DEBUG_DIR/version.txt" 2>&1
kubectl get nodes -o wide > "$DEBUG_DIR/nodes.txt" 2>&1
kubectl get componentstatuses > "$DEBUG_DIR/component-status.txt" 2>&1

# Resource information
echo "=== Collecting resource information ==="
kubectl get all -A > "$DEBUG_DIR/all-resources.txt" 2>&1
kubectl get pv > "$DEBUG_DIR/persistent-volumes.txt" 2>&1
kubectl get pvc -A > "$DEBUG_DIR/persistent-volume-claims.txt" 2>&1
kubectl get storageclass > "$DEBUG_DIR/storage-classes.txt" 2>&1
kubectl get ingress -A > "$DEBUG_DIR/ingress.txt" 2>&1

# Events
echo "=== Collecting events ==="
kubectl get events -A --sort-by='.lastTimestamp' > "$DEBUG_DIR/events-all.txt" 2>&1
kubectl get events -n lair --sort-by='.lastTimestamp' > "$DEBUG_DIR/events-lair.txt" 2>&1

# Lair-specific information
echo "=== Collecting Lair application information ==="
kubectl get all -n lair -o wide > "$DEBUG_DIR/lair-resources.txt" 2>&1
kubectl describe pods -n lair > "$DEBUG_DIR/lair-pods-describe.txt" 2>&1
kubectl describe services -n lair > "$DEBUG_DIR/lair-services-describe.txt" 2>&1
kubectl describe ingress -n lair > "$DEBUG_DIR/lair-ingress-describe.txt" 2>&1

# Application logs
echo "=== Collecting application logs ==="
for pod in $(kubectl get pods -n lair -o jsonpath='{.items[*].metadata.name}'); do
    echo "Collecting logs for $pod..."
    kubectl logs -n lair "$pod" --tail=500 > "$DEBUG_DIR/logs-$pod.txt" 2>&1
    kubectl logs -n lair "$pod" --previous --tail=500 > "$DEBUG_DIR/logs-$pod-previous.txt" 2>&1 || true
done

# Infrastructure logs
echo "=== Collecting infrastructure logs ==="
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=500 > "$DEBUG_DIR/logs-ingress.txt" 2>&1
kubectl logs -n longhorn-system daemonset/longhorn-manager --tail=500 > "$DEBUG_DIR/logs-longhorn.txt" 2>&1 || true
kubectl logs -n cert-manager deployment/cert-manager --tail=500 > "$DEBUG_DIR/logs-cert-manager.txt" 2>&1

# System information
echo "=== Collecting system information ==="
df -h > "$DEBUG_DIR/disk-usage.txt" 2>&1
free -h > "$DEBUG_DIR/memory-usage.txt" 2>&1
uptime > "$DEBUG_DIR/uptime.txt" 2>&1
lscpu > "$DEBUG_DIR/cpu-info.txt" 2>&1
lsblk > "$DEBUG_DIR/block-devices.txt" 2>&1

# Network information
echo "=== Collecting network information ==="
ip addr show > "$DEBUG_DIR/network-interfaces.txt" 2>&1
ip route show > "$DEBUG_DIR/network-routes.txt" 2>&1
netstat -tuln > "$DEBUG_DIR/network-ports.txt" 2>&1

# Resource usage
echo "=== Collecting resource usage ==="
kubectl top nodes > "$DEBUG_DIR/resource-nodes.txt" 2>&1 || echo "Metrics server not available" > "$DEBUG_DIR/resource-nodes.txt"
kubectl top pods -A > "$DEBUG_DIR/resource-pods.txt" 2>&1 || echo "Metrics server not available" > "$DEBUG_DIR/resource-pods.txt"

# Create archive
echo "=== Creating debug archive ==="
tar -czf "$DEBUG_DIR.tar.gz" -C "/tmp" "$(basename "$DEBUG_DIR")"
rm -rf "$DEBUG_DIR"

echo "Debug information collected: $DEBUG_DIR.tar.gz"
echo "Please provide this file when seeking support."