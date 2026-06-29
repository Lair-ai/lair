# 🔧 MicroK8s Installation Guide

> **Complete guide for setting up Kubernetes clusters with MicroK8s optimized for Lair - supports both single-node and multi-node deployments**

MicroK8s provides a lightweight Kubernetes cluster solution perfect for development, edge computing, and production deployments. This guide covers both single-node and multi-node cluster setup with platform-specific optimizations.

---

## 🎯 Overview

The MicroK8s setup process (`microk8s/setup.sh`) orchestrates Kubernetes cluster installation with support for both single-node and multi-node deployments:

### 🏗️ **Deployment Types**

| Type | Use Case | Nodes | Storage | Best For |
|------|----------|-------|---------|----------|
| **Single-Node** | Development, testing | 1 | Longhorn/Hostpath | Local development, Jetson |
| **Multi-Node** | Production, scaling | 2+ | Distributed Longhorn | High availability, load distribution |

### 🔄 **Installation Flow**
```
Node Detection → Prerequisites → Network → MicroK8s → Addons → Storage → Backup → Verification
      ↓               ↓             ↓         ↓         ↓        ↓        ↓         ↓
Primary/Secondary → OS/DNS/NTP → IP Detection → Snap → Ingress → Longhorn → Velero → Health Check
```

### 📦 **What Gets Installed**
- **MicroK8s 1.32/stable**: Kubernetes cluster via Snap
- **Core Addons**: Ingress (NGINX), Helm3, DNS, RBAC
- **Storage**: Longhorn (distributed) or Hostpath (Jetson)
- **Network**: Calico (standard) or Flannel (Jetson)
- **Load Balancer**: MetalLB with intelligent IP allocation
- **Certificates**: Cert-Manager for TLS automation
- **Backup**: Velero for disaster recovery (optional)
- **GPU Support**: NVIDIA GPU detection and configuration

---

## 📋 Prerequisites

### 🖥️ **System Requirements**

| Component | Minimum | Recommended | Jetson |
|-----------|---------|-------------|---------|
| **OS** | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| **CPU** | 4+ cores | 8+ cores | 4+ cores (ARM64) |
| **RAM** | 8GB | 16GB+ | 8GB+ |
| **Storage** | 100GB free | 200GB+ free | 128GB+ SD card |
| **Network** | Internet access | Stable connection | WiFi/Ethernet |

### ⚠️ **Important Notes**
- **⚠️ Windows NOT supported**: Lair does **NOT work on Windows**, including WSL2, WSL, or any Windows emulation layer
- **Root access required**: Installation must run as root/sudo
- **Internet required**: For package downloads and container images
- **Clean system recommended**: Fresh Ubuntu 24.04 installation preferred
- **🤖 Jetson limitations**: NVIDIA Jetson devices are **single-node only** with specific optimizations

---

## 🏗️ Multi-Node Cluster Setup

### 🎯 **Multi-Node Architecture**

```
┌─────────────────────────────────────────────────────────────────┐
│                    🏗️ MULTI-NODE CLUSTER                        │
│                                                                 │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │  PRIMARY NODE   │    │ SECONDARY NODE  │    │ SECONDARY NODE  │ │
│  │                 │    │                 │    │                 │ │
│  │ • Control Plane │    │ • Worker Node   │    │ • Worker Node   │ │
│  │ • All Addons    │    │ • Longhorn      │    │ • Longhorn      │ │
│  │ • Velero Backup │    │ • Storage       │    │ • Storage       │ │
│  │ • MetalLB       │    │ • Workloads     │    │ • Workloads     │ │
│  │ • Cert-Manager  │    │                 │    │                 │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│           │                       │                       │       │
│           └───────────────────────┼───────────────────────┘       │
│                                   │                               │
│                    📡 Cluster Network                             │
└─────────────────────────────────────────────────────────────────┘
```

### 🚀 **Quick Multi-Node Setup**

#### **Step 1: Setup Primary Node**
```bash
# On the primary node (master)
cd microk8s/
sudo ./setup.sh

# When prompted, select:
# - Node type: primary
# - Configure cluster name (optional)
# - Complete normal setup

# After completion, find join token in:
cat microk8s-join-info.txt
```

