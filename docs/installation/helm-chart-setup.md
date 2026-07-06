# 📦 Helm Chart Deployment Guide

> **Complete guide for deploying Lair applications using the Helm chart with intelligent configuration**

The Helm chart deployment (`helm-chart/setup.sh`) provides an interactive configuration system that detects your environment, calculates optimal resource allocation, and generates a complete Kubernetes deployment for all Lair applications.

---

## 🎯 Overview

The Helm chart deployment is the final step that transforms your Kubernetes cluster into a complete AI infrastructure platform. It handles everything from resource detection to application deployment.

### 🔄 **Deployment Flow**
```
System Detection → Resource Planning → Component Config → YAML Generation → Deployment
       ↓                   ↓               ↓              ↓             ↓
   CPU/Memory/GPU    → Allocation %   → Service Setup → values-*.yaml → Helm Install
   Platform Type     → Storage Size   → Domain Config → Ingress Rules → Running Apps
   Network Config    → Replica Count  → Access Mode   → TLS Certs    → Ready to Use
```

### 📦 **What Gets Deployed**
- **🤖 OpenWebUI**: Private ChatGPT-like interface with RAG capabilities
- **⚡ N8N**: Workflow automation platform with workers
- **🧠 Ollama**: Local LLM serving platform with GPU support
- **🎨 ComfyUI**: AI image generation interface (optional)
- **💾 MinIO**: S3-compatible object storage (optional)
- **📄 Tika**: Document processing and text extraction
- **🗄️ PostgreSQL**: Database with pgvector for embeddings
- **⚡ Redis**: Cache and queue system
- **🔐 TLS Certificates**: Automatic HTTPS with Let's Encrypt or mkcert
- **🌐 Ingress**: NGINX ingress with intelligent routing

---

## 📋 Prerequisites

### 🔧 **Cluster Requirements**
- **✅ Kubernetes Cluster**: MicroK8s or managed cluster ready
- **✅ Ingress Controller**: NGINX Ingress installed and running
- **✅ Storage**: StorageClass available (Longhorn or Hostpath)
- **✅ Cert-Manager**: For automatic TLS certificate management
- **✅ MetalLB**: Load balancer for external access

### 📊 **Resource Requirements**

| Component | CPU (min) | Memory (min) | Storage (min) | GPU |
|-----------|-----------|--------------|---------------|-----|
| **OpenWebUI** | 0.5 cores | 1GB | 10GB | Optional |
| **Ollama** | 1.0 cores | 2GB | 20GB | Recommended |
| **N8N + Workers** | 0.3 cores | 1.5GB | 10GB | No |
| **PostgreSQL** | 0.1 cores | 256MB | 5GB | No |
| **Redis** | 0.1 cores | 128MB | 5GB | No |
| **ComfyUI** | 1.0 cores | 2GB | 10GB | Recommended |
| **MinIO** | 0.2 cores | 512MB | 10GB | No |
| **Tika** | 0.1 cores | 256MB | - | No |
| **Total Minimum** | **3.3 cores** | **7.6GB** | **70GB** | - |

### ⚠️ **Important Notes**
- **Minimum 8GB RAM recommended** for comfortable operation
- **GPU highly recommended** for AI workloads (Ollama, ComfyUI)
- **Jetson optimization** automatically applied for ARM64 platforms
- **Internet access required** for initial model downloads

---

## 🚀 Quick Start

### 🎯 **Interactive Setup**
```bash
# Navigate to helm-chart directory
cd helm-chart

# Run interactive setup
sudo ./setup.sh
```

The script will guide you through:
1. **🔍 System Detection**: Automatic resource and platform detection
2. **🏗️ Platform Configuration**: Jetson vs Standard optimization
3. **🌐 Access Configuration**: LAN vs Public access setup
4. **🧩 Component Selection**: Enable/disable optional components
5. **📊 Resource Allocation**: Intelligent resource distribution
6. **🚀 Deployment**: Automatic Helm deployment (if cluster accessible)

### 📝 **Configuration File Mode**
```bash
# Use existing configuration
sudo ./setup.sh --config lair-config-standard.yaml

# Update existing configuration
sudo ./setup.sh --update values-myconfig.yaml

# Interactive mode (skip config import)
sudo ./setup.sh --interactive
```

---

## 🔧 Detailed Configuration Process

### 📊 **Phase 1: System Detection & Resource Planning**

#### **🔍 Automatic Detection**
The script automatically detects:

