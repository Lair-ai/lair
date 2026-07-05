#!/bin/bash

TIMESTAMP_START=${1:-"$(date -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S')"}
TIMESTAMP_END=${2:-"$(date '+%Y-%m-%dT%H:%M:%S')"}

echo "=== LOG CORRELATION ANALYSIS ==="
echo "Time range: $TIMESTAMP_START to $TIMESTAMP_END"
echo

# Get logs from all components with timestamps
echo "=== OpenWebUI Logs ==="
kubectl logs -n lair deployment/lair-openwebui --since-time="$TIMESTAMP_START" --timestamps | head -20

echo "=== Ollama Logs ==="
kubectl logs -n lair statefulset/lair-ollama --since-time="$TIMESTAMP_START" --timestamps | head -20

echo "=== N8N Logs ==="
kubectl logs -n lair deployment/lair-n8n --since-time="$TIMESTAMP_START" --timestamps | head -20

echo "=== Ingress Logs ==="
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --since-time="$TIMESTAMP_START" --timestamps | grep lair | head -20

