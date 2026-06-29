# 🔍 Debugging Tools & Techniques

> **Comprehensive guide to debugging tools, techniques, and diagnostic procedures for Lair deployments**

This guide provides advanced debugging capabilities for diagnosing complex issues in Lair deployments, from cluster-level problems to application-specific debugging.

---

## 🎯 Overview

Effective debugging requires the right tools and systematic approaches. This guide covers both built-in Kubernetes debugging capabilities and specialized tools for different types of issues.

### 🏗️ **Debugging Layers**
```
┌─────────────────────────────────────────────────────────────────┐
│                    🔍 DEBUGGING SCOPE                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Application   │  │   Kubernetes    │  │ Infrastructure  │  │
│  │   Debugging     │  │   Debugging     │  │   Debugging     │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🛠️ DEBUGGING TOOLS                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │    kubectl      │  │      k9s        │  │   Specialized   │  │
│  │   (Native)      │  │    (TUI)        │  │    Tools        │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                  📊 DIAGNOSTIC METHODS                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Log Analysis   │  │ Resource Trace  │  │ Network Debug   │  │
│  │   (Logs/Events) │  │ (CPU/Memory)    │  │ (Connectivity)  │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔧 Essential Debugging Tools

### 📱 **kubectl - Native Kubernetes Debugging**

#### **Basic Diagnostic Commands**
```bash
# Cluster-wide overview
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A --field-selector=status.phase!=Running

# Component status
kubectl get componentstatuses
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# Resource usage
kubectl top nodes
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory
```

#### **Advanced kubectl Debugging**
```bash
# Detailed resource inspection
kubectl describe node <node-name>
kubectl describe pod <pod-name> -n <namespace>

# Resource definitions and status
kubectl get pod <pod-name> -n <namespace> -o yaml
kubectl get pod <pod-name> -n <namespace> -o json | jq '.status'

# Events and logs
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
kubectl logs <pod-name> -n <namespace> --previous  # Previous container logs
kubectl logs <pod-name> -n <namespace> -c <container-name>  # Multi-container pods
```

#### **Interactive Debugging**
```bash
# Execute commands in running pods
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Port forwarding for local access
kubectl port-forward -n <namespace> <pod-name> 8080:8080
kubectl port-forward -n <namespace> service/<service-name> 8080:80

# Copy files to/from pods
kubectl cp <local-file> <namespace>/<pod-name>:<remote-path>
kubectl cp <namespace>/<pod-name>:<remote-path> <local-file>
```

### 🖥️ **k9s - Terminal UI for Kubernetes**

#### **Installation and Basic Usage**
```bash
# Install k9s
curl -sS https://webinstall.dev/k9s | bash

# Start k9s
k9s

# Essential k9s shortcuts:
# :pods           - View pods
# :svc            - View services
# :ing            - View ingress
# :pvc            - View persistent volume claims
# :events         - View events
# :logs           - View logs
# Ctrl+A          - Show all namespaces
# /               - Filter resources
# d               - Describe resource
# l               - View logs
# e               - Edit resource
# Ctrl+D          - Delete resource
```

#### **Advanced k9s Features**
```bash
# k9s configuration (~/.config/k9s/config.yml)
k9s:
  refreshRate: 2
  maxConnRetry: 5
  readOnly: false
  noExitOnCtrlC: false
  ui:
    enableMouse: false
    headless: false
    logoless: false
    crumbsless: false
  skipLatestRevCheck: false
  disablePodCounting: false
  shellPod:
    image: busybox:1.35.0
    namespace: default
    limits:
      cpu: 100m
      memory: 100Mi
```

### 🔍 **Specialized Debugging Tools**

#### **Debug Containers and Utilities**
```bash
# Create debug pod with network tools
kubectl run debug-pod --image=nicolaka/netshoot --rm -it --restart=Never

# Debug pod with system tools
kubectl run debug-pod --image=busybox --rm -it --restart=Never

# Debug with privileged access
kubectl run debug-pod --image=nicolaka/netshoot --rm -it --restart=Never --overrides='
{
  "spec": {
    "hostNetwork": true,
    "hostPID": true,
    "containers": [
      {
        "name": "debug-pod",
        "image": "nicolaka/netshoot",
        "securityContext": {
          "privileged": true
        }
      }
    ]
  }
}'
```

#### **Network Debugging Tools**
```bash
# Network connectivity testing
kubectl run network-test --image=busybox --rm -it -- ping google.com
kubectl run network-test --image=busybox --rm -it -- nslookup kubernetes.default

