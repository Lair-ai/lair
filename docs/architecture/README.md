# 🏗️ Lair Architecture Overview

> **Complete system architecture and component relationships in the Lair private AI infrastructure**

Lair is built on a **four-layer architecture** that provides a complete private AI infrastructure stack. From Kubernetes cluster management to AI applications, everything is designed for ease of deployment, security, and scalability.

## 🎯 **What You'll Learn**
- **Complete system architecture** from infrastructure to applications
- **Component relationships** and how they integrate
- **Platform-specific optimizations** (x86_64, Jetson, Cloud)
- **Resource allocation strategies** for optimal performance
- **Deployment patterns** and configuration management

---

## 🏗️ **Four-Layer Architecture**

Lair's architecture is designed as a **complete private AI infrastructure stack** with four distinct layers:

```
┌─────────────────────────────────────────────────────────────────┐
│                       🌐 ACCESS LAYER                            │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   LAN Access    │  │  Public Access  │  │   API Access    │  │
│  │  (.local TLS)   │  │ (Let's Encrypt) │  │ (Internal APIs) │  │
│  │ ai.host.local │  │ ai.domain.com │  │ kubectl/helm    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                    🤖 AI APPLICATION LAYER                       │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │  OpenWebUI  │ │     N8N     │ │   ComfyUI   │ │   MinIO   │  │
│  │ (AI Chat)   │ │(Automation) │ │ (AI Images) │ │ (Storage) │  │
│  │   + RAG     │ │ 400+ APIs   │ │ Stable Diff │ │ S3 API    │  │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘  │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │   Ollama    │ │    Tika     │ │ PostgreSQL  │ │   Redis   │  │
│  │ (LLM Server)│ │(Doc Extract)│ │ (Database)  │ │  (Cache)  │  │
│  │ Local Models│ │ PDF/Office  │ │ Multi-tenant│ │ Bull Queue│  │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                    🔧 INFRASTRUCTURE LAYER                      │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │   Ingress   │ │   Storage   │ │ Cert-Manager│ │  Backup   │  │
│  │  (NGINX)    │ │ (Longhorn)  │ │(Let's Encr.)│ │ (Velero)  │  │
│  │ TLS + Route │ │ Distributed │ │ Auto Certs  │ │ S3 Backup │  │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘  │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌───────────┐  │
│  │   Network   │ │   MetalLB   │ │     DNS     │ │    GPU    │  │
│  │ (Calico/    │ │(LoadBalancer│ │ (CoreDNS)   │ │ (NVIDIA)  │  │
│  │  Flannel)   │ │ Local IPs   │ │ Service Disc│ │ Tegra/RTX │  │
│  └─────────────┘ └─────────────┘ └─────────────┘ └───────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                       🖥️ PLATFORM LAYER                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   MicroK8s      │  │  Managed K8s    │  │   Hardware      │  │
│  │ (Local Cluster) │  │ (EKS/GKE/AKS)   │  │ (x86/ARM/GPU)   │  │
│  │ Single/Multi    │  │ Enterprise      │  │ Ubuntu 24.04    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 🎯 **Layer Responsibilities**

| Layer | Purpose | Key Components | Platform Variations |
|-------|---------|----------------|-------------------|
| **🌐 Access** | External connectivity | Ingress, TLS, DNS | LAN (.local) vs Public domains |
| **🤖 AI Apps** | AI functionality | OpenWebUI, Ollama, N8N, ComfyUI | Resource allocation varies |
| **🔧 Infrastructure** | K8s services | Storage, Network, Certs, Backup | Longhorn vs Hostpath, Calico vs Flannel |
| **🖥️ Platform** | Foundation | Kubernetes cluster | MicroK8s vs Managed, x86 vs ARM64 |

---

## 🧩 Component Architecture

### 🎯 **Three Main Components**

Lair consists of three main components that work together:

#### 1. **🔧 Cluster Setup** (`microk8s/` or `k8s-managed/`)
**Purpose**: Prepare and configure the Kubernetes cluster infrastructure

**MicroK8s Path** (`microk8s/`):
- **Target**: Single-node local deployments, edge computing, development
- **Installs**: Complete MicroK8s cluster with all required addons
- **Optimizes**: Platform-specific configurations (Jetson, x86_64)
- **Configures**: Networking, storage, ingress, certificates, backup

**Managed K8s Path** (`k8s-managed/`):
- **Target**: Existing Kubernetes clusters (EKS, GKE, AKS, etc.)
- **Installs**: Required components (Longhorn, Ingress-NGINX, Cert-Manager)
- **Assumes**: Cluster already exists and is accessible
- **Configures**: Additional components needed for Lair applications

#### 2. **📦 Application Deployment** (`helm-chart/`)
**Purpose**: Deploy and configure all Lair applications

- **Interactive Configuration**: Guided setup with resource detection
- **Resource Management**: Intelligent allocation based on available resources
- **Multi-Access**: LAN and Public access configuration
- **Component Selection**: Enable/disable services based on needs

#### 3. **🌐 Access & Integration**
**Purpose**: Provide secure access to applications and APIs

- **LAN Access**: `.local` domains with optional HTTPS via mkcert
- **Public Access**: Internet domains with automatic Let's Encrypt certificates
- **API Integration**: Internal APIs for custom integrations
- **Security**: TLS termination, authentication, authorization

---

## 🔄 Installation Flows

### 🏠 **Local MicroK8s Flow**
```
1. Prerequisites Check → 2. MicroK8s Install → 3. Addons Setup → 4. App Deploy
   ├─ OS Compatibility     ├─ Snap Installation   ├─ Ingress (NGINX)   ├─ Resource Detection
   ├─ Network Config       ├─ Cluster Init        ├─ Storage (Longhorn) ├─ Component Config
   ├─ DNS Setup           ├─ Remote Access       ├─ Cert-Manager      ├─ YAML Generation
   └─ Resource Check      └─ GPU Detection       ├─ MetalLB           └─ Helm Deployment
                                                 └─ Velero (optional)