#### **Step 2: Setup Secondary Nodes**
```bash
# On each secondary node (worker)
cd microk8s/

# Method 1: Simplified script (RECOMMENDED)
sudo ./utils/setup-secondary.sh <PRIMARY_IP> <JOIN_TOKEN>

# Method 2: Interactive setup
sudo ./setup.sh
# Select: Node type: secondary
# Enter: Primary node IP and join token
```

#### **Step 3: Verify Cluster**
```bash
# On primary node, check all nodes
microk8s kubectl get nodes -o wide

# Expected output:
# NAME        STATUS   ROLES    AGE   VERSION   INTERNAL-IP
# primary     Ready    <none>   10m   v1.32.0   192.168.1.100
# secondary1  Ready    <none>   5m    v1.32.0   192.168.1.101
# secondary2  Ready    <none>   3m    v1.32.0   192.168.1.102
```

### 🔧 **Advanced Multi-Node Configuration**

#### **Configuration File Method**
```bash
# Copy and customize cluster configuration
cp cluster.conf.example cluster.conf

# Edit cluster.conf with your values:
# NODE_TYPE=secondary
# PRIMARY_NODE_IP=192.168.1.100
# JOIN_TOKEN=192.168.1.100:25000/abc123...
# CLUSTER_NAME=lair-cluster

# Run setup with configuration
sudo ./setup.sh
```

#### **Environment Variables Method**
```bash
# Set environment variables
export NODE_TYPE="secondary"
export PRIMARY_NODE_IP="192.168.1.100"
export JOIN_TOKEN="192.168.1.100:25000/abc123..."

# Run setup
sudo ./setup.sh
```

### 📊 **Multi-Node Benefits**

#### **🚀 Performance & Scalability**
- **Load Distribution**: Workloads spread across multiple nodes
- **Resource Scaling**: Add nodes to increase cluster capacity
- **Parallel Processing**: Multiple nodes handle concurrent requests
- **Storage Performance**: Distributed Longhorn storage across nodes

#### **🛡️ High Availability**
- **Node Redundancy**: Cluster survives individual node failures
- **Distributed Storage**: Data replicated across multiple nodes
- **Service Continuity**: Workloads automatically reschedule on healthy nodes
- **Backup Distribution**: Velero backup runs on stable primary node

#### **🔧 Operational Advantages**
- **Rolling Updates**: Update nodes one at a time without downtime
- **Maintenance Windows**: Take nodes offline for maintenance
- **Resource Isolation**: Separate workloads by node characteristics
- **Cost Optimization**: Use different node sizes for different workloads

### ⚙️ **Multi-Node Components**

#### **Primary Node Components**
- **Control Plane**: Kubernetes API server, scheduler, controller manager
- **All Addons**: MetalLB, Cert-Manager, Ingress Controller
- **Velero Backup**: Centralized backup management
- **Storage Coordination**: Longhorn management and coordination
- **Cluster Management**: Node joining, token generation

#### **Secondary Node Components**
- **Kubelet**: Node agent for pod management
- **Container Runtime**: Container execution environment
- **Longhorn Storage**: Distributed storage participation
- **Network Components**: CNI plugins for cluster networking
- **Monitoring Agents**: Node-level monitoring and logging

---

### 🔍 **Pre-Installation Check**
```bash
# Check OS version
lsb_release -a

# Check available resources
free -h
df -h
nproc

# Check internet connectivity
ping -c 3 google.com

# Check if running as root
id
```

---

## 🚀 Quick Start

### 🎯 **Single-Node Installation**
```bash
# Clone repository
git clone https://github.com/Lair-ai/lair.git
cd lair

# Run MicroK8s setup (defaults to single-node)
sudo ./microk8s/setup.sh
```

### 🏗️ **Multi-Node Installation**

#### **Primary Node Setup**
```bash
# On the primary/master node
sudo ./microk8s/setup.sh

# When prompted, select:
# - Node type: primary
# - Configure cluster settings
```

#### **Secondary Node Setup**
```bash
# On each worker node (after primary is ready)
sudo ./microk8s/utils/setup-secondary.sh <PRIMARY_IP> <JOIN_TOKEN>

# Or use interactive mode:
sudo ./microk8s/setup.sh
# Select: Node type: secondary
```

The script will guide you through:
1. **Node Type Selection**: Primary, Secondary, or Single-node
2. **Cluster Configuration**: Join tokens and cluster settings (multi-node)
3. **Access Mode Selection**: LAN vs Public access
4. **Network Configuration**: IP detection and MetalLB pool
5. **Hostname Setup**: System hostname configuration
6. **Remote Access**: Optional remote kubectl access
7. **Backup Configuration**: Optional Velero backup setup (primary node only)

