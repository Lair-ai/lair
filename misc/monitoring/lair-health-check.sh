#!/bin/bash

HEALTH_STATUS="HEALTHY"
ISSUES=()

# Check cluster connectivity
if ! kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; then
    HEALTH_STATUS="CRITICAL"
    ISSUES+=("Cluster connectivity failed")
fi

# Check node status
NOTREADY_NODES=$(kubectl get nodes --no-headers | grep -v Ready | wc -l)
if [ $NOTREADY_NODES -gt 0 ]; then
    HEALTH_STATUS="WARNING"
    ISSUES+=("$NOTREADY_NODES nodes not ready")
fi

# Check Lair pods
FAILED_PODS=$(kubectl get pods -n lair --no-headers | grep -v Running | grep -v Completed | wc -l)
if [ $FAILED_PODS -gt 0 ]; then
    HEALTH_STATUS="CRITICAL"
    ISSUES+=("$FAILED_PODS Lair pods not running")
fi

# Check PVC status
PENDING_PVCS=$(kubectl get pvc -n lair --no-headers | grep Pending | wc -l)
if [ $PENDING_PVCS -gt 0 ]; then
    HEALTH_STATUS="WARNING"
    ISSUES+=("$PENDING_PVCS PVCs pending")
fi

# Check disk usage
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $DISK_USAGE -gt 90 ]; then
    HEALTH_STATUS="CRITICAL"
    ISSUES+=("Disk usage: ${DISK_USAGE}%")
elif [ $DISK_USAGE -gt 80 ]; then
    HEALTH_STATUS="WARNING"
    ISSUES+=("Disk usage: ${DISK_USAGE}%")
fi

# Check memory usage
MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
if [ $MEMORY_USAGE -gt 90 ]; then
    HEALTH_STATUS="WARNING"
    ISSUES+=("Memory usage: ${MEMORY_USAGE}%")
fi

# Output results
echo "HEALTH_STATUS: $HEALTH_STATUS"
if [ ${#ISSUES[@]} -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${ISSUES[@]}"
fi

# Exit with appropriate code
case $HEALTH_STATUS in
    "HEALTHY") exit 0 ;;
    "WARNING") exit 1 ;;
    "CRITICAL") exit 2 ;;
esac