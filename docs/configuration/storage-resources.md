# 🧮 Resource Management Guide

> **Complete guide to CPU, memory, and storage resource allocation and optimization in Lair**

This guide covers comprehensive resource management strategies for Lair deployments, from automatic resource detection to manual optimization and platform-specific tuning.

---

## 🎯 Overview

Effective resource management is crucial for optimal Lair performance. The system automatically detects and allocates resources based on available hardware, but understanding and fine-tuning these allocations can significantly improve performance and efficiency.

### 🏗️ **Resource Management Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                   🔍 RESOURCE DETECTION                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   CPU Cores     │  │   Memory Size   │  │ Storage Space   │  │
│  │  (nproc/lscpu)  │  │  (free -h)      │  │   (df -h)       │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                  ⚖️ RESOURCE ALLOCATION                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ System Reserve  │  │ Kubernetes      │  │ Applications    │  │
│  │    (20-30%)     │  │   (10-20%)      │  │   (50-70%)      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                 📊 APPLICATION DISTRIBUTION                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │     Ollama      │  │   OpenWebUI     │  │      N8N        │  │
│  │     (35%)       │  │     (25%)       │  │     (10%)       │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │    ComfyUI      │  │   PostgreSQL    │  │     Others      │  │
│  │     (20%)       │  │      (5%)       │  │     (5%)        │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📊 **Resource Allocation Strategy**

| Component | CPU % | Memory % | Storage Priority | Notes |
|-----------|-------|----------|------------------|-------|
| **System Reserve** | 20% | 20% | - | OS and system processes |
| **Kubernetes** | 10% | 15% | - | K8s control plane and addons |
| **Ollama** | 35% | 35% | High | LLM serving (GPU priority) |
| **OpenWebUI** | 25% | 25% | Medium | Web interface and RAG |
| **ComfyUI** | 20% | 20% | Medium | Image generation (optional) |
| **N8N + Workers** | 10% | 15% | Low | Workflow automation |
| **PostgreSQL** | 5% | 5% | High | Database persistence |
| **Redis** | 3% | 3% | Low | Cache and queues |
| **MinIO** | 7% | 7% | High | Object storage (optional) |

---

## 🔍 Automatic Resource Detection

### 📊 **System Resource Detection**
The Helm chart setup automatically detects system resources during configuration:

```bash
# Resource detection process (from helm-chart/lib/system-detection.sh)
# CPU detection
TOTAL_CPU=$(nproc)
USABLE_CPU=$(echo "$TOTAL_CPU * 0.7" | bc -l)  # 70% for applications

# Memory detection  
TOTAL_MEMORY_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEMORY_GB=$(echo "scale=1; $TOTAL_MEMORY_KB / 1024 / 1024" | bc -l)
USABLE_MEMORY_GB=$(echo "scale=1; $TOTAL_MEMORY_GB * 0.7" | bc -l)  # 70% for applications

# Storage detection
AVAILABLE_STORAGE=$(df / --output=avail | tail -1)
USABLE_STORAGE_GB=$(echo "scale=0; $AVAILABLE_STORAGE / 1024 / 1024 * 0.8" | bc -l)  # 80% usable
```

### 🎛️ **Platform-Specific Detection**

#### **Standard Platform Detection**
```bash
# Standard x86_64 platform
PLATFORM="standard"
GPU_ENABLED=$(lspci | grep -i nvidia >/dev/null && echo "true" || echo "false")
STORAGE_CLASS="longhorn"
CNI="calico"
```

#### **Jetson Platform Detection**
```bash
# NVIDIA Jetson detection
if [ -f /proc/device-tree/model ] && grep -qi jetson /proc/device-tree/model; then
    PLATFORM="jetson"
    GPU_ENABLED="true"  # Tegra GPU always available
    STORAGE_CLASS="hostpath"
    CNI="flannel"
    
    # Jetson-specific memory optimization
    USABLE_MEMORY_GB=$(echo "scale=1; $TOTAL_MEMORY_GB * 0.8" | bc -l)  # 80% for Jetson
fi
```

