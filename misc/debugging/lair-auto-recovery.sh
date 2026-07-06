#!/bin/bash

echo "=== AUTOMATED RECOVERY PROCEDURES ==="
echo "Timestamp: $(date)"
echo

# Function to restart failed pods
restart_failed_pods() {
    echo "Checking for failed pods..."
    FAILED_PODS=$(kubectl get pods -n lair --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}')
    
    if [ ! -z "$FAILED_PODS" ]; then
        echo "Found failed pods: $FAILED_PODS"
        for pod in $FAILED_PODS; do
            echo "Restarting pod: $pod"
            kubectl delete pod "$pod" -n lair
        done
    else
        echo "No failed pods found"
    fi
}

# Function to restart ingress controller
restart_ingress() {
    echo "Restarting ingress controller..."
    kubectl rollout restart deployment/ingress-nginx-controller -n ingress-nginx
    kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=300s
}

# Function to clear DNS cache
clear_dns_cache() {
    echo "Clearing DNS cache..."
    kubectl delete pods -n kube-system -l k8s-app=kube-dns
}

# Main recovery logic
echo "Starting automated recovery..."

# Check cluster connectivity
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "ERROR: Cannot connect to cluster. Manual intervention required."
    exit 1
fi

# Restart failed pods
restart_failed_pods

# Check ingress status
INGRESS_READY=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}')
if [ "$INGRESS_READY" != "True" ]; then
    echo "Ingress controller not ready, restarting..."
    restart_ingress
fi

# Check DNS resolution
if ! kubectl exec -n lair deployment/lair-openwebui -- nslookup kubernetes.default > /dev/null 2>&1; then
    echo "DNS resolution issues detected, clearing DNS cache..."
    clear_dns_cache
fi

echo "Automated recovery complete. Waiting for stabilization..."
sleep 30

# Final status check
echo "=== POST-RECOVERY STATUS ==="
kubectl get pods -n lair
kubectl get services -n lair
kubectl get ingress -n lair

echo "Recovery procedures completed at $(date)"