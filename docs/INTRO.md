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
- **[MicroK8s Installation](installation/microk8s/README.md)** - Kubernetes cluster setup (single-node and multi-node)
  - [Prerequisites & Requirements](installation/microk8s/prerequisites.md)
  - [Single-Node Setup](installation/microk8s/single-node-setup.md)
  - [Multi-Node Setup](installation/microk8s/multi-node-setup.md)
  - [Network Configuration](installation/microk8s/network-config.md)
  - [Platform-Specific Setup](installation/microk8s/platform-specific.md)
  - [Jetson Optimization](installation/microk8s/jetson-setup.md)

- **[Managed Kubernetes Setup](installation/managed-k8s/README.md)** - Deploy on existing clusters
  - [Prerequisites & Requirements](installation/managed-k8s/prerequisites.md)
  - [Component Installation](installation/managed-k8s/components.md)
  - [Cloud Provider Guides](installation/managed-k8s/cloud-providers.md)

#### Application Deployment
- **[Helm Chart Deployment](installation/helm-chart/README.md)** - Lair application deployment
  - [Configuration Generation](installation/helm-chart/configuration.md)
  - [Resource Planning](installation/helm-chart/resource-planning.md)
  - [Deployment Options](installation/helm-chart/deployment-options.md)

### 🧩 **Components**
Detailed documentation for each system component.

#### Cluster Components
- **[Kubernetes Cluster](components/cluster/README.md)** - Core cluster functionality
  - [MicroK8s Configuration](components/cluster/microk8s.md)
  - [Addon Management](components/cluster/addons.md)
  - [Remote Access](components/cluster/remote-access.md)

- **[Networking](components/networking/README.md)** - Network configuration and management
  - [CNI Configuration](components/networking/cni.md)
  - [Ingress Controllers](components/networking/ingress.md)
  - [MetalLB Load Balancer](components/networking/metallb.md)
  - [DNS Configuration](components/networking/dns.md)

- **[Storage](components/storage/README.md)** - Storage solutions and management
  - [Longhorn Distributed Storage](components/storage/longhorn.md)
  - [Hostpath Storage (Jetson)](components/storage/hostpath.md)
  - [Storage Classes](components/storage/storage-classes.md)
  - [Persistent Volumes](components/storage/persistent-volumes.md)

- **[Backup & Disaster Recovery](components/backup/README.md)** - Data protection with Velero
  - [Velero Configuration](components/backup/velero-setup.md)
  - [Backup Strategies](components/backup/backup-strategies.md)
  - [Restore Procedures](components/backup/restore-procedures.md)

#### Application Components
- **[Applications Overview](components/applications/README.md)** - All Lair applications
  - [OpenWebUI](components/applications/openwebui.md) - AI Chat Interface
  - [N8N](components/applications/n8n.md) - Workflow Automation
  - [Ollama](components/applications/ollama.md) - LLM Serving Platform
  - [ComfyUI](components/applications/comfyui.md) - AI Image Generation
  - [MinIO](components/applications/minio.md) - Object Storage
  - [Tika](components/applications/tika.md) - Document Processing
  - [PostgreSQL](components/applications/postgresql.md) - Database
  - [Redis](components/applications/redis.md) - Cache & Queue

### ⚙️ **Configuration**
Configuration guides for different aspects of the system.

- **[Access Modes](configuration/access-modes/README.md)** - LAN vs Public access configuration
  - [LAN Access (.local domains)](configuration/access-modes/lan-access.md)
  - [Public Access (internet domains)](configuration/access-modes/public-access.md)
  - [Dual Access Configuration](configuration/access-modes/dual-access.md)