### ⚙️ **Resource Calculation Logic**

#### **CPU Allocation**
```bash
# CPU allocation calculation
calculate_cpu_allocation() {
    local total_cpu=$1
    local usable_cpu=$(echo "$total_cpu * 0.7" | bc -l)
    
    # Component allocation (percentages of usable CPU)
    OLLAMA_CPU=$(echo "scale=0; $usable_cpu * 0.35" | bc -l)
    OPENWEBUI_CPU=$(echo "scale=0; $usable_cpu * 0.25" | bc -l)
    COMFYUI_CPU=$(echo "scale=0; $usable_cpu * 0.20" | bc -l)
    N8N_CPU=$(echo "scale=0; $usable_cpu * 0.10" | bc -l)
    POSTGRES_CPU=$(echo "scale=0; $usable_cpu * 0.05" | bc -l)
    REDIS_CPU=$(echo "scale=0; $usable_cpu * 0.03" | bc -l)
    MINIO_CPU=$(echo "scale=0; $usable_cpu * 0.07" | bc -l)
}
```

#### **Memory Allocation**
```bash
# Memory allocation calculation
calculate_memory_allocation() {
    local total_memory_gb=$1
    local usable_memory_gb=$(echo "$total_memory_gb * 0.7" | bc -l)
    
    # Component allocation (percentages of usable memory)
    OLLAMA_MEMORY=$(echo "scale=0; $usable_memory_gb * 0.35 * 1024" | bc -l)  # MB
    OPENWEBUI_MEMORY=$(echo "scale=0; $usable_memory_gb * 0.25 * 1024" | bc -l)
    COMFYUI_MEMORY=$(echo "scale=0; $usable_memory_gb * 0.20 * 1024" | bc -l)
    N8N_MEMORY=$(echo "scale=0; $usable_memory_gb * 0.10 * 1024" | bc -l)
    POSTGRES_MEMORY=$(echo "scale=0; $usable_memory_gb * 0.05 * 1024" | bc -l)
    REDIS_MEMORY=$(echo "scale=0; $usable_memory_gb * 0.03 * 1024" | bc -l)
    MINIO_MEMORY=$(echo "scale=0; $usable_memory_gb * 0.07 * 1024" | bc -l)
}
```

#### **Storage Allocation**
```bash
# Storage allocation calculation
calculate_storage_allocation() {
    local total_storage_gb=$1
    local usable_storage_gb=$(echo "$total_storage_gb * 0.8" | bc -l)
    
    # Component allocation (percentages of usable storage)
    OLLAMA_STORAGE=$(echo "scale=0; $usable_storage_gb * 0.45" | bc -l)  # Models
    OPENWEBUI_STORAGE=$(echo "scale=0; $usable_storage_gb * 0.20" | bc -l)  # Documents
    COMFYUI_STORAGE=$(echo "scale=0; $usable_storage_gb * 0.15" | bc -l)  # Models
    N8N_STORAGE=$(echo "scale=0; $usable_storage_gb * 0.05" | bc -l)  # Workflows
    POSTGRES_STORAGE=$(echo "scale=0; $usable_storage_gb * 0.05" | bc -l)  # Database
    REDIS_STORAGE=$(echo "scale=0; $usable_storage_gb * 0.03" | bc -l)  # Cache
    MINIO_STORAGE=$(echo "scale=0; $usable_storage_gb * 0.07" | bc -l)  # Objects
}
```

---

## ⚙️ Resource Configuration Templates

### 🖥️ **Standard Platform Configuration**