# DNS debugging
kubectl run dns-debug --image=busybox --rm -it -- nslookup lair-ollama.lair.svc.cluster.local

# Service connectivity testing
kubectl exec -n lair deployment/lair-openwebui -- curl -v lair-ollama:11434/api/tags
```

---

## 🔍 Log Analysis and Debugging

### 📝 **Centralized Log Collection**

#### **Comprehensive Log Gathering Script**
```bash
# Create comprehensive log collection script
cat > /usr/local/bin/lair-debug-logs.sh << 'EOF'

/misc/debugging/lair-debug-logs.sh

chmod +x /usr/local/bin/lair-debug-logs.sh
```

#### **Real-time Log Monitoring**
```bash
# Monitor all Lair logs in real-time
kubectl logs -n lair -f -l app.kubernetes.io/instance=lair

# Monitor specific application logs
kubectl logs -n lair -f deployment/lair-openwebui
kubectl logs -n lair -f statefulset/lair-ollama
kubectl logs -n lair -f deployment/lair-n8n

# Monitor with timestamps
kubectl logs -n lair -f deployment/lair-openwebui --timestamps=true

# Monitor multiple pods
kubectl logs -n lair -f -l app=openwebui --max-log-requests=10
```

### 🔍 **Log Analysis Techniques**

#### **Error Pattern Detection**
```bash
# Search for common error patterns
kubectl logs -n lair deployment/lair-openwebui | grep -i "error\|fail\|exception\|panic"

# Search for specific error types
kubectl logs -n lair deployment/lair-openwebui | grep -E "(HTTP [45][0-9][0-9]|timeout|connection.*refused)"

# Search with context (lines before/after)
kubectl logs -n lair deployment/lair-openwebui | grep -B 5 -A 5 "error"

# Count error occurrences
kubectl logs -n lair deployment/lair-openwebui | grep -c "error"
```

#### **Performance Analysis from Logs**
```bash
# Analyze response times
kubectl logs -n lair deployment/lair-openwebui | grep -E "response.*time|duration|latency" | tail -20

# Monitor memory usage patterns
kubectl logs -n lair statefulset/lair-ollama | grep -i "memory\|oom\|allocation"

# Track startup times
kubectl logs -n lair deployment/lair-openwebui | grep -E "started|ready|listening"
```

#### **Log Correlation Analysis**
```bash
# Create log correlation script
cat > /usr/local/bin/lair-log-correlation.sh << 'EOF'
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

echo "=== Events During Time Range ==="
kubectl get events -n lair --field-selector="firstTimestamp>=$TIMESTAMP_START,firstTimestamp<=$TIMESTAMP_END" --sort-by='.firstTimestamp'
EOF

chmod +x /usr/local/bin/lair-log-correlation.sh
```

---

## 🔧 Resource Debugging

### 📊 **Resource Usage Analysis**

#### **Detailed Resource Inspection**
```bash
# Node resource analysis
kubectl describe nodes | grep -A 10 "Allocated resources"

# Pod resource analysis
kubectl get pods -n lair -o custom-columns=NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,CPU_LIM:.spec.containers[0].resources.limits.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory,MEM_LIM:.spec.containers[0].resources.limits.memory

# Resource utilization vs allocation
kubectl top pods -n lair --containers | while read line; do
    echo "$line"
    # Add logic to compare with requests/limits
done
```

#### **Memory Debugging**
```bash
# Memory usage analysis script
cat > /usr/local/bin/lair-memory-debug.sh << 'EOF'
#!/bin/bash

echo "=== MEMORY DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# System memory
echo "=== System Memory ==="
free -h
echo

# Node memory pressure
echo "=== Node Memory Pressure ==="
kubectl describe nodes | grep -A 5 "MemoryPressure"
echo

# Pod memory usage
echo "=== Pod Memory Usage ==="
kubectl top pods -n lair --sort-by=memory
echo

# Memory-related events
echo "=== Memory-Related Events ==="
kubectl get events -A | grep -i "memory\|oom\|evict"
echo

# Check for OOMKilled pods
echo "=== OOMKilled Pods ==="
kubectl get pods -A -o json | jq -r '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason == "OOMKilled") | "\(.metadata.namespace)/\(.metadata.name)"'
echo

