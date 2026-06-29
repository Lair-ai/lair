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
This script collects full logs from all Lair components and cluster events into a single directory for deep analysis or for sharing with support.
```bash
# Run comprehensive log collection script
./misc/debugging/lair-debug-logs.sh
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
This tool pulls logs from OpenWebUI, Ollama, N8N, and Ingress along with cluster events for a specific time range to correlate failures across multiple components.
```bash
# Run log correlation script
./misc/debugging/lair-log-correlation.sh
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
This script analyzes system memory, node memory pressure, and pod memory usage, identifying OOMKilled pods and comparing actual usage against configured limits.
```bash
# Run memory usage analysis script
./misc/debugging/lair-memory-debug.sh
```

#### **CPU Debugging**
This script checks system CPU architecture, node CPU pressure, and pod CPU usage to detect CPU throttling and compare current usage against resource limits.
```bash
# Run CPU usage analysis script
./misc/debugging/lair-cpu-debug.sh
```

### 💾 **Storage Debugging**

#### **Storage Analysis Tools**
This script inspects system storage, Kubernetes Persistent Volumes, Storage Classes, Longhorn status, and pod-level storage usage to diagnose disk space or mount issues.
```bash
# Run storage debugging script
./misc/debugging/lair-storage-debug.sh
```

---

## 🌐 Network Debugging

### 🔍 **Network Connectivity Analysis**

#### **Comprehensive Network Debug**
This script tests system network interfaces, Kubernetes services, endpoints, DNS resolution, and verifies connectivity between key Lair services (e.g., OpenWebUI to Ollama).
```bash
# Run network debugging script
./misc/debugging/lair-network-debug.sh
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
This tool checks the status of the ingress controller, LoadBalancer (MetalLB), TLS certificates, and retrieves recent ingress logs to debug routing and access issues.
```bash
# Run ingress debugging script
./misc/debugging/lair-ingress-debug.sh
```

---

## 🔍 Application-Specific Debugging

### 🤖 **OpenWebUI Debugging**

#### **OpenWebUI Debug Script**
This script specifically targets OpenWebUI, checking its pod status, connectivity to backend services (Ollama, Tika, PostgreSQL), recent application logs, and storage access.
```bash
# Run OpenWebUI debugging script
./misc/debugging/lair-openwebui-debug.sh
```

### 🧠 **Ollama Debugging**

#### **Ollama Debug Script**
This tool focuses on Ollama, checking pod health, API responsiveness, loaded models, GPU availability (via nvidia-smi), and storage access for downloaded models.
```bash
# Run Ollama debugging script
./misc/debugging/lair-ollama-debug.sh
```

---

## 🚨 Emergency Debugging Procedures

### 🔧 **Cluster Emergency Debug**

#### **Rapid Cluster Assessment**
This emergency script performs a rapid health check of the entire cluster, identifying critical failures in nodes, core components, and Lair services during severe outages.
```bash
# Run emergency cluster debug script
./misc/debugging/lair-emergency-debug.sh
```

### 🔄 **Recovery Procedures**

#### **Automated Recovery Script**
This script attempts automated remediation by checking cluster connectivity, restarting failed pods, restarting the ingress controller, and clearing the DNS cache if needed.
```bash
# Run automated recovery script
./misc/debugging/lair-auto-recovery.sh
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
This script provides an interactive, step-by-step checklist of standard debugging commands to systematically guide you through diagnosing complex cluster issues.
```bash
# Run debugging checklist
./misc/debugging/lair-debug-checklist.sh
```

### 🚨 **When to Escalate**
- **Cluster-wide failures**: Multiple nodes down, control plane issues
- **Data corruption**: Database or storage corruption detected
- **Security incidents**: Unauthorized access or suspicious activity
- **Hardware failures**: Physical hardware problems
- **Network infrastructure**: ISP or datacenter network issues

---

**🎯 Ready to master debugging?** Continue with [Advanced Configuration](../configuration/advanced-configuration.md) or explore [Component-Specific Guides](../components/services-overview.md)!
