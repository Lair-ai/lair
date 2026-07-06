#!/bin/bash

echo "=== STORAGE DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# System storage
echo "=== System Storage ==="
df -h
echo

# Kubernetes storage
echo "=== Persistent Volumes ==="
kubectl get pv -o wide
echo

echo "=== Persistent Volume Claims ==="
kubectl get pvc -A -o wide
echo

echo "=== Storage Classes ==="
kubectl get storageclass -o wide
echo

# Storage-related events
echo "=== Storage-Related Events ==="
kubectl get events -A | grep -i "storage\|volume\|pvc\|pv\|mount"
echo

# Longhorn status (if available)
echo "=== Longhorn Status ==="
kubectl get volumes.longhorn.io -n longhorn-system 2>/dev/null || echo "Longhorn not available"
echo

# Pod storage usage
echo "=== Pod Storage Usage ==="
for pod in $(kubectl get pods -n lair -o jsonpath='{.items[*].metadata.name}'); do
    echo "Pod: $pod"
    kubectl exec -n lair "$pod" -- df -h 2>/dev/null | grep -E "(Filesystem|/app|/data|/var)" || echo "  Cannot access storage info"
    echo
done