# Memory limits vs usage
echo "=== Memory Limits vs Usage ==="
for pod in $(kubectl get pods -n lair -o jsonpath='{.items[*].metadata.name}'); do
    echo "Pod: $pod"
    kubectl get pod "$pod" -n lair -o json | jq -r '.spec.containers[] | "  Container: \(.name), Memory Limit: \(.resources.limits.memory // "none"), Memory Request: \(.resources.requests.memory // "none")"'
    kubectl top pod "$pod" -n lair --containers 2>/dev/null | tail -n +2 | awk '{print "  Current Usage: " $3}'
    echo
done
EOF

chmod +x /usr/local/bin/lair-memory-debug.sh
```

#### **CPU Debugging**
```bash
# CPU usage analysis script
cat > /usr/local/bin/lair-cpu-debug.sh << 'EOF'
#!/bin/bash

echo "=== CPU DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# System CPU
echo "=== System CPU ==="
lscpu | grep -E "CPU\(s\)|Model name|Architecture"
uptime
echo

# Node CPU pressure
echo "=== Node CPU Pressure ==="
kubectl describe nodes | grep -A 5 "PIDPressure\|DiskPressure"
echo

# Pod CPU usage
echo "=== Pod CPU Usage ==="
kubectl top pods -n lair --sort-by=cpu
echo

# CPU throttling detection
echo "=== CPU Throttling Analysis ==="
for pod in $(kubectl get pods -n lair -o jsonpath='{.items[*].metadata.name}'); do
    echo "Pod: $pod"
    kubectl get pod "$pod" -n lair -o json | jq -r '.spec.containers[] | "  Container: \(.name), CPU Limit: \(.resources.limits.cpu // "none"), CPU Request: \(.resources.requests.cpu // "none")"'
    kubectl top pod "$pod" -n lair --containers 2>/dev/null | tail -n +2 | awk '{print "  Current Usage: " $2}'
    echo
done
EOF

chmod +x /usr/local/bin/lair-cpu-debug.sh
```

### 💾 **Storage Debugging**

#### **Storage Analysis Tools**
```bash
# Storage debugging script
cat > /usr/local/bin/lair-storage-debug.sh << 'EOF'
#!/bin/bash

echo "=== STORAGE DEBUGGING ANALYSIS ==="
echo "Timestamp: $(date)"
echo

# System storage
echo "=== System Storage ==="
df -h
echo

# Kubernetes storage
echo "=== Persistent Volumes ==="
kubectl get pv -o wide
echo

echo "=== Persistent Volume Claims ==="
kubectl get pvc -A -o wide
echo

echo "=== Storage Classes ==="
kubectl get storageclass -o wide
echo

# Storage-related events
echo "=== Storage-Related Events ==="
kubectl get events -A | grep -i "storage\|volume\|pvc\|pv\|mount"
echo

# Longhorn status (if available)
echo "=== Longhorn Status ==="
kubectl get volumes.longhorn.io -n longhorn-system 2>/dev/null || echo "Longhorn not available"
echo

# Pod storage usage
echo "=== Pod Storage Usage ==="
for pod in $(kubectl get pods -n lair -o jsonpath='{.items[*].metadata.name}'); do
    echo "Pod: $pod"
    kubectl exec -n lair "$pod" -- df -h 2>/dev/null | grep -E "(Filesystem|/app|/data|/var)" || echo "  Cannot access storage info"
    echo
done
EOF

chmod +x /usr/local/bin/lair-storage-debug.sh
```

---

## 🌐 Network Debugging

### 🔍 **Network Connectivity Analysis**

#### **Comprehensive Network Debug**
```bash
# Network debugging script
cat > /usr/local/bin/lair-network-debug.sh << 'EOF'
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
EOF

chmod +x /usr/local/bin/lair-network-debug.sh
```

#### **Advanced Network Diagnostics**
```bash
# Create network diagnostic pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: network-debug
  namespace: lair
spec:
  containers:
  - name: network-debug
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
  restartPolicy: Never
EOF

# Wait for pod to be ready
kubectl wait --for=condition=Ready pod/network-debug -n lair --timeout=60s

# Network diagnostics from inside cluster
kubectl exec -n lair network-debug -- ping -c 3 lair-ollama.lair.svc.cluster.local
kubectl exec -n lair network-debug -- nslookup lair-ollama.lair.svc.cluster.local
kubectl exec -n lair network-debug -- curl -v lair-ollama:11434/api/tags
kubectl exec -n lair network-debug -- traceroute lair-ollama.lair.svc.cluster.local

