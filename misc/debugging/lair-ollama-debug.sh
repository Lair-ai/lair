#!/bin/bash

echo "=== OLLAMA DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# Pod status
echo "=== Ollama Pod Status ==="
kubectl get pods -n lair -l app=ollama -o wide
kubectl describe pods -n lair -l app=ollama
echo

# API health check
echo "=== API Health Check ==="
kubectl exec -n lair statefulset/lair-ollama -- curl -s lair-ollama:11434/api/tags 2>/dev/null | jq '.' || echo "API not responding or invalid JSON"
echo

# Model status
echo "=== Model Status ==="
kubectl exec -n lair statefulset/lair-ollama -- ollama list 2>/dev/null || echo "Cannot list models"
echo

# GPU status (if available)
echo "=== GPU Status ==="
kubectl exec -n lair statefulset/lair-ollama -- nvidia-smi 2>/dev/null || echo "GPU not available or nvidia-smi not found"
echo

# Resource usage
echo "=== Resource Usage ==="
kubectl top pod -n lair -l app=ollama 2>/dev/null || echo "Metrics not available"
echo

# Storage check
echo "=== Storage Check ==="
kubectl exec -n lair statefulset/lair-ollama -- df -h /root/.ollama 2>/dev/null || echo "Cannot access Ollama storage"
kubectl exec -n lair statefulset/lair-ollama -- ls -la /root/.ollama/models 2>/dev/null | head -10 || echo "Cannot list models directory"
echo

# Application logs analysis
echo "=== Recent Application Logs ==="
kubectl logs -n lair statefulset/lair-ollama --tail=50 | grep -E "(ERROR|WARN|INFO|model|load|GPU)"