### 📊 **Interactive Prompts**

#### 🏗️ **Node Type Selection** (Multi-Node)
```
🏗️ Node type? [primary/secondary/single] (default: single):
```
- **`primary`**: Master node with control plane and all addons
- **`secondary`**: Worker node that joins existing cluster
- **`single`**: Traditional single-node deployment (default)

#### 🔗 **Cluster Configuration** (Secondary Nodes)
```
🔗 Primary node IP address: 192.168.1.100
🔗 Join token from primary node: 192.168.1.100:25000/abc123...
```
- **Primary IP**: IP address of the primary/master node
- **Join Token**: Token generated by primary node (found in `microk8s-join-info.txt`)

#### 🌐 **Access Mode Selection**
```
🌐 Access mode? [lan/public] (default: lan):
```
- **`lan`**: Local network access with `.local` domains
- **`public`**: Internet access with public IP configuration

#### 🔧 **Network Configuration**
```
🌐 Proposed MetalLB pool (machine IP): 192.168.1.100-192.168.1.100. Confirm? [Y/n]:
```
- **LAN mode**: Uses local machine IP
- **Public mode**: Uses detected public IP or manual entry

#### 🌐 **Remote Access Configuration**
```
🌐 Enable remote cluster access? [Y/n] (default: Y):
```
- **Enabled**: Allows remote kubectl access from other machines
- **Disabled**: Local access only (SSH required)

---

## 🔧 Detailed Installation Process

### 📝 **Step-by-Step Breakdown**

The `microk8s/setup.sh` script orchestrates multiple modules in sequence:

#### **Phase 1: Pre-flight Checks** (`lib/preflight.sh`)
```bash
# What happens:
- OS compatibility check (Linux/Ubuntu)
- Internet connectivity verification
- DNS configuration (systemd-resolved or static fallback)
- NTP synchronization check
```

#### **Phase 2: Initial Setup** (`lib/initial_setup.sh`)
```bash
# What happens:
- Root execution verification
- Verbose/debug mode setup
- ANSI color configuration
- Fail-fast error handling
```

#### **Phase 3: Platform Detection** (`lib/platform_detection.sh`)
```bash
# What happens:
- NVIDIA Jetson detection via device tree
- Tegra kernel detection
- Platform-specific optimizations
```

#### **Phase 4: Network Configuration** (`lib/network.sh`)
```bash
# What happens:
- Default interface detection (ip route)
- Local IP and CIDR extraction
- Public IP detection (multiple methods)
- Network diagnostics and validation
```

#### **Phase 5: MetalLB Configuration** (`lib/microk8s_metallb_config.sh`)
```bash
# What happens:
- Access mode selection (LAN/Public)
- IP pool calculation based on mode
- Cloud vs On-Premises scenario detection
- MetalLB range configuration
```

#### **Phase 6: System Setup** (`lib/system_setup.sh`)
```bash
# What happens:
- Hostname configuration
- System package updates
- Required dependencies installation
```

#### **Phase 7: MicroK8s Installation** (`lib/microk8s_install.sh`)
```bash
# What happens:
- Snap installation of MicroK8s 1.32/stable
- User group configuration (microk8s group)
- Kubeconfig export and permissions
- kubectl wrapper creation
- Remote access configuration (optional)
```

#### **Phase 8: Core Addons** (`lib/microk8s_addon_core.sh`)
```bash
# What happens:
- Enable ingress addon (NGINX)
- Enable helm3 addon
- Addon readiness verification
```

#### **Phase 9: Network CNI** (`lib/microk8s_flannel.sh` - Jetson only)
```bash
# What happens (Jetson only):
- Flannel CNI configuration for ARM64
- Calico removal and cleanup
- Kernel module loading (VXLAN, bridge)
- Interface detection and optimization
- Pod CIDR assignment verification
- Extensive diagnostics and testing
```

#### **Phase 10: Certificate Manager** (`lib/microk8s_certmanager.sh`)
```bash
# What happens:
- Cert-Manager addon enablement
- ClusterIssuer preparation
- TLS certificate automation setup
```

