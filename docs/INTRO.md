# 📚 Lair Documentation

> **Comprehensive documentation for Lair - Private AI Infrastructure & Process Automation Platform**

This documentation covers the complete Lair ecosystem, from cluster setup to application deployment and maintenance.

## ⚠️ **Important Prerequisites**

### 🖥️ **Operating System Requirements**
- **✅ Supported**: Ubuntu 24.04 LTS (native installation only)
- **❌ NOT Supported**: Windows (including WSL2, WSL, or any Windows emulation layer)
- **❌ NOT Supported**: Other Linux distributions (may work but not tested/supported)

### 🤖 **NVIDIA Jetson Limitations**
- **Single-Node Only**: Jetson devices support **single-node deployments only**
- **Flannel CNI**: Uses Flannel networking (NOT Calico) optimized for ARM64
- **Hostpath Storage**: Uses local Hostpath storage (NOT Longhorn distributed storage)
- **No Clustering**: Cannot be part of multi-node Kubernetes clusters

---

## 📖 Documentation Structure

### 🏗️ **Architecture & Overview**
Understanding the complete Lair ecosystem and how components work together.

- **[Architecture Overview](architecture/README.md)** - Complete system architecture and component relationships

### 🛠️ **Installation & Setup**
Step-by-step guides for different deployment scenarios.

#### Cluster Setup
- **[MicroK8s Installation](installation/microk8s-setup.md)** - Kubernetes cluster setup (single-node and multi-node)
  - [Prerequisites & Requirements](installation/requirements.md)
  - [Single-Node Setup](installation/microk8s-setup.md)
  - [Multi-Node Setup](installation/microk8s-setup.md)
  - [Network Configuration](installation/microk8s-setup.md)
  - [Platform-Specific Setup](installation/microk8s-setup.md)
  - [Jetson Optimization](installation/microk8s-setup.md)

- **[Managed Kubernetes Setup](installation/managed-k8s-setup.md)** - Deploy on existing clusters
  - [Prerequisites & Requirements](installation/requirements.md)
  - [Component Installation](installation/managed-k8s-setup.md)
  - [Cloud Provider Guides](installation/managed-k8s-setup.md)

#### Application Deployment
- **[Helm Chart Deployment](installation/helm-chart-setup.md)** - Lair application deployment
  - [Configuration Generation](installation/helm-chart-setup.md)
  - [Resource Planning](installation/helm-chart-setup.md)
  - [Deployment Options](installation/helm-chart-setup.md)

### 🧩 **Components**
Detailed documentation for each system component.

#### Cluster Components
- **[Kubernetes Cluster](components/cluster.md)** - Core cluster functionality
  - [MicroK8s Configuration](components/cluster.md)
  - [Addon Management](components/cluster.md)
  - [Remote Access](components/cluster.md)

- **[Networking](components/networking.md)** - Network configuration and management
  - [CNI Configuration](components/networking.md)
  - [Ingress Controllers](components/networking.md)
  - [MetalLB Load Balancer](components/networking.md)
  - [DNS Configuration](components/networking.md)

- **[Storage](components/storage.md)** - Storage solutions and management
  - [Longhorn Distributed Storage](components/storage.md)
  - [Hostpath Storage (Jetson)](components/storage.md)
  - [Storage Classes](components/storage.md)
  - [Persistent Volumes](components/storage.md)

- **[Backup & Disaster Recovery](components/backup.md)** - Data protection with Velero
  - [Velero Configuration](components/backup.md)
  - [Backup Strategies](components/backup.md)
  - [Restore Procedures](components/backup.md)

#### Application Components
- **[Applications Overview](components/services-overview.md)** - All Lair applications
  - [OpenWebUI](components/applications/openwebui.md) - AI Chat Interface
  - [N8N](components/applications/n8n.md) - Workflow Automation
  - [Ollama](components/applications/ollama.md) - LLM Serving Platform
  - [ComfyUI](components/applications/comfyui.md) - AI Image Generation
  - [MinIO](components/applications/minio.md) - Object Storage
  - [Tika](components/services-overview.md) - Document Processing
  - [PostgreSQL](components/services-overview.md) - Database
  - [Redis](components/services-overview.md) - Cache & Queue

### ⚙️ **Configuration**
Configuration guides for different aspects of the system.

- **[Network & Access](configuration/network-access.md)** - LAN vs Public access configuration

- **[Certificates & Security](configuration/security-certificates.md)** - TLS and security configuration

- **[Storage & Resources](configuration/storage-resources.md)** - Resource and storage configuration

- **[Advanced Configuration](configuration/advanced-configuration.md)** - Advanced setup options

### 🔧 **Maintenance & Operations**
Ongoing maintenance, updates, and operational procedures.