```bash
# System Resources
Total CPU: 8 cores detected
Total RAM: 16GB detected  
Available Storage: 500GB detected
GPU: NVIDIA RTX 4090 detected

# Platform Detection
Platform: standard (x86_64)
Jetson: No
Cluster Type: MicroK8s detected

# Network Detection
Public IP: 203.0.113.10 (Cloud scenario detected)
Local IP: 192.168.1.100
```

#### **🧮 Resource Calculation**
Intelligent allocation based on available resources:

```bash
# Resource Allocation (30% of system reserved for apps)
Kubernetes CPU: 5.6 cores (from 8 total)
Kubernetes RAM: 11.2GB (from 16GB total)
Usable Storage: 400GB (80% of 500GB available)

# Component Allocation
OpenWebUI: 25% → 1.4 cores, 2.8GB RAM
Ollama: 35% → 2.0 cores, 3.9GB RAM  
N8N: 5% → 0.3 cores, 0.6GB RAM
ComfyUI: 20% → 1.1 cores, 2.2GB RAM
PostgreSQL: 5% → 0.3 cores, 0.6GB RAM
Redis: 3% → 0.2 cores, 0.3GB RAM
MinIO: 7% → 0.4 cores, 0.8GB RAM
```

### 🏗️ **Phase 2: Platform & Application Configuration**

#### **🤖 Platform Detection**
```bash
# Interactive prompt:
Is this installation for NVIDIA Jetson? (y/n) [default: y]:

# Jetson Configuration:
✅ Jetson platform detected - GPU enabled by default
⚠️ Using microk8s hostpath provisioner (Longhorn not recommended for Jetson)

# Standard Configuration:
✅ Standard platform detected
✅ GPU detection completed: NVIDIA GPU detected
```

#### **🌐 Access Mode Configuration**
```bash
# Domain Configuration Options:

1) 🏠 LAN Access Only (.local domains)
   - ai.hostname.local
   - n8n.hostname.local
   - Optional HTTPS with mkcert

2) 🌍 Public Access Only (internet domains)  
   - ai.example.com
   - n8n.example.com
   - Automatic HTTPS with Let's Encrypt

3) 🔄 Both LAN and Public Access
   - LAN: .local domains with mkcert
   - Public: internet domains with Let's Encrypt
```

#### **🧩 Component Selection**
```bash
# Interactive Component Configuration:

📦 MinIO Object Storage
Enable MinIO for S3-compatible storage? (y/n) [default: y]:
✅ MinIO enabled - S3 API for file storage

🎨 ComfyUI Image Generation  
Enable ComfyUI for AI image generation? (y/n) [default: y]:
✅ ComfyUI enabled - GPU acceleration available

🔐 OpenWebUI SSO Integration
Enable Single Sign-On for OpenWebUI? (y/n) [default: n]:
❌ SSO disabled - using built-in authentication
```

### 📁 **Phase 3: Infrastructure & Deployment Setup**

#### **💾 Storage Class Configuration**
```bash
# Automatic based on platform:

# Jetson Platform:
✅ StorageClass: lair-hostpath (hostpath-based for Jetson)

# Standard Platform:  
✅ StorageClass: lair-storage (Longhorn-based for standard platforms)
```

#### **🔐 Certificate Management**
```bash
# Automatic based on access mode:

# LAN Mode:
🔧 Let's Encrypt: Disabled (suitable for .local domains)
📋 Use mkcert for local HTTPS certificates

# Public Mode:
✅ Let's Encrypt: Enabled (automatic TLS certificates)
📋 Ensure domains point to your cluster's external IP
```

### 📝 **Phase 4: Configuration Generation & Deployment**

#### **🔧 YAML Generation**
The script generates a complete `values-<name>.yaml` file:

```yaml
# Generated configuration structure:
namespace: lair
global:
  storageClass: "lair-storage"
  platform: "standard"

# Ingress configuration with LAN/Public support
ingress:
  className: public
  lan:
    enabled: true
    hosts: [...]
  public:
    enabled: true  
    hosts: [...]

# Resource-optimized application configuration
openWebUI:
  resources:
    limits: { memory: 2867Mi, cpu: 1400m }
    requests: { memory: 1434Mi, cpu: 700m }
  persistence: { size: 10Gi }

ollama:
  gpuEnabled: true
  resources:
    limits: { memory: 3993Mi, cpu: 2000m }
    requests: { memory: 1997Mi, cpu: 1000m }
  persistence: { size: 30Gi }

# ... (all other components)
```

#### **🚀 Automatic Deployment**
If cluster is accessible, automatic deployment:

```bash
# Deployment process:
✅ Cluster accessible - proceeding with deployment
📦 Installing Helm chart...
🔄 Waiting for pods to be ready...
✅ All components deployed successfully!

# Access information:
🏠 LAN Access:
   • OpenWebUI: https://ai.hostname.local
   • N8N: https://n8n.hostname.local

🌍 Public Access:  
   • OpenWebUI: https://ai.example.com
   • N8N: https://n8n.example.com
```

---

## 🎛️ Configuration Options

### 📋 **Pre-built Configuration Templates**

#### **Standard Configuration** (`lair-config-standard.yaml`)
```bash
# Optimized for standard x86_64 systems
- Platform: standard
- GPU: Auto-detected
- Storage: Longhorn
- Components: All enabled
- Access: Dual (LAN + Public)
```

#### **Jetson Configuration** (`lair-config-template-jetson.yaml`)
```bash
# Optimized for NVIDIA Jetson devices
- Platform: jetson  
- GPU: Tegra (always enabled)
- Storage: Hostpath
- Components: Memory-optimized selection
- Access: LAN preferred
```

### 🔧 **Advanced Configuration Options**

#### **Resource Override**
```bash
# During setup, when prompted:
Use these detected resources? (y/n) [default: y]: n

# Manual resource configuration:
CPU cores available for Kubernetes: 6
RAM available for Kubernetes in GB: 12  
Storage available for Lair in GB: 300
```

#### **Component Customization**
```bash
# N8N Worker Configuration:
Number of N8N workers [default: 2]: 1

# Storage Size Customization:
OpenWebUI storage size [default: 10Gi]: 20Gi
Ollama storage size [default: 30Gi]: 50Gi
```

#### **Domain Configuration**
```bash
# LAN Domain Configuration:
System hostname for .local domains [default: lair]: myai
# Results in: ai.myai.local, n8n.myai.local

# Public Domain Configuration:  
OpenWebUI domain: openwebui.mycompany.com
N8N domain: n8n.mycompany.com
ComfyUI domain: images.mycompany.com
```

---

## 🌐 Access Modes Deep Dive

### 🏠 **LAN Access Mode**

#### **Configuration**
```yaml
ingress:
  lan:
    enabled: true
    enableTLS: false  # Set to true for mkcert HTTPS
    hosts:
      - host: ai.hostname.local
        serviceName: openwebui
      - host: n8n.hostname.local  
        serviceName: n8n
```

#### **DNS Requirements**
```bash
# Option 1: Router DNS configuration
# Add to router's DNS server:
192.168.1.100  ai.hostname.local
192.168.1.100  n8n.hostname.local

# Option 2: Local hosts file (each client)
# Add to /etc/hosts (Linux/Mac) or C:\Windows\System32\drivers\etc\hosts (Windows):
192.168.1.100  ai.hostname.local
192.168.1.100  n8n.hostname.local
```

#### **HTTPS Setup (Optional)**
```bash
# Generate mkcert certificates:
cd helm-chart
sudo ./generate-lan-certificates.sh --wildcard hostname.local

# Apply certificates:
helm upgrade --install lair . -n lair -f values-config.yaml
```

### 🌍 **Public Access Mode**

#### **Configuration**
```yaml
ingress:
  public:
    enabled: true
    hosts:
      - host: ai.example.com
        serviceName: openwebui
      - host: n8n.example.com
        serviceName: n8n

certManager:
  createClusterIssuer: true
  email: admin@example.com
```

#### **DNS Requirements**
```bash
# DNS A records required:
ai.example.com        A    203.0.113.10
n8n.example.com  A    203.0.113.10
images.example.com      A    203.0.113.10
storage.example.com     A    203.0.113.10
```

#### **Firewall Configuration**
```bash
# Required ports:
80/tcp   - HTTP (redirects to HTTPS)
443/tcp  - HTTPS (main access)
6443/tcp - Kubernetes API (if remote access enabled)

# Cloud platforms: Usually automatic
# On-premises: Configure router port forwarding
```

---

## 🔍 Verification & Testing

### ✅ **Post-Deployment Checks**

#### **Pod Status**
```bash
# Check all pods are running
kubectl get pods -n lair

# Expected output:
NAME                         READY   STATUS    RESTARTS
lair-openwebui-xxx           1/1     Running   0
lair-ollama-0                1/1     Running   0  
lair-n8n-xxx                 1/1     Running   0
lair-n8n-worker-xxx          1/1     Running   0
lair-postgresql-0            1/1     Running   0
lair-redis-xxx               1/1     Running   0
lair-minio-xxx               1/1     Running   0
lair-comfyui-xxx             1/1     Running   0
lair-tika-xxx                1/1     Running   0
```