#### **Phase 11: Storage Configuration** (`lib/microk8s_hostpath.sh` & `lib/microk8s_longhorn.sh`)
```bash
# Hostpath (Jetson):
- Enable hostpath-storage addon
- Configure as default StorageClass

# Longhorn (Standard):
- Install dependencies (open-iscsi, nfs-common)
- Add Longhorn Helm repository
- Install Longhorn with MicroK8s-specific settings
- Patch driver-deployer for kubelet root directory
- Verify installation with test PVC
```

#### **Phase 12: MetalLB Setup** (`lib/microk8s_metallb_setup.sh`)
```bash
# What happens:
- MetalLB addon enablement with calculated IP range
- Load balancer service verification
- External IP assignment testing
```

#### **Phase 13: GPU Configuration** (`lib/microk8s_gpu.sh`)
```bash
# What happens:
- NVIDIA GPU detection
- GPU addon enablement (if available)
- CUDA runtime configuration
```

#### **Phase 14: Velero Backup** (`lib/microk8s_velero.sh`)
```bash
# What happens (if enabled):
- Interactive Velero configuration
- S3-compatible storage setup
- Helm installation of Velero
- Backup schedule configuration
```

#### **Phase 15: Final Verification** (`lib/setup_check.sh`)
```bash
# What happens:
- Cluster readiness verification
- Addon status checks
- Network connectivity tests
- Storage functionality verification
- Complete system health check
```

---

## 🤖 Platform-Specific Configurations

### 🖥️ **Standard x86_64 Platform**

#### **Network Configuration**
- **CNI**: Calico (default MicroK8s CNI)
- **Load Balancer**: MetalLB with IP pool
- **DNS**: CoreDNS with external nameservers

#### **Storage Configuration**
- **Primary**: Longhorn distributed storage
- **Features**: Replication, snapshots, backup
- **Performance**: High availability, data protection

#### **Resource Allocation**
- **Conservative**: Assumes shared system resources
- **Scalable**: Can handle larger workloads
- **Flexible**: Supports various hardware configurations

### 🤖 **NVIDIA Jetson Platform**

> **⚠️ Important**: Jetson deployments are **single-node only** - no clustering or multi-node support

#### **Network Configuration**
- **CNI**: Flannel (ARM64 optimized, **NOT Calico**)
- **Optimization**: Host-gateway backend for WiFi reliability
- **Interface**: Intelligent ethernet/WiFi detection
- **Calico Removal**: Aggressive cleanup to prevent conflicts
- **Single-Node**: No multi-node clustering capabilities

#### **Storage Configuration**
- **Primary**: Hostpath provisioner (**NOT Longhorn**)
- **Optimization**: Single-node, local storage only
- **Performance**: Optimized for SD card limitations
- **No Distributed Storage**: Hostpath is local-only

#### **Resource Allocation**
- **Memory-Constrained**: Optimized for 4-8GB RAM
- **Edge-Optimized**: Minimal resource overhead
- **GPU-Aware**: Tegra GPU integration
- **Single-Node Focused**: All resources on one device

#### **Special Optimizations**
```bash
# Jetson-specific optimizations applied:
- Flannel host-gw backend for WiFi stability
- Aggressive Calico removal (prevents conflicts)
- Memory-optimized resource allocation
- SD card-friendly storage patterns
- Tegra GPU detection and configuration
- ARM64-specific container images
```

---

## 🌐 Network Configuration Details

### 🏠 **LAN Mode Configuration**
```bash
# What gets configured:
- MetalLB pool: Single machine IP (e.g., 192.168.1.100-192.168.1.100)
- Access: Local network only
- Domains: .local domains (ai.hostname.local)
- Certificates: mkcert for local HTTPS (optional)
- DNS: Local DNS resolution required
```

### 🌍 **Public Mode Configuration**

#### **Cloud Public Scenario** (IP assigned to machine)
```bash
# What gets configured:
- MetalLB pool: Public IP (e.g., 203.0.113.10-203.0.113.10)
- kube-apiserver: Bind to all interfaces, advertise public IP
- Access: Direct internet access
- Domains: Public domains with DNS records
- Certificates: Let's Encrypt automatic
```

#### **On-Premises Public Scenario** (IP on router/NAT)
```bash
# What gets configured:
- MetalLB pool: Public IP (e.g., 203.0.113.10-203.0.113.10)
- kube-apiserver: Bind to all interfaces, advertise local IP
- Access: Via router port forwarding
- Domains: Public domains with DNS records
- Certificates: Let's Encrypt automatic
- Optimization: Dual-IP configuration for NAT environments
```