#### **High-Performance Configuration (16GB+ RAM)**
```yaml
# High-performance resource allocation
openWebUI:
  resources:
    limits:
      memory: 4Gi
      cpu: 2000m
    requests:
      memory: 2Gi
      cpu: 1000m
  persistence:
    size: 20Gi

ollama:
  resources:
    limits:
      memory: 6Gi
      cpu: 4000m
    requests:
      memory: 3Gi
      cpu: 2000m
  persistence:
    size: 100Gi
  gpuEnabled: true

comfyUI:
  enabled: true
  resources:
    limits:
      memory: 4Gi
      cpu: 2000m
    requests:
      memory: 2Gi
      cpu: 1000m
  persistence:
    size: 50Gi
  gpuEnabled: true

n8n:
  resources:
    limits:
      memory: 1Gi
      cpu: 500m
    requests:
      memory: 512Mi
      cpu: 250m
  worker:
    replicas: 3
    resources:
      limits:
        memory: 512Mi
        cpu: 250m
```

#### **Standard Configuration (8-16GB RAM)**
```yaml
# Standard resource allocation
openWebUI:
  resources:
    limits:
      memory: 2Gi
      cpu: 1000m
    requests:
      memory: 1Gi
      cpu: 500m
  persistence:
    size: 15Gi

ollama:
  resources:
    limits:
      memory: 4Gi
      cpu: 2000m
    requests:
      memory: 2Gi
      cpu: 1000m
  persistence:
    size: 50Gi
  gpuEnabled: true

comfyUI:
  enabled: false  # Disabled for resource conservation

n8n:
  resources:
    limits:
      memory: 512Mi
      cpu: 250m
    requests:
      memory: 256Mi
      cpu: 125m
  worker:
    replicas: 1
```

#### **Minimal Configuration (4-8GB RAM)**
```yaml
# Minimal resource allocation
openWebUI:
  resources:
    limits:
      memory: 1Gi
      cpu: 500m
    requests:
      memory: 512Mi
      cpu: 250m
  persistence:
    size: 10Gi

ollama:
  resources:
    limits:
      memory: 2Gi
      cpu: 1000m
    requests:
      memory: 1Gi
      cpu: 500m
  persistence:
    size: 20Gi
  gpuEnabled: false  # CPU-only for minimal systems

comfyUI:
  enabled: false

n8n:
  resources:
    limits:
      memory: 256Mi
      cpu: 125m
    requests:
      memory: 128Mi
      cpu: 62m
  worker:
    replicas: 1
```

### 🤖 **Jetson Platform Configuration**

#### **Jetson AGX Orin (32GB)**
```yaml
# Jetson AGX Orin optimized configuration
global:
  platform: jetson
  storageClass: lair-hostpath

openWebUI:
  resources:
    limits:
      memory: 3Gi
      cpu: 1500m
    requests:
      memory: 1500Mi
      cpu: 750m
  persistence:
    size: 15Gi

ollama:
  resources:
    limits:
      memory: 8Gi
      cpu: 2000m
    requests:
      memory: 4Gi
      cpu: 1000m
  persistence:
    size: 50Gi
  gpuEnabled: true
  image:
    repository: dustynv/ollama
    tag: r36.3.0

comfyUI:
  enabled: true
  resources:
    limits:
      memory: 4Gi
      cpu: 1000m
    requests:
      memory: 2Gi
      cpu: 500m
  persistence:
    size: 20Gi
  gpuEnabled: true
  lowVram: true
  image:
    repository: dustynv/comfyui
    tag: r36.3.0
```

#### **Jetson Orin Nano (8GB)**
```yaml
# Jetson Orin Nano optimized configuration
global:
  platform: jetson
  storageClass: lair-hostpath

openWebUI:
  resources:
    limits:
      memory: 1500Mi
      cpu: 1000m
    requests:
      memory: 750Mi
      cpu: 500m
  persistence:
    size: 8Gi

ollama:
  resources:
    limits:
      memory: 3Gi
      cpu: 1500m
    requests:
      memory: 1500Mi
      cpu: 750m
  persistence:
    size: 20Gi
  gpuEnabled: true
  image:
    repository: dustynv/ollama
    tag: r36.3.0

comfyUI:
  enabled: false  # Disabled for 8GB Jetson

n8n:
  resources:
    limits:
      memory: 512Mi
      cpu: 250m
    requests:
      memory: 256Mi
      cpu: 125m
  worker:
    replicas: 1
```

---

## 🔧 Manual Resource Optimization