# Cleanup
kubectl delete pod network-debug -n lair
```

### 🔧 **Ingress and Load Balancer Debugging**

#### **Ingress Debugging**
```bash
# Ingress debugging script
cat > /usr/local/bin/lair-ingress-debug.sh << 'EOF'
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
EOF

chmod +x /usr/local/bin/lair-ingress-debug.sh
```

---

## 🔍 Application-Specific Debugging

### 🤖 **OpenWebUI Debugging**

#### **OpenWebUI Debug Script**
```bash
# OpenWebUI debugging script
cat > /usr/local/bin/lair-openwebui-debug.sh << 'EOF'
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
EOF

chmod +x /usr/local/bin/lair-openwebui-debug.sh
```

### 🧠 **Ollama Debugging**

#### **Ollama Debug Script**
```bash
# Ollama debugging script
cat > /usr/local/bin/lair-ollama-debug.sh << 'EOF'
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
EOF

chmod +x /usr/local/bin/lair-ollama-debug.sh
```

---

## 🚨 Emergency Debugging Procedures

### 🔧 **Cluster Emergency Debug**

#### **Rapid Cluster Assessment**
```bash
# Emergency cluster debug script

misc/debugging/lair-emergency-debug.sh
```

### 🔄 **Recovery Procedures**

#### **Automated Recovery Script**
```bash
# Automated recovery script
cat > /usr/local/bin/lair-auto-recovery.sh << 'EOF'
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
EOF

chmod +x /usr/local/bin/lair-auto-recovery.sh
```

---

## 🎯 Best Practices for Debugging

### 🔍 **Systematic Debugging Approach**
1. **Start with overview**: Use cluster-wide commands first
2. **Narrow down scope**: Focus on specific namespaces/components
3. **Check dependencies**: Verify prerequisite services are running
4. **Analyze logs**: Look for error patterns and timing
5. **Test connectivity**: Verify network paths between components
6. **Resource analysis**: Check for resource constraints
7. **Document findings**: Keep track of what you've checked

### 📊 **Debugging Checklist**
```bash
# Create debugging checklist
cat > /usr/local/bin/lair-debug-checklist.sh << 'EOF'
#!/bin/bash

echo "=== LAIR DEBUGGING CHECKLIST ==="
echo "Use this checklist to systematically debug issues"
echo

echo "□ 1. Cluster connectivity (kubectl cluster-info)"
echo "□ 2. Node status (kubectl get nodes)"
echo "□ 3. Pod status (kubectl get pods -n lair)"
echo "□ 4. Service status (kubectl get services -n lair)"
echo "□ 5. Ingress status (kubectl get ingress -n lair)"
echo "□ 6. Recent events (kubectl get events -n lair)"
echo "□ 7. Resource usage (kubectl top pods -n lair)"
echo "□ 8. Application logs (kubectl logs -n lair <pod-name>)"
echo "□ 9. Service connectivity (curl tests between services)"
echo "□ 10. DNS resolution (nslookup tests)"
echo "□ 11. Storage status (kubectl get pvc -n lair)"
echo "□ 12. Certificate status (kubectl get certificates -n lair)"
echo "□ 13. Network policies (kubectl get networkpolicies -n lair)"
echo "□ 14. External connectivity (ping, curl external services)"
echo "□ 15. System resources (df -h, free -h, uptime)"
echo

echo "Run specific debug scripts:"
echo "- Emergency debug: /misc/debugging/lair-emergency-debug.sh"
echo "- Full debug logs: /misc/debugging/lair-debug-logs.sh"
echo "- Network debug: /usr/local/bin/lair-network-debug.sh"
echo "- OpenWebUI debug: /usr/local/bin/lair-openwebui-debug.sh"
echo "- Ollama debug: /usr/local/bin/lair-ollama-debug.sh"
EOF

chmod +x /usr/local/bin/lair-debug-checklist.sh
```

### 🚨 **When to Escalate**
- **Cluster-wide failures**: Multiple nodes down, control plane issues
- **Data corruption**: Database or storage corruption detected
- **Security incidents**: Unauthorized access or suspicious activity
- **Hardware failures**: Physical hardware problems
- **Network infrastructure**: ISP or datacenter network issues

---

**🎯 Ready to master debugging?** Continue with [Advanced Configuration](../../configuration/advanced/README.md) or explore [Component-Specific Guides](../../components/README.md)!