- **[Updates & Upgrades](maintenance/updates.md)** - Keeping the system current
  - [Component Updates](maintenance/updates.md)
  - [Application Updates](maintenance/updates.md)
  - [Security Updates](maintenance/updates.md)

- **[Backup & Restore](maintenance/backup-restore.md)** - Data protection procedures
  - [Backup Procedures](maintenance/backup-restore.md)
  - [Restore Procedures](maintenance/backup-restore.md)
  - [Disaster Recovery](maintenance/backup-restore.md)

- **[Monitoring & Health](maintenance/monitoring.md)** - System monitoring and health checks
  - [Health Monitoring](maintenance/monitoring.md)
  - [Performance Monitoring](maintenance/monitoring.md)
  - [Log Management](maintenance/monitoring.md)

- **[Cleanup & Maintenance](maintenance/cleanup.md)** - System cleanup and maintenance
  - [Regular Maintenance](maintenance/cleanup.md)
  - [Storage Cleanup](maintenance/cleanup.md)
  - [Complete Removal](maintenance/cleanup.md)

### 🔍 **Troubleshooting**
Problem diagnosis and resolution guides.

- **[Common Issues](troubleshooting/common-issues.md)** - Frequently encountered problems

- **[Platform-Specific Issues](troubleshooting/platform-specific.md)** - Platform-specific problems

- **[Debugging Tools](troubleshooting/debugging.md)** - Diagnostic tools and procedures

---

## 🚀 Quick Navigation

### 🎯 **New Users - Start Here**
1. **[Architecture Overview](architecture/README.md)** - Understand the system
2. **[Installation Requirements](installation/microk8s-setup.md)** - Check prerequisites
3. **[Single-Node Setup](installation/microk8s-setup.md#single-node-installation)** - Install your first cluster
4. **[Application Deployment](installation/helm-chart-setup.md)** - Deploy Lair applications

### 🔧 **System Administrators**
1. **[Multi-Node Setup](installation/microk8s-setup.md#multi-node-cluster-setup)** - Scale to production
2. **[Resource Planning](installation/helm-chart-setup.md)** - Plan your deployment
3. **[Network Configuration](components/networking.md)** - Configure networking
4. **[Backup Setup](components/backup.md)** - Configure backups
5. **[Monitoring Setup](maintenance/monitoring.md)** - Monitor your system

### 🏢 **Enterprise Users**
1. **[Multi-Node Architecture](installation/microk8s-setup.md#multi-node-architecture)** - High availability setup
2. **[Managed K8s Setup](installation/managed-k8s-setup.md)** - Deploy on existing clusters
3. **[Advanced Configuration](configuration/advanced-configuration.md)** - Enterprise features
4. **[Multi-Environment](configuration/advanced-configuration.md#multi-environment-setup)** - Multiple environments
5. **[Disaster Recovery](maintenance/backup-restore.md)** - Enterprise DR

### 🤖 **Edge Computing (Jetson)**
> **Note**: Jetson deployments are **single-node only** with Flannel CNI and Hostpath storage

1. **[Jetson Prerequisites](installation/requirements.md)** - Jetson-specific requirements
2. **[Jetson Setup Guide](installation/microk8s-setup.md)** - Single-node Jetson installation
3. **[Jetson Troubleshooting](troubleshooting/platform-specific.md)** - Jetson-specific issues
4. **[Edge Optimization](configuration/advanced-configuration.md)** - Single-node edge optimization

---

## 📝 Documentation Conventions

### 🎯 **Symbols & Indicators**
- **✅** - Recommended or confirmed working
- **⚠️** - Important warning or limitation
- **🔧** - Configuration required
- **📋** - Prerequisites or requirements
- **🚀** - Performance optimization
- **🔒** - Security consideration

### 💻 **Code Blocks**
```bash
# Commands to run as root/sudo
sudo command-here

# Commands to run as regular user
kubectl get pods

# File content examples
# /path/to/file
content here
```

### 📁 **File Paths**
- **Absolute paths**: `/Users/user/lair/component/file`
- **Relative paths**: `./component/file` (from project root)
- **Config files**: `values-config.yaml`, `lair-config-template.yaml`

---

## 🤝 Contributing to Documentation

We welcome contributions to improve this documentation!

### 📝 **How to Contribute**
1. **Fork the repository**
2. **Create a documentation branch**: `git checkout -b docs/improve-section`
3. **Make your changes** following our style guide
4. **Test your changes** on a real system
5. **Submit a pull request**

### 📋 **Style Guide**
- **Clear headings** with emoji indicators
- **Step-by-step procedures** with numbered lists
- **Code examples** with proper syntax highlighting
- **Screenshots** for complex UI procedures
- **Cross-references** to related documentation

---

**📖 Happy reading! If you need help, check our [Troubleshooting](troubleshooting/common-issues.md) section or open an issue.**
