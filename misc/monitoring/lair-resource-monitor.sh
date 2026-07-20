#!/bin/bash

LOG_FILE="/var/log/lair-resources.log"
INTERVAL=60  # seconds

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # System resources
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    # Kubernetes resources
    if kubectl top nodes >/dev/null 2>&1; then
        K8S_CPU=$(kubectl top nodes --no-headers | awk '{sum+=$3} END {print sum}')
        K8S_MEMORY=$(kubectl top nodes --no-headers | awk '{sum+=$5} END {print sum}')
    else
        K8S_CPU="N/A"
        K8S_MEMORY="N/A"
    fi
    
    # Log metrics
    echo "$TIMESTAMP,CPU:$CPU_USAGE,Memory:$MEMORY_USAGE,Disk:$DISK_USAGE,Load:$LOAD_AVG,K8s_CPU:$K8S_CPU,K8s_Memory:$K8S_MEMORY" >> "$LOG_FILE"
    
    sleep $INTERVAL
done