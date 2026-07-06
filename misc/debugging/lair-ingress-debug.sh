#!/bin/bash

echo "=== INGRESS DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# Ingress controller status
echo "=== Ingress Controller Status ==="
kubectl get pods -n ingress-nginx -o wide
echo

# Ingress configuration
echo "=== Ingress Configuration ==="
kubectl get ingress -n lair -o yaml
echo

# Ingress controller logs
echo "=== Recent Ingress Controller Logs ==="
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=20
echo

# Load balancer status
echo "=== Load Balancer Status ==="
kubectl get services -n ingress-nginx -o wide
echo

# MetalLB status (if available)
echo "=== MetalLB Status ==="
kubectl get pods -n metallb-system 2>/dev/null || echo "MetalLB not available"
kubectl get configmap config -n metallb-system -o yaml 2>/dev/null || echo "MetalLB config not available"
echo

# Certificate status
echo "=== Certificate Status ==="
kubectl get certificates -n lair 2>/dev/null || echo "No certificates found"
kubectl get secrets -n lair | grep tls || echo "No TLS secrets found"