```

### ☁️ **Managed K8s Flow**
```
1. Prerequisites Check → 2. Component Install → 3. App Deploy
   ├─ Cluster Access       ├─ Helm OS Install    ├─ Resource Detection
   ├─ Permissions         ├─ Longhorn Storage   ├─ Component Config
   ├─ Network Config      ├─ Ingress-NGINX      ├─ YAML Generation
   └─ Resource Check      ├─ Cert-Manager       └─ Helm Deployment
                          └─ Velero (optional)
```

---

## 🏗️ Platform-Specific Architectures

> **⚠️ Important Platform Requirements:**
> - **✅ Supported**: Ubuntu 24.04 LTS (native installation only)
> - **❌ NOT Supported**: Windows (including WSL2, WSL, or any Windows emulation)
> - **🤖 Jetson Limitation**: Single-node only with Flannel CNI and Hostpath storage

### 🖥️ **Standard x86_64 Architecture**
```
┌─────────────────────────────────────────────────────────────┐
│                    Standard Platform                        │
├─────────────────────────────────────────────────────────────┤
│ Network: Calico CNI (default)                             │
│ Storage: Longhorn Distributed Storage                     │
│ GPU: Optional NVIDIA GPU support                          │
│ LoadBalancer: MetalLB with IP pool                        │
│ Ingress: NGINX Ingress Controller                         │
│ Certificates: Let's Encrypt (public) + mkcert (LAN)       │
│ Backup: Velero with S3-compatible storage                 │
└─────────────────────────────────────────────────────────────┘
```

### 🤖 **NVIDIA Jetson Architecture**
```
┌─────────────────────────────────────────────────────────────┐
│                    Jetson Platform                         │
├─────────────────────────────────────────────────────────────┤
│ Network: Flannel CNI (ARM64 optimized)                    │
│ Storage: Hostpath Provisioner (SD card optimized)         │
│ GPU: Tegra GPU with CUDA acceleration                     │
│ LoadBalancer: MetalLB with single IP                      │
│ Ingress: NGINX Ingress Controller                         │
│ Certificates: mkcert for .local domains                   │
│ Backup: Velero with S3-compatible storage                 │
│ Optimization: Memory-constrained resource allocation       │
└─────────────────────────────────────────────────────────────┘
```

### ☁️ **Cloud Platform Architecture**
```
┌─────────────────────────────────────────────────────────────┐
│                   Cloud Platform                           │
├─────────────────────────────────────────────────────────────┤
│ Network: Cloud CNI (EKS/GKE/AKS native)                   │
│ Storage: Cloud Storage Classes + Longhorn                 │
│ GPU: Cloud GPU instances (optional)                       │
│ LoadBalancer: Cloud LoadBalancer + MetalLB                │
│ Ingress: NGINX Ingress Controller                         │
│ Certificates: Let's Encrypt with DNS challenges           │
│ Backup: Velero with cloud-native storage                  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔗 Component Integration