### 🔧 **Remote Access Configuration**
When enabled, configures kube-apiserver for remote kubectl access:

```bash
# kube-apiserver configuration:
--bind-address=0.0.0.0                    # Listen on all interfaces
--advertise-address=<appropriate-ip>       # Cloud: public IP, On-prem: local IP
--secure-port=16443                       # Standard secure port

# kubeconfig configuration:
server: https://<external-ip>:16443       # External access endpoint
```

---

## 🔍 Verification & Testing

### ✅ **Post-Installation Checks**

#### **Cluster Status**
```bash
# Check MicroK8s status
sudo microk8s status --wait-ready

# Check all addons
sudo microk8s status

# Check cluster info
kubectl cluster-info
```

#### **Network Verification**
```bash
# Check MetalLB configuration
kubectl get configmap config -n metallb-system -o yaml

# Check ingress controller
kubectl get pods -n ingress

# Test external connectivity
kubectl run test-pod --image=busybox --rm -it -- ping google.com
```

#### **Storage Verification**
```bash
# Check storage classes
kubectl get storageclass

# Test PVC creation (Longhorn)
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn
EOF

# Check PVC status
kubectl get pvc test-pvc

# Cleanup
kubectl delete pvc test-pvc
```

#### **GPU Verification** (if available)
```bash
# Check GPU addon status
sudo microk8s status | grep gpu

# Test GPU access
kubectl run gpu-test --image=nvidia/cuda:11.0-base --rm -it -- nvidia-smi
```

### 🚨 **Common Issues & Solutions**

#### **DNS Issues**
```bash
# Symptom: ImagePullBackOff errors
# Solution: Check DNS configuration
nslookup google.com

# If DNS fails, reconfigure:
sudo systemctl restart systemd-resolved
# Or manually edit /etc/resolv.conf
```

#### **Jetson Flannel Issues**
```bash
# Symptom: Pods stuck in ContainerCreating
# Solution: Check Flannel status
sudo journalctl -u snap.microk8s.daemon-flanneld -n 50

# Verify Pod CIDR assignment
kubectl get nodes -o wide
kubectl describe node $(hostname)
```

#### **Storage Issues**
```bash
# Symptom: PVCs stuck in Pending
# Solution: Check storage backend
kubectl get pods -n longhorn-system  # For Longhorn
kubectl get pods -n kube-system | grep hostpath  # For Hostpath
```

---

## 🔧 Advanced Configuration

### 🎛️ **Custom Configuration Options**

#### **Manual MetalLB Pool**
```bash
# During setup, when prompted:
🌐 Proposed MetalLB pool (machine IP): 192.168.1.100-192.168.1.100. Confirm? [Y/n]: n
Enter manual MetalLB pool: 192.168.1.200-192.168.1.210
```

#### **Custom Hostname**
```bash
# During setup, when prompted:
📛 Enter new hostname [current-hostname]: my-lair-cluster
```

#### **Velero Configuration**
```bash
# When prompted for Velero:
Enable Velero backups? (y/n) [default: y]: y
📦 Bucket name: my-lair-backups
🌐 Storage endpoint URL: https://s3.region.provider.com
🗺️ Region code: us-east-1
🔑 Access Key: AKIAIOSFODNN7EXAMPLE
🔒 Secret Key: [hidden input]
```

### 🔧 **Post-Installation Customization**

#### **Add Additional Storage Classes**
```bash
# Create custom storage class
kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "1"
  staleReplicaTimeout: "30"
  fromBackup: ""
EOF
```

#### **Configure Additional Ingress**
```bash
# Add custom ingress rules
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: custom-ingress
  namespace: default
spec:
  ingressClassName: public
  rules:
  - host: custom.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: custom-service
            port:
              number: 80
EOF
```

---

## 🔄 Next Steps

After successful MicroK8s installation:

1. **✅ Verify Installation**: Run all verification checks above
2. **📦 Deploy Applications**: Proceed to [Helm Chart Deployment](../helm-chart/README.md)
3. **🔧 Configure Access**: Set up [Access Modes](../../configuration/access-modes/README.md)
4. **🔐 Setup Certificates**: Configure [TLS Certificates](../../configuration/certificates/README.md)
5. **📊 Monitor System**: Set up [Monitoring](../../maintenance/monitoring/README.md)

---

**🎯 Ready for applications?** Continue with [Helm Chart Deployment Guide](../helm-chart/README.md)