- **[Certificates & Security](configuration/certificates/README.md)** - TLS and security configuration
  - [Let's Encrypt (Public)](configuration/certificates/letsencrypt.md)
  - [mkcert (LAN)](configuration/certificates/mkcert.md)
  - [Certificate Management](configuration/certificates/management.md)

- **[Resource Management](configuration/resources/README.md)** - CPU, memory, and storage allocation
  - [Resource Detection](configuration/resources/detection.md)
  - [Allocation Strategies](configuration/resources/allocation.md)
  - [Platform Optimization](configuration/resources/optimization.md)

- **[Advanced Configuration](configuration/advanced/README.md)** - Advanced setup options
  - [Multi-Environment Setup](configuration/advanced/multi-environment.md)
  - [Custom Configurations](configuration/advanced/custom-configs.md)
  - [Integration Patterns](configuration/advanced/integration-patterns.md)

### 🔧 **Maintenance & Operations**
Ongoing maintenance, updates, and operational procedures.

- **[Updates & Upgrades](maintenance/updates/README.md)** - Keeping the system current
  - [Component Updates](maintenance/updates/component-updates.md)
  - [Application Updates](maintenance/updates/application-updates.md)
  - [Security Updates](maintenance/updates/security-updates.md)

- **[Backup & Restore](maintenance/backup-restore/README.md)** - Data protection procedures
  - [Backup Procedures](maintenance/backup-restore/backup-procedures.md)
  - [Restore Procedures](maintenance/backup-restore/restore-procedures.md)
  - [Disaster Recovery](maintenance/backup-restore/disaster-recovery.md)

- **[Monitoring & Health](maintenance/monitoring/README.md)** - System monitoring and health checks
  - [Health Monitoring](maintenance/monitoring/health-monitoring.md)
  - [Performance Monitoring](maintenance/monitoring/performance.md)
  - [Log Management](maintenance/monitoring/log-management.md)

- **[Cleanup & Maintenance](maintenance/cleanup/README.md)** - System cleanup and maintenance
  - [Regular Maintenance](maintenance/cleanup/regular-maintenance.md)
  - [Storage Cleanup](maintenance/cleanup/storage-cleanup.md)
  - [Complete Removal](maintenance/cleanup/complete-removal.md)

### 🔍 **Troubleshooting**
Problem diagnosis and resolution guides.

- **[Common Issues](troubleshooting/common-issues/README.md)** - Frequently encountered problems
  - [Installation Issues](troubleshooting/common-issues/installation.md)
  - [Network Issues](troubleshooting/common-issues/network.md)
  - [Storage Issues](troubleshooting/common-issues/storage.md)
  - [Application Issues](troubleshooting/common-issues/applications.md)

- **[Platform-Specific Issues](troubleshooting/platform-specific/README.md)** - Platform-specific problems
  - [Jetson Issues](troubleshooting/platform-specific/jetson.md)
  - [Cloud Platform Issues](troubleshooting/platform-specific/cloud.md)
  - [Network Configuration Issues](troubleshooting/platform-specific/network.md)

- **[Debugging Tools](troubleshooting/debugging/README.md)** - Diagnostic tools and procedures
  - [Log Analysis](troubleshooting/debugging/log-analysis.md)
  - [Network Debugging](troubleshooting/debugging/network-debugging.md)
  - [Resource Debugging](troubleshooting/debugging/resource-debugging.md)

---

## 🚀 Quick Navigation

### 🎯 **New Users - Start Here**
1. **[Architecture Overview](architecture/README.md)** - Understand the system
2. **[Installation Requirements](installation/microk8s/README.md)** - Check prerequisites
3. **[Single-Node Setup](installation/microk8s/README.md#single-node-installation)** - Install your first cluster
4. **[Application Deployment](installation/helm-chart/README.md)** - Deploy Lair applications

### 🔧 **System Administrators**
1. **[Multi-Node Setup](installation/microk8s/README.md#multi-node-cluster-setup)** - Scale to production
2. **[Resource Planning](installation/helm-chart/resource-planning.md)** - Plan your deployment
3. **[Network Configuration](components/networking/README.md)** - Configure networking
4. **[Backup Setup](components/backup/README.md)** - Configure backups
5. **[Monitoring Setup](maintenance/monitoring/README.md)** - Monitor your system

### 🏢 **Enterprise Users**
1. **[Multi-Node Architecture](installation/microk8s/README.md#multi-node-architecture)** - High availability setup
2. **[Managed K8s Setup](installation/managed-k8s/README.md)** - Deploy on existing clusters
3. **[Advanced Configuration](configuration/advanced/README.md)** - Enterprise features
4. **[Multi-Environment](configuration/advanced/README.md#multi-environment-setup)** - Multiple environments
5. **[Disaster Recovery](maintenance/backup-restore/README.md)** - Enterprise DR

### 🤖 **Edge Computing (Jetson)**
> **Note**: Jetson deployments are **single-node only** with Flannel CNI and Hostpath storage

1. **[Jetson Prerequisites](installation/microk8s/prerequisites.md)** - Jetson-specific requirements
2. **[Jetson Setup Guide](installation/microk8s/jetson-setup.md)** - Single-node Jetson installation
3. **[Jetson Troubleshooting](troubleshooting/platform-specific/jetson.md)** - Jetson-specific issues
4. **[Edge Optimization](configuration/resources/optimization.md)** - Single-node edge optimization

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

**📖 Happy reading! If you need help, check our [Troubleshooting](troubleshooting/README.md) section or open an issue.**
