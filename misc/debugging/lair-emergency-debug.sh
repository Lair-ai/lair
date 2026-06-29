#!/bin/bash

echo "=== EMERGENCY CLUSTER DEBUGGING ==="
echo "Timestamp: $(date)"
echo "This script performs rapid assessment of critical cluster issues"
echo

# Critical cluster components
echo "=== CRITICAL COMPONENT STATUS ==="
kubectl get componentstatuses
echo

# Node status
echo "=== NODE STATUS ==="
kubectl get nodes -o wide
kubectl describe nodes | grep -A 5 "Conditions:"
echo

# Critical system pods
echo "=== CRITICAL SYSTEM PODS ==="
kubectl get pods -n kube-system | grep -E "(api-server|etcd|scheduler|controller)"
kubectl get pods -n ingress-nginx
kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager not found"
echo

# Lair application status
echo "=== LAIR APPLICATION STATUS ==="
kubectl get pods -n lair -o wide
echo

# Recent critical events
echo "=== RECENT CRITICAL EVENTS ==="
kubectl get events -A --field-selector type=Warning --sort-by='.lastTimestamp' | tail -20
echo

# Resource pressure
echo "=== RESOURCE PRESSURE ==="
kubectl top nodes 2>/dev/null || echo "Metrics server not available"
df -h | grep -E "(Filesystem|/var|/)"
free -h
echo

# Network connectivity
echo "=== BASIC CONNECTIVITY ==="
ping -c 3 8.8.8.8 > /dev/null && echo "Internet: OK" || echo "Internet: FAILED"
kubectl exec -n lair deployment/lair-openwebui -- curl -s -o /dev/null lair-ollama:11434 && echo "Internal services: OK" || echo "Internal services: FAILED"
echo

echo "=== EMERGENCY DEBUG COMPLETE ==="
echo "If issues persist, run full debug collection: /usr/local/bin/lair-debug-logs.sh"