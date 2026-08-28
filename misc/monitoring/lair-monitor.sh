#!/bin/bash

echo "=== LAIR SYSTEM MONITORING REPORT ==="
echo "Generated: $(date)"
echo

echo "=== CLUSTER STATUS ==="
kubectl cluster-info --request-timeout=10s
echo

echo "=== NODE STATUS ==="
kubectl get nodes -o wide
echo

echo "=== RESOURCE USAGE ==="
kubectl top nodes 2>/dev/null || echo "Metrics server not available"
echo

echo "=== LAIR PODS STATUS ==="
kubectl get pods -n lair -o wide
echo

echo "=== LAIR SERVICES ==="
kubectl get services -n lair
echo

echo "=== INGRESS STATUS ==="
kubectl get ingress -n lair
echo

echo "=== PERSISTENT VOLUMES ==="
kubectl get pvc -n lair
echo

echo "=== RECENT EVENTS ==="
kubectl get events -n lair --sort-by='.lastTimestamp' | tail -10
echo

echo "=== STORAGE USAGE ==="
df -h | grep -E "(Filesystem|/var|/mnt)"
echo

echo "=== MEMORY USAGE ==="
free -h
echo

echo "=== LOAD AVERAGE ==="
uptime
echo

echo "Report completed at $(date)"