### 🌐 **Network Integration**
```
Internet/LAN → MetalLB → NGINX Ingress → Services → Pods
                 ↓
              External IP
                 ↓
         ┌─────────────────┐
         │  Ingress Rules  │
         │  ├─ ai.*        │ → OpenWebUI Service
         │  ├─ n8n.*       │ → N8N Service  
         │  ├─ images.*    │ → ComfyUI Service
         │  └─ storage.*   │ → MinIO Service
         └─────────────────┘
```

### 💾 **Storage Integration**
```
Applications → PersistentVolumeClaims → StorageClass → Storage Backend
     ↓                    ↓                 ↓              ↓
OpenWebUI PVC → lair-storage → Longhorn → Distributed Storage
N8N PVC       → lair-storage → Longhorn → Distributed Storage
Ollama PVC    → lair-storage → Longhorn → Distributed Storage
     ↓                    ↓                 ↓              ↓
(Jetson)      → lair-hostpath → Hostpath → Local Storage
```

### 🔐 **Certificate Integration**
```
Cert-Manager → ClusterIssuer → Certificate → Secret → Ingress TLS
     ↓              ↓              ↓           ↓         ↓
Let's Encrypt → lair-letsencrypt → Auto Cert → TLS Secret → HTTPS
     ↓              ↓              ↓           ↓         ↓
mkcert (LAN)  → Manual Process → Manual Cert → lair-tls-local → HTTPS
```

### 🔄 **Backup Integration**
```
Velero → BackupStorageLocation → S3 Storage
  ↓           ↓                      ↓
Schedule → Namespace Backup → Encrypted Backup
  ↓           ↓                      ↓
Daily    → lair namespace    → Cloud Storage
```

---

## 📊 Resource Architecture

### 🧠 **Resource Allocation Strategy**
```
Total System Resources (100%)
├─ System Reserved (20%)
├─ Kubernetes System (10-20%)
└─ Application Resources (60-70%)
    ├─ OpenWebUI (25%)
    ├─ Ollama (35%)
    ├─ N8N + Workers (10%)
    ├─ ComfyUI (20%) [optional]
    ├─ PostgreSQL (5%)
    ├─ Redis (3%)
    └─ MinIO (7%) [optional]
```

### 💾 **Storage Allocation Strategy**
```
Total Available Storage (100%)
├─ System Reserved (20%)
└─ Application Storage (80%)
    ├─ Ollama Models (40-50%)
    ├─ OpenWebUI Data (15-20%)
    ├─ ComfyUI Models (15-20%) [optional]
    ├─ N8N Workflows (10%)
    ├─ MinIO Objects (10-15%) [optional]
    ├─ PostgreSQL Data (5%)
    └─ Redis Cache (2-3%)
```

---