### ⚙️ **Runtime Resource Adjustment**

#### **Scaling Resources Up**
```bash
# Increase OpenWebUI resources
kubectl patch deployment lair-openwebui -n lair -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "openwebui",
          "resources": {
            "limits": {
              "memory": "4Gi",
              "cpu": "2000m"
            },
            "requests": {
              "memory": "2Gi", 
              "cpu": "1000m"
            }
          }
        }]
      }
    }
  }
}'

# Increase Ollama resources
kubectl patch statefulset lair-ollama -n lair -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "ollama",
          "resources": {
            "limits": {
              "memory": "8Gi",
              "cpu": "4000m"
            },
            "requests": {
              "memory": "4Gi",
              "cpu": "2000m"
            }
          }
        }]
      }
    }
  }
}'
```

#### **Scaling Resources Down**
```bash
# Reduce ComfyUI resources (if enabled)
kubectl patch deployment lair-comfyui -n lair -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "comfyui",
          "resources": {
            "limits": {
              "memory": "2Gi",
              "cpu": "1000m"
            },
            "requests": {
              "memory": "1Gi",
              "cpu": "500m"
            }
          }
        }]
      }
    }
  }
}'
```

### 📊 **Horizontal Pod Autoscaling (HPA)**

#### **Enable HPA for N8N Workers**
```yaml
# HPA configuration for N8N workers
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: n8n-worker-hpa
  namespace: lair
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: lair-n8n-worker
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

#### **Enable HPA for OpenWebUI**
```yaml
# HPA configuration for OpenWebUI
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: openwebui-hpa
  namespace: lair
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: lair-openwebui
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
```

### 💾 **Storage Optimization**

#### **Expand Persistent Volumes**
```bash
# Check current PVC sizes
kubectl get pvc -n lair

# Expand Ollama storage (if storage class supports expansion)
kubectl patch pvc lair-ollama-data -n lair -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'

# Expand OpenWebUI storage
kubectl patch pvc lair-openwebui-data -n lair -p '{"spec":{"resources":{"requests":{"storage":"30Gi"}}}}'

# Check expansion status
kubectl describe pvc lair-ollama-data -n lair
```

#### **Storage Cleanup Optimization**
```bash
# Create storage cleanup script
cat > /usr/local/bin/lair-storage-cleanup.sh << 'EOF'
#!/bin/bash

echo "=== LAIR STORAGE CLEANUP ==="
echo "Started: $(date)"

# Clean up Ollama unused models
kubectl exec -n lair statefulset/lair-ollama -- ollama list | grep -v "NAME" | while read model rest; do
    echo "Checking model: $model"
    # Add logic to remove unused models
done

# Clean up OpenWebUI old documents
kubectl exec -n lair deployment/lair-openwebui -- find /app/backend/data -name "*.tmp" -mtime +7 -delete

# Clean up N8N old executions
kubectl exec -n lair statefulset/lair-postgresql -- psql -U n8n -d n8n -c "DELETE FROM execution_entity WHERE finished_at < NOW() - INTERVAL '30 days';"

# Clean up container logs
sudo find /var/log/containers -name "*.log" -mtime +7 -delete

echo "Cleanup completed: $(date)"
EOF

chmod +x /usr/local/bin/lair-storage-cleanup.sh
```

---

## 🎯 Performance Tuning

### 🚀 **CPU Optimization**

#### **CPU Affinity Configuration**
```yaml
# Pin CPU-intensive workloads to specific cores
ollama:
  nodeSelector:
    kubernetes.io/arch: amd64
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-role.kubernetes.io/worker
            operator: Exists
  resources:
    limits:
      cpu: 4000m
    requests:
      cpu: 2000m
```

#### **CPU Governor Optimization**
```bash
# Set CPU governor to performance mode
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Make permanent
echo 'GOVERNOR="performance"' | sudo tee -a /etc/default/cpufrequtils
sudo systemctl restart cpufrequtils
```

### 🧠 **Memory Optimization**

#### **Memory Overcommit Configuration**
```yaml
# Configure memory overcommit ratios
openWebUI:
  resources:
    limits:
      memory: 4Gi      # Burst limit
    requests:
      memory: 1Gi      # Guaranteed memory (25% of limit)

