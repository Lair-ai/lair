#!/bin/bash

echo "=== OPENWEBUI DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# Pod status
echo "=== OpenWebUI Pod Status ==="
kubectl get pods -n lair -l app=openwebui -o wide
kubectl describe pods -n lair -l app=openwebui
echo

# Service connectivity
echo "=== Service Connectivity Tests ==="
echo "Testing Ollama connectivity:"
kubectl exec -n lair deployment/lair-openwebui -- curl -s -o /dev/null -w "HTTP Status: %{http_code}, Time: %{time_total}s\n" lair-ollama:11434/api/tags 2>/dev/null || echo "Failed to connect to Ollama"

echo "Testing Tika connectivity:"
kubectl exec -n lair deployment/lair-openwebui -- curl -s -o /dev/null -w "HTTP Status: %{http_code}, Time: %{time_total}s\n" lair-tika:9998 2>/dev/null || echo "Failed to connect to Tika"

echo "Testing PostgreSQL connectivity:"
kubectl exec -n lair deployment/lair-openwebui -- nc -z lair-postgresql 5432 && echo "PostgreSQL: Connected" || echo "PostgreSQL: Connection failed"
echo

# Application logs analysis
echo "=== Recent Application Logs ==="
kubectl logs -n lair deployment/lair-openwebui --tail=50 | grep -E "(ERROR|WARN|INFO|startup|ready)"
echo

# Configuration check
echo "=== Configuration Check ==="
kubectl get configmap -n lair | grep openwebui || echo "No OpenWebUI ConfigMap found"
kubectl get secret -n lair | grep openwebui || echo "No OpenWebUI secrets found"
echo

# Resource usage
echo "=== Resource Usage ==="
kubectl top pod -n lair -l app=openwebui 2>/dev/null || echo "Metrics not available"
echo

# Storage check
echo "=== Storage Check ==="
kubectl exec -n lair deployment/lair-openwebui -- df -h /app/backend/data 2>/dev/null || echo "Cannot access storage"
kubectl exec -n lair deployment/lair-openwebui -- ls -la /app/backend/data 2>/dev/null | head -10 || echo "Cannot list storage contents"