#### **Service Access**
```bash
# Check services and external IPs
kubectl get services -n lair

# Check ingress configuration
kubectl get ingress -n lair

# Test external access
curl -k https://ai.hostname.local  # LAN mode
curl -k https://ai.example.com     # Public mode
```

#### **Storage Verification**
```bash
# Check persistent volume claims
kubectl get pvc -n lair

# All PVCs should be "Bound":
NAME                    STATUS   VOLUME     CAPACITY
lair-openwebui-data     Bound    pvc-xxx    10Gi
lair-ollama-data        Bound    pvc-xxx    30Gi
lair-n8n-data           Bound    pvc-xxx    10Gi
lair-postgresql-data    Bound    pvc-xxx    5Gi
lair-redis-data         Bound    pvc-xxx    5Gi
```

#### **Certificate Verification**
```bash
# Check TLS certificates (Public mode)
kubectl get certificates -n lair

# Check certificate secrets
kubectl get secrets -n lair | grep tls
```

### 🚨 **Common Issues & Solutions**

#### **Pods Stuck in Pending**
```bash
# Check resource constraints
kubectl describe pod <pod-name> -n lair

# Common causes:
- Insufficient CPU/memory resources
- Storage class not available
- Node selector constraints

# Solutions:
- Reduce resource requests in values file
- Check storage class: kubectl get storageclass
- Verify node resources: kubectl top nodes
```

#### **ImagePullBackOff Errors**
```bash
# Check image pull status
kubectl describe pod <pod-name> -n lair

# Common causes:
- No internet connectivity from cluster
- DNS resolution issues
- Registry authentication problems

# Solutions:
- Test cluster internet: kubectl run test --image=busybox --rm -it -- ping google.com
- Check DNS: kubectl exec -it <pod> -- nslookup google.com
- Verify image names in values file
```

#### **Ingress Not Working**
```bash
# Check ingress controller
kubectl get pods -n ingress

# Check ingress configuration
kubectl describe ingress -n lair

# Common causes:
- Ingress controller not running
- DNS not pointing to cluster IP
- Firewall blocking ports 80/443

# Solutions:
- Restart ingress: kubectl rollout restart deployment -n ingress
- Check MetalLB: kubectl get services -n ingress
- Verify DNS resolution: nslookup ai.hostname.local
```

---

## 🔧 Advanced Deployment Options

### 📝 **Configuration File Management**

#### **Generate Configuration Only**
```bash
# Generate config without deploying
sudo ./setup.sh
# Choose option 5: "Save Configuration Only (No Deploy)"

# Manual deployment later:
helm upgrade --install lair . -n lair --create-namespace \
  -f values-myconfig.yaml
```

#### **Update Existing Deployment**
```bash
# ⚠️ CRITICAL: Configuration updates can be dangerous
# Safe method:
sudo ./setup.sh --config existing-config.yaml  # Generate new config
nano values-myconfig.yaml                      # Edit manually
helm upgrade --install lair . -n lair -f values-myconfig.yaml
```

#### **Multiple Environments**
```bash
# Development environment
sudo ./setup.sh
# Save as: values-dev.yaml

# Production environment  
sudo ./setup.sh
# Save as: values-prod.yaml

# Deploy specific environment:
helm upgrade --install lair-dev . -n lair-dev --create-namespace \
  -f values-dev.yaml

helm upgrade --install lair-prod . -n lair-prod --create-namespace \
  -f values-prod.yaml
```

### 🎛️ **Custom Helm Values**

#### **Resource Overrides**
```yaml
# values-custom.yaml
openWebUI:
  resources:
    limits:
      memory: 4Gi
      cpu: 2000m
    requests:
      memory: 2Gi  
      cpu: 1000m

ollama:
  persistence:
    size: 100Gi  # Larger storage for more models
```

#### **Component Disabling**
```yaml
# Disable optional components
comfyUI:
  enabled: false

minio:
  enabled: false
```

#### **Advanced Network Configuration**
```yaml
# Custom ingress annotations
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
```

---

## 🔄 Next Steps

After successful deployment:

1. **✅ Verify Deployment**: Run all verification checks above
2. **🔐 Setup Admin Accounts**: Create admin users in OpenWebUI and N8N
3. **📚 Configure Applications**: Set up your AI models and workflows
4. **🔒 Setup Certificates**: Configure [TLS Certificates](../configuration/security-certificates.md) for HTTPS
5. **📊 Monitor System**: Set up [Monitoring](../maintenance/monitoring.md)
6. **💾 Configure Backups**: Set up [Backup Procedures](../maintenance/backup-restore.md)

---

**🎯 Ready to use your AI infrastructure?** Check the [Components Documentation](../components/services-overview.md) to learn about each application!
