#!/bin/bash

echo "=== MEMORY DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# System memory
echo "=== System Memory ==="
free -h
echo

# Node memory pressure
echo "=== Node Memory Pressure ==="
kubectl describe nodes | grep -A 5 "MemoryPressure"
echo

# Pod memory usage
echo "=== Pod Memory Usage ==="
kubectl top pods -n lair --sort-by=memory
echo

# Memory-related events
echo "=== Memory-Related Events ==="
kubectl get events -A | grep -i "memory\|oom\|evict"
echo

# Check for OOMKilled pods
echo "=== OOMKilled Pods ==="
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason == "OOMKilled") | "\(.metadata.namespace)/\(.metadata.name)"'
echo

# Memory limits vs usage
echo "=== Memory Limits vs Usage ==="
for pod in $(kubectl get pods -n lair -o jsonpath='{.items[*].metadata.name}'); do
    echo "Pod: $pod"
    kubectl get pod "$pod" -n lair -o json | jq -r '.spec.containers[] | "  Container: \(.name), Memory Limit: \(.resources.limits.memory // "none"), Memory Request: \(.resources.requests.memory // "none")"'
    kubectl top pod "$pod" -n lair --containers 2>/dev/null | tail -n +2 | awk '{print "  Current Usage: " $3}'
    echo
done