## 🔧 Configuration Architecture

### 📝 **Configuration Hierarchy**
```
1. Base Configuration (values.yaml)
   ├─ Safe defaults for all components
   ├─ Conservative resource allocation
   └─ Disabled optional components

2. Platform Configuration (generated)
   ├─ Platform-specific optimizations
   ├─ Resource detection results
   └─ Network configuration

3. User Configuration (values-custom.yaml)
   ├─ User-specific settings
   ├─ Domain configuration
   ├─ Component selection
   └─ Resource overrides

4. Runtime Configuration (Kubernetes)
   ├─ Secrets and ConfigMaps
   ├─ Environment variables
   └─ Dynamic configuration
```

### 🎛️ **Configuration Generation Flow**
```
System Detection → Resource Calculation → Component Configuration → YAML Generation
       ↓                    ↓                      ↓                    ↓
   CPU/Memory/GPU    →  Allocation %     →    Service Configs   →   values-*.yaml
   Platform Type     →  Storage Size     →    Domain Setup     →   Helm Values
   Network Config    →  Replica Count    →    Access Mode      →   Ready to Deploy
```

---

## 🚀 Deployment Patterns

### 🏠 **Single-Node Deployment** (Current)
```
┌─────────────────────────────────────────────────────────────┐
│                    Single Node                             │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐          │
│  │ Control     │ │ Worker      │ │ Storage     │          │
│  │ Plane       │ │ Workloads   │ │ Backend     │          │
│  │ (MicroK8s)  │ │ (All Apps)  │ │ (Longhorn)  │          │
│  └─────────────┘ └─────────────┘ └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### 🏢 **Multi-Node Deployment** (Future)
```
┌─────────────────────────────────────────────────────────────┐
│                   Multi-Node Cluster                       │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐          │
│  │   Master    │ │   Worker 1  │ │   Worker 2  │          │
│  │ Control     │ │ AI Workloads│ │ Data Layer  │          │
│  │ Plane       │ │ (Ollama,    │ │ (PostgreSQL,│          │
│  │ (etcd, API) │ │  ComfyUI)   │ │  MinIO)     │          │
│  └─────────────┘ └─────────────┘ └─────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔍 Monitoring & Observability

### 📊 **Built-in Monitoring**
```
Application Level:
├─ Health Checks (Kubernetes Probes)
├─ Resource Metrics (CPU, Memory, Storage)
└─ Application Logs (kubectl logs)

Infrastructure Level:
├─ Cluster Status (microk8s status)
├─ Node Resources (kubectl top nodes)
├─ Storage Health (Longhorn UI)
└─ Network Status (MetalLB, Ingress)

Backup Level:
├─ Backup Status (Velero)
├─ Backup Schedules
└─ Restore Capabilities
```

### 🚨 **Health Indicators**
```
🟢 Healthy: All components running, resources available
🟡 Warning: High resource usage, some components degraded
🔴 Critical: Component failures, resource exhaustion
⚫ Unknown: Monitoring unavailable, network issues
```

---

## 🔮 Future Architecture Evolution

### 📈 **Planned Enhancements**
1. **Multi-Node Support**: High availability across multiple nodes
2. **Central Management**: Unified dashboard for all components
3. **Advanced Monitoring**: Prometheus + Grafana integration
4. **Service Mesh**: Istio for advanced networking and security
5. **GitOps Integration**: ArgoCD for declarative deployments

### 🎯 **Scalability Roadmap**
```
Current: Single-Node → Near-term: Multi-Node → Long-term: Cloud-Native
    ↓                      ↓                        ↓
Edge/Development    →  Enterprise HA         →  Hyperscale
Simple Setup       →  Advanced Features     →  Full Automation
Manual Config      →  GitOps Integration    →  AI-Driven Ops
```

---

**🎯 Next Steps**: Explore specific components in the [Components Documentation](../components/README.md) or dive into [Installation Guides](../installation/README.md).
