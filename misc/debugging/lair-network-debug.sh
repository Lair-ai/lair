#!/bin/bash

echo "=== NETWORK DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# System network
echo "=== System Network Interfaces ==="
ip addr show
echo

echo "=== System Network Routes ==="
ip route show
echo

# Kubernetes network
echo "=== Kubernetes Services ==="
kubectl get services -A -o wide
echo

echo "=== Kubernetes Endpoints ==="
kubectl get endpoints -A
echo

echo "=== Kubernetes Ingress ==="
kubectl get ingress -A -o wide
echo

# DNS testing
echo "=== DNS Resolution Testing ==="
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default 2>/dev/null || echo "DNS test failed"
kubectl run dns-test --image=busybox --rm -it --restart=Never -- nslookup lair-ollama.lair.svc.cluster.local 2>/dev/null || echo "Service DNS test failed"
echo

# Connectivity testing
echo "=== Service Connectivity Testing ==="
kubectl exec -n lair deployment/lair-openwebui -- curl -s -o /dev/null -w "%{http_code}" lair-ollama:11434/api/tags 2>/dev/null || echo "Ollama connectivity failed"
kubectl exec -n lair deployment/lair-openwebui -- curl -s -o /dev/null -w "%{http_code}" lair-tika:9998 2>/dev/null || echo "Tika connectivity failed"
echo

# Network policies
echo "=== Network Policies ==="
kubectl get networkpolicies -A
echo

# CNI status
echo "=== CNI Status ==="
kubectl get pods -n kube-system | grep -E "(calico|flannel|cni)"