#!/bin/bash

echo "=== CPU DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# System CPU
echo "=== System CPU ==="
lscpu | grep -E "CPU\(s\)|Model name|Architecture"
uptime
echo

# Node CPU pressure
echo "=== Node CPU Pressure ==="
kubectl describe nodes | grep -A 5 "PIDPressure\|DiskPressure"
echo

# Pod CPU usage
echo "=== Pod CPU Usage ==="
kubectl top pods -n lair --sort-by=cpu
echo

# CPU throttling detection
echo "=== CPU Throttling Analysis ==="
for pod in $(kubectl get pods -n lair -o jsonpath='{.items[*].metadata.name}'); do
    echo "Pod: $pod"
    kubectl get pod "$pod" -n lair -o json | jq -r '.spec.containers[] | "  Container: \(.name), CPU Limit: \(.resources.limits.cpu // "none"), CPU Request: \(.resources.requests.cpu // "none")"'
    kubectl top pod "$pod" -n lair --containers 2>/dev/null | tail -n +2 | awk '{print "  Current Usage: " $2}'
    echo
done