ollama:
  resources:
    limits:
      memory: 8Gi      # Burst limit
    requests:
      memory: 2Gi      # Guaranteed memory (25% of limit)
```

#### **Swap Configuration**
```bash
# Disable swap for better Kubernetes performance
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Or configure swap accounting (if swap needed)
echo 'GRUB_CMDLINE_LINUX="cgroup_enable=memory swapaccount=1"' | sudo tee -a /etc/default/grub
sudo update-grub
```

### 🎮 **GPU Optimization**

#### **GPU Resource Management**
```yaml
# GPU resource allocation
ollama:
  gpuEnabled: true
  resources:
    limits:
      nvidia.com/gpu: 1
      memory: 8Gi
      cpu: 4000m

comfyUI:
  gpuEnabled: true
  resources:
    limits:
      nvidia.com/gpu: 1  # Shared GPU access
      memory: 4Gi
      cpu: 2000m
  lowVram: true  # Enable for memory-constrained GPUs
```

#### **GPU Memory Optimization**
```bash
# Configure GPU memory growth (for TensorFlow/PyTorch workloads)
kubectl patch deployment lair-comfyui -n lair -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "comfyui",
          "env": [
            {"name": "TF_FORCE_GPU_ALLOW_GROWTH", "value": "true"},
            {"name": "CUDA_VISIBLE_DEVICES", "value": "0"}
          ]
        }]
      }
    }
  }
}'
```

---

## 📊 Resource Monitoring & Analysis

### 🔍 **Resource Usage Analysis**

#### **Real-time Resource Monitoring**
```bash
# Monitor resource usage continuously
watch -n 5 'kubectl top pods -n lair'

# Detailed resource analysis
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check resource requests vs limits
kubectl get pods -n lair -o custom-columns=NAME:.metadata.name,CPU_REQ:.spec.containers[0].resources.requests.cpu,CPU_LIM:.spec.containers[0].resources.limits.cpu,MEM_REQ:.spec.containers[0].resources.requests.memory,MEM_LIM:.spec.containers[0].resources.limits.memory
```

#### **Resource Utilization Report**
```bash
# Create resource utilization report
cat > /usr/local/bin/lair-resource-report.sh << 'EOF'
#!/bin/bash

echo "=== LAIR RESOURCE UTILIZATION REPORT ==="
echo "Generated: $(date)"
echo

echo "=== NODE RESOURCES ==="
kubectl describe nodes | grep -A 10 "Allocated resources"
echo

echo "=== POD RESOURCE USAGE ==="
kubectl top pods -n lair --sort-by=cpu
echo

echo "=== MEMORY USAGE BREAKDOWN ==="
kubectl top pods -n lair --sort-by=memory
echo

echo "=== STORAGE USAGE ==="
kubectl get pvc -n lair -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,STATUS:.status.phase
echo

echo "=== RESOURCE EFFICIENCY ==="
kubectl get pods -n lair -o json | jq -r '.items[] | "\(.metadata.name): CPU: \(.spec.containers[0].resources.requests.cpu // "none") / \(.spec.containers[0].resources.limits.cpu // "none"), Memory: \(.spec.containers[0].resources.requests.memory // "none") / \(.spec.containers[0].resources.limits.memory // "none")"'
EOF

chmod +x /usr/local/bin/lair-resource-report.sh
```

### 📈 **Capacity Planning**

#### **Growth Trend Analysis**
```bash
# Create capacity planning script
cat > /usr/local/bin/lair-capacity-planning.sh << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/lair-capacity.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Collect current usage
CPU_USAGE=$(kubectl top nodes --no-headers | awk '{sum+=$3} END {print sum}' | sed 's/m//')
MEMORY_USAGE=$(kubectl top nodes --no-headers | awk '{sum+=$5} END {print sum}' | sed 's/Mi//')
STORAGE_USAGE=$(kubectl get pvc -n lair -o json | jq -r '.items[] | .status.capacity.storage' | sed 's/Gi//' | awk '{sum+=$1} END {print sum}')

# Log usage data
echo "$DATE,$CPU_USAGE,$MEMORY_USAGE,$STORAGE_USAGE" >> "$LOG_FILE"

# Analyze trends (last 30 days)
if [ -f "$LOG_FILE" ]; then
    echo "=== CAPACITY TREND ANALYSIS ==="
    tail -720 "$LOG_FILE" | awk -F',' '
    BEGIN {
        cpu_sum=0; mem_sum=0; storage_sum=0; count=0
    }
    {
        cpu_sum+=$2; mem_sum+=$3; storage_sum+=$4; count++
    }
    END {
        if (count > 0) {
            printf "Average CPU: %.0fm\n", cpu_sum/count
            printf "Average Memory: %.0fMi\n", mem_sum/count
            printf "Average Storage: %.0fGi\n", storage_sum/count
        }
    }'
fi
EOF

chmod +x /usr/local/bin/lair-capacity-planning.sh
```

---

## 🚨 Resource Troubleshooting

### 🔧 **Common Resource Issues**

#### **Out of Memory (OOMKilled)**
```bash
# Identify OOMKilled pods
kubectl get pods -n lair -o json | jq -r '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason == "OOMKilled") | .metadata.name'

# Check memory limits
kubectl describe pod <pod-name> -n lair | grep -A 5 -B 5 memory

# Solution: Increase memory limits
kubectl patch deployment <deployment-name> -n lair -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","resources":{"limits":{"memory":"4Gi"}}}]}}}}'
```

#### **CPU Throttling**
```bash
# Check CPU throttling
kubectl top pods -n lair
kubectl describe pod <pod-name> -n lair | grep -A 5 -B 5 cpu

# Monitor CPU usage over time
kubectl exec -n lair <pod-name> -- top -bn1 | head -5

# Solution: Increase CPU limits
kubectl patch deployment <deployment-name> -n lair -p '{"spec":{"template":{"spec":{"containers":[{"name":"<container-name>","resources":{"limits":{"cpu":"2000m"}}}]}}}}'
```

#### **Storage Full**
```bash
# Check storage usage
kubectl exec -n lair <pod-name> -- df -h

# Check PVC capacity
kubectl get pvc -n lair
kubectl describe pvc <pvc-name> -n lair

# Solution: Expand storage (if supported)
kubectl patch pvc <pvc-name> -n lair -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
```

#### **Resource Contention**
```bash
# Identify resource-heavy pods
kubectl top pods -A --sort-by=cpu | head -10
kubectl top pods -A --sort-by=memory | head -10

# Check node resource pressure
kubectl describe nodes | grep -A 10 "Conditions"

# Solution: Redistribute workloads or add resources
```

---

## 🎯 Best Practices

### 📊 **Resource Allocation Best Practices**
- **Right-sizing**: Start with conservative estimates and scale up based on usage
- **Overcommit Ratios**: Use 2-4x overcommit for limits vs requests
- **Resource Monitoring**: Continuously monitor and adjust based on actual usage
- **Platform Optimization**: Use platform-specific configurations (Jetson vs Standard)

### 🔧 **Performance Best Practices**
- **CPU Affinity**: Pin CPU-intensive workloads to specific cores
- **Memory Management**: Disable swap and use appropriate memory limits
- **GPU Sharing**: Implement GPU sharing for multiple AI workloads
- **Storage Optimization**: Use appropriate storage classes and cleanup policies

### 🚨 **Troubleshooting Best Practices**
- **Proactive Monitoring**: Set up alerts for resource exhaustion
- **Capacity Planning**: Regular analysis of resource trends
- **Documentation**: Document resource changes and their impact
- **Testing**: Test resource changes in non-production environments

---

**🎯 Ready to optimize your resources?** Continue with [Advanced Configuration](advanced-configuration.md) or explore [Cluster Configuration](../components/cluster.md)!
