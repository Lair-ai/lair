# Lair — Private AI Infrastructure & Process Automation Platform

> **Complete private AI infrastructure with automated process management on Kubernetes**

[![License: GPL v3](https://img.shields.io/badge/License-GPL3.0-yellow.svg)](https://opensource.org/license/gpl-3.0)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%2024.04-orange.svg)]()
[![Kubernetes](https://img.shields.io/badge/Kubernetes-MicroK8s%201.32-blue.svg)]()
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)
[![GitHub Issues](https://img.shields.io/github/issues/Lair-ai/lair)](https://github.com/Lair-ai/lair/issues)
[![GitHub Stars](https://img.shields.io/github/stars/Lair-ai/lair?style=social)](https://github.com/Lair-ai/lair/stargazers)

**Created by [NEXiD s.r.l.](https://www.nexid.it)** 

---

## Table of Contents

- [What is Lair?](#what-is-lair)
- [Architecture Overview](#architecture-overview)
- [Quick Start](#quick-start)
- [Installation Paths](#installation-paths)
- [Edge AI & DGX Spark](#edge-ai--desktop-supercomputing-nvidia-jetson--dgx-spark)
- [Use Case Examples](#use-case-examples)
- [Platform Support & Smart Features](#platform-support--smart-features)
- [Quick Commands](#quick-commands)
- [Current Limitations](#current-limitations)
- [Roadmap](#future-roadmap)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [Code of Conduct](#code-of-conduct)
- [Security](#security)
- [Support & Community](#support--community)
- [License](#license)
- [About](#about)
- [Acknowledgements](#acknowledgements)

---

## What is Lair?

Lair enables organizations to deploy **private AI infrastructure** with comprehensive **process automation capabilities** on Kubernetes. The default architecture is fully self-hosted for data sovereignty and control; optional external AI providers can be enabled when needed.

### Key Use Cases

- **Private AI Infrastructure**: Run LLMs, AI models, and ML workloads on your machine or with the AI providers of your choice
- **Company Authentication integration**: Integrate with your company's authentication system (e.g., SingleSignOn with Azure AD, Google, OIDC)
- **Business Process Automation**: Workflow orchestration with a locally installed N8N and custom integrations
- **Data Privacy Compliance**: RAG, documents, files, knowledge bases are stored locally, no data leaves your infrastructure
- **Enterprise Integration**: Add AI capabilities to existing business systems using FastAPI and N8N
- **Edge & Desktop AI**: Complete AI infrastructure on NVIDIA Jetson devices or a DGX Spark workstation — production-grade workflows at the edge and on the desk
- **Backend for vibecoding**: by using a DGX Spark you can run an open‑source model (such as *Qwen3-Next-Coder*) and use it as a backend for vibecoding, without the hassle of tokens or time‑limited subscriptions, and your code and data remain on your device

### What You See

Users get:

- a **chat interface** with multiple features and customization options (powered by *OpenWebUI*)
- the ability to choose between **local models** (via *Ollama*) and **open‑source AI providers** (e.g. OVH AI Endpoints)
- the option to use major **cloud AI providers** (such as ChatGPT, Claude, Gemini) via API, without user profiling and with the ability to prevent data from being used for training
- the ability to **upload documents** and use them as context for conversations (powered by *Tika*)
- local **image generation** (powered by *ComfyUI*, when a GPU is available)
- a no‑code interface to **build and automate workflows** (powered by *N8N*)

### What You Get

#### Applications

| Component | Purpose | Default Access |
|-----------|---------|----------------|
| **OpenWebUI** | Private ChatGPT-like interface with RAG and extended features | `ai.hostname.local` |
| **N8N** | Workflow automation and API orchestration | `n8n.hostname.local` |
| **Ollama** | Local LLM serving platform | Internal API |
| **Tika** | Document processing and text extraction | Internal API |
| **ComfyUI** | AI image generation interface | `images.hostname.local` |
| **MinIO** | S3-compatible object storage | `storage.hostname.local` |
| **PostgreSQL** | Database backend for OpenWebUI and N8N | Internal API |
| **Redis** | Cache/queue backend for OpenWebUI and N8N | Internal API |

#### Cluster Infrastructure

| Component | Purpose | Default Access |
|-----------|---------|----------------|
| **ingress-nginx** | Ingress controller / reverse proxy for exposed services | Via app hostnames |
| **cert-manager** | Certificate lifecycle management in Kubernetes | Internal API |
| **Let's Encrypt** | Public TLS certificate issuer (through cert-manager) | Internal API |
| **Longhorn** | Distributed block storage for persistent volumes | Internal API |
| **Velero** | Backup and restore for cluster resources and volumes | Internal API |
| **CoreDNS** | Internal Kubernetes service discovery and DNS | Internal API |
| **MetalLB** | LoadBalancer IP allocation for bare-metal/local clusters | Internal API |

#### Host/LAN Tools (Optional)

| Component | Purpose | Default Access |
|-----------|---------|----------------|
| **dnsmasq** | Local LAN DNS resolution for `*.hostname.local` | Host/LAN service |
| **mkcert** | Local trusted certificates for LAN domains | Local host tool |

---

## Architecture Overview

### High Level Overview 

![alt text](https://dev.lair-ai.it/wp-content/uploads/2026/06/schema_ai.png "Lair Architecture Overview")

Lair consists of three main components that work together to provide a complete AI infrastructure:

### 1. Cluster Setup (`microk8s/` or `k8s-managed/`)
- **MicroK8s Setup**: Install and configure Kubernetes clusters (single-node or multi-node) optimized for AI workloads
- **Multi-Node Support**: Scale from single-node development to multi-node production clusters
- **Managed K8s Setup**: Configure existing Kubernetes clusters (OVH MKS, EKS, GKE, AKS, etc.)
- **Platform Detection**: Automatic optimization for x86_64, ARM64, and NVIDIA Jetson
- **Network Configuration**: Smart dual-IP handling for Cloud vs On-Premises scenarios
- **Storage & Backup**: Distributed Longhorn (multi-node) or Hostpath (Jetson), with Velero backup integration

### 2. Application Deployment (`helm-chart/`)
- **Interactive Configuration**: Guided setup with resource detection and optimization
- **Multi-Access Modes**: LAN (`.local` domains) and Public (internet domains) with automatic TLS
- **Resource Management**: Intelligent allocation based on available CPU, memory, and storage
- **Component Selection**: Enable/disable services based on your needs and resources

### 3. Access & Integration
- **LAN Access**: `.local` domains with optional HTTPS via mkcert certificates
- **Public Access**: Internet domains with automatic Let's Encrypt certificates
- **API Integration**: All services expose APIs for custom integrations
- **Backup & DR**: Automated backups to S3-compatible storage with Velero

---

## Quick Start

### Prerequisites

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **OS** | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS / DGX OS |
| **CPU** | 4 cores | 8+ cores |
| **RAM** | 8 GB | 16+ GB |
| **Storage** | 100 GB free | 200+ GB free |
| **Access** | Root/sudo | Root/sudo |

> **Note**: Lair does not work on Windows, even with WSL2 or any Windows emulation layer. Use native Ubuntu 24.04 LTS only. On DGX Spark, DGX OS (Ubuntu-based) is the recommended and fully supported environment.

### Simplified Installation (Recommended)

```bash
# 1. Clone repository
git clone https://github.com/Lair-ai/lair.git
cd lair

# 2. Run the interactive setup wizard
sudo ./setup.sh
```

**The setup wizard will:**
- Welcome you and explain the process
- Ask whether you want to setup a cluster or deploy Lair
- Guide you through cluster choice (managed vs local MicroK8s)
- Run the appropriate setup scripts interactively
- Handle the complete setup process step by step

**That's it!** Your private AI infrastructure is ready with guided assistance.

---

## Installation Paths

Choose the installation path that best fits your infrastructure:

Before choosing, here are the main deployment scenarios (aligned with the paths below):

1. **Single machine in local environment (for example DGX Spark or Jetson)** → **Path 1 (Local MicroK8s)**
2. **Single machine in cloud (one VM/node)** → **Path 1 (Local MicroK8s)**
3. **On-prem or LAN multi-node setup (primary + workers)** → **Path 1 (Local MicroK8s)**
4. **Managed multi-node Kubernetes in cloud (OVH MKS, EKS, GKE, AKS)** → **Path 2 (Managed Kubernetes)**
5. **Already prepared Kubernetes cluster (advanced direct deploy)** → **Path 3 (Helm-Only)**

### Path 1: Local MicroK8s (Recommended for most users)

Perfect for development, edge computing, and production deployments. **Supports multi-node clusters and DGX Spark.**

#### Single-Node Setup (Development / Edge / DGX Spark)
```bash
sudo ./microk8s/setup.sh
# Select: Node type: single (default)
```

#### Multi-Node Setup (Production/High Availability)
```bash
# 1. Setup primary node (master)
sudo ./microk8s/setup.sh
# Select: Node type: primary

# 2. Setup secondary nodes (workers) — on each additional machine
sudo ./microk8s/utils/setup-secondary.sh <PRIMARY_IP> <JOIN_TOKEN>

# 3. Deploy Lair applications
cd helm-chart
sudo ./setup.sh
```

 **Best for**: Development, testing, edge computing, NVIDIA Jetson, DGX Spark, single-node production

> **Jetson Note**: On NVIDIA Jetson devices, MicroK8s automatically configures Flannel CNI (instead of Calico) and Hostpath storage (instead of Longhorn), and supports single-node only.

> **DGX Spark Note**: DGX Spark is treated as a standard Ubuntu 24.04 ARM64 host. Use the same setup flow and scripts as any other supported Ubuntu machine.

### Path 2: Managed Kubernetes (Enterprise)

Deploy on existing Kubernetes clusters such as [OVH MKS](https://www.ovhcloud.com/en/public-cloud/kubernetes/).

```bash
# 1. Setup cluster components (Longhorn, Ingress, Cert-Manager)
sudo ./k8s-managed/setup.sh

# 2. Deploy Lair applications
cd helm-chart
sudo ./setup.sh
```

 **Best for**: Enterprise environments, multi-node clusters, existing K8s infrastructure

### Path 3: Helm-Only (Advanced)

Deploy directly to any Kubernetes cluster with existing infrastructure.

```bash
cd helm-chart
sudo ./setup.sh
```

 **Best for**: Advanced users with pre-configured Kubernetes clusters

---

## Edge AI & Desktop Supercomputing: NVIDIA Jetson & DGX Spark

Lair deploys a complete production-grade AI infrastructure on compact edge devices (NVIDIA Jetson) and desktop AI systems such as NVIDIA DGX Spark. It is a strong on-premise option for privacy, open-source control, and predictable costs, because models and data remain on your own hardware.

### NVIDIA DGX Spark — Desktop AI Supercomputer

The DGX Spark is powered by the **NVIDIA GB10 Grace Blackwell Superchip** and brings datacenter-class AI compute to a Mac mini-sized desktop form factor. Lair is validated to run on DGX Spark, enabling very high‑end single-node private AI deployments.

| Specification | DGX Spark |
|---------------|-----------|
| **Chip** | NVIDIA GB10 Grace Blackwell Superchip |
| **CPU** | 20-core ARM (10× Cortex-X925 + 10× Cortex-A725) |
| **GPU** | Blackwell with 5th-gen Tensor Cores |
| **AI Performance** | 1 PFLOP (sparse FP4) |
| **Memory** | 128 GB unified (CPU + GPU shared) |
| **Bandwidth** | 273 GB/s |
| **Max model size** | ~200B parameters (single) / ~405B (two units via ConnectX) |
| **OS** | DGX OS (Ubuntu 24.04-based) |
| **Architecture** | ARM64 |
| **Power** | 240W |

**DGX Spark + Lair: key benefits**
- Run **70B parameter models in FP16** on a single unit — no multi-GPU cluster required
- **128 GB unified memory** reduces system-to-VRAM data transfer overhead
- Full **CUDA acceleration** with PyTorch, Ollama, vLLM, and ComfyUI
- Keep your AI stack **fully on-premise** for data privacy and sovereignty
- Build on **open-source components** without SaaS lock-in
- Improve **cost control** for sustained workloads versus token-based cloud billing

### DGX Spark Quick Start

```bash
# On DGX Spark (DGX OS / Ubuntu 24.04 ARM64)
git clone https://github.com/Lair-ai/lair.git
cd lair
sudo ./setup.sh
# Choose your preferred access mode (LAN or Public)
# Same installation flow as any other supported Ubuntu host
```

### NVIDIA Jetson — Edge AI

For deployments at the network edge, Lair runs on all NVIDIA Jetson devices with automatic ARM64 optimizations.

```bash
git clone https://github.com/Lair-ai/lair.git
cd lair
sudo ./setup.sh
# Choose "lan" when prompted — Jetson is detected automatically
```

### What Runs on Both Platforms

| Component | Jetson | DGX Spark |
|-----------|--------|-----------|
| OpenWebUI (ChatGPT-like interface + RAG) | ✅ | ✅ |
| N8N (workflow automation, 400+ integrations) | ✅ | ✅ |
| Ollama (local LLM with GPU acceleration) | ✅ | ✅ *(up to 200B params)* |
| ComfyUI (AI image generation) | ✅ | ✅ |
| PostgreSQL (persistent storage) | ✅ | ✅ |
| Kubernetes (MicroK8s) | ✅ | ✅ |
| Custom AI workflows | ✅ | ✅ |
| Multi-node clustering | ❌ | ✅ *(via ConnectX)* |

### Why This Matters
- **Technical scope**: Production AI stack on ARM64 — from <60W Jetson devices to a 240W desktop system
- **Data locality**: Run enterprise-grade AI directly where your data resides
- **Privacy**: Process sensitive data locally with zero required cloud dependency
- **Cost considerations**: DGX Spark can be cost-competitive with cloud A100 workloads for sustained, full-time use

---

## Use Case Examples

### Private AI Development Lab (LAN Mode)
```bash
sudo ./microk8s/setup.sh
# Choose "lan" when prompted for access mode
cd helm-chart
./setup.sh --config lair-config-standard.yaml
```
**Perfect for**: Office environments, internal development, secure networks, DGX Spark workstations

### Edge AI Deployment (NVIDIA Jetson)
```bash
sudo ./microk8s/setup.sh
# Choose "lan" when prompted
cd helm-chart
./setup.sh --config lair-config-template-jetson.yaml
```

**Enterprise Edge Use Cases:**
- **Manufacturing**: AI quality control with real-time defect detection and automated responses
- **Retail**: Local customer behavior analysis with privacy-compliant workflow automation
- **Agriculture**: Autonomous crop monitoring with local AI processing and decision workflows
- **Security**: Real-time threat detection with automated response protocols — fully air-gapped

### Cloud Public Deployment (OVHCloud or AWS, GCP, Azure)
```bash
sudo ./microk8s/setup.sh
# Choose "public" — optimized for cloud environments
cd helm-chart
./setup.sh --config lair-config-standard.yaml
```
**Perfect for**: OVH MKS, AWS EC2, GCP Compute Engine, Azure VMs where public IP is assigned directly to the instance

### On-Premises Public Access (Router/NAT Setup)
```bash
sudo ./microk8s/setup.sh
# Choose "public" and enter your router's public IP when prompted
cd helm-chart
./setup.sh --config lair-config-standard.yaml
```
**Perfect for**: Home servers, office setups with router port forwarding, VPS with NAT

### Enterprise Managed Kubernetes (OVH MKS / EKS / GKE / AKS)
```bash
sudo ./k8s-managed/setup.sh
cd helm-chart
./setup.sh --config lair-config-standard.yaml
```
**Perfect for**: OVH MKS, AWS EKS, Google GKE, Azure AKS, OpenShift, Rancher

---

## Platform Support & Smart Features

### Platform Support

| Platform | Architecture | Networking | Storage | GPU | Multi-Node |
|----------|-------------|-----------|---------|-----|-----------|
| **x86_64** | x86_64 | Calico | Longhorn | NVIDIA (optional) | ✅ |
| **NVIDIA Jetson** | ARM64 | Flannel | Hostpath | Tegra | ❌ |
| **NVIDIA DGX Spark** | ARM64 | Calico | Longhorn | GB10 Blackwell |  ✅ *(via ConnectX)*  |
| **Cloud Instances** | x86_64 | Calico | Longhorn | NVIDIA (optional) | ✅ |

### Smart Features
- **Intelligent Scenario Detection** — Automatically detects and optimizes for Cloud vs On-Premises deployments
- **Smart Dual-IP Configuration** — Native optimization for NAT/router scenarios with separate internal/external IP handling
- **Auto-GPU Detection** — Automatic NVIDIA GPU configuration on supported platforms
- **Automatic Internet Connectivity** — Pod-to-internet routing for model downloads
- **Multi-Architecture** — Works on x86_64, ARM64, NVIDIA Jetson, NVIDIA DGX Spark
- **Storage Optimization** — Platform-specific storage solutions (Longhorn vs Hostpath)
- **Remote Cluster Access** — Optional remote kubectl access with automatic kube-apiserver configuration

---

## Quick Commands

### MicroK8s Deployments
```bash
microk8s status # Check system status
kubectl get pods -n lair # View all services
kubectl get ingress -n lair # Check service URLs
kubectl logs -n lair deployment/openwebui # View logs
sudo ./microk8s/teardown.sh # Complete cleanup
```

### Managed Kubernetes Deployments
```bash
kubectl cluster-info # Check cluster status
kubectl get pods -n lair # View all services
kubectl get ingress -n lair # Check service URLs
kubectl logs -n lair deployment/openwebui # View logs
sudo ./k8s-managed/teardown.sh # Complete cleanup
```

---

## Current Limitations

### Configuration Update Issues *(Critical)*

`setup.sh` **cannot safely update existing deployments** — it recalculates resources and may attempt to modify immutable PVC specifications, risking data loss.

**Safe Workaround:**
```bash
cd helm-chart
sudo ./setup.sh --config existing-config.yaml # Generate new config
nano values-yourname.yaml # Edit storage sizes manually
helm upgrade lair . -n lair -f values.yaml -f values-yourname.yaml
```

### Jetson Platform Limitations
- NVIDIA Jetson is **single-node only** — no distributed storage or high availability
- Uses Flannel CNI and Hostpath storage (not Longhorn)
- **Workaround**: Use reliable hardware and schedule regular backups

### DGX Spark Considerations
- ARM64 architecture may require additional configuration for some specialized tools and libraries not yet ported to `aarch64`
- DGX OS is the recommended and most thoroughly tested environment; stock Ubuntu 24.04 ARM64 is supported but may need manual driver setup
- Multi-node behavior follows your Kubernetes cluster design, same as other Ubuntu hosts

### No Central Management Dashboard
- Each component is accessed individually via separate URLs
- **Workaround**: Bookmark individual service URLs; use `kubectl` for system management

### OAuth2 Support by Mode
- N8N OAuth2 integrations have **limited functionality in LAN mode** (internal URLs cannot be reached by external OAuth2 providers)
- **Full OAuth2 support** is available in Public mode (Cloud and On-Premises)

---

## Future Roadmap

- **Unified management dashboard** for centralized operations and health checks
- **Safer config updates** to avoid immutable PVC update conflicts during upgrades
- **Expanded platform hardening** for ARM64 and edge deployments
- **Improved docs depth** (installation, operations, and troubleshooting runbooks)

---

## Documentation

> **[Complete Documentation](docs/INTRO.md)** — Comprehensive guides for installation, configuration, and maintenance

### Installation & Setup
- [Prerequisites & Requirements](docs/installation/requirements.md)
- [MicroK8s Setup](docs/installation/microk8s-setup.md)
- [DGX Spark Setup](docs/installation/dgx-spark-setup.md)
- [Managed Kubernetes Setup](docs/installation/managed-k8s-setup.md)
- [Troubleshooting](docs/installation/troubleshooting.md)

### Components & Configuration
- [Services Overview](docs/components/services-overview.md)
- [Network & Access](docs/configuration/network-access.md)
- [Storage & Backup](docs/configuration/storage-backup.md)
- [Security & Certificates](docs/configuration/security-certificates.md)

### Maintenance & Operations
- [Updates & Upgrades](docs/maintenance/updates.md)
- [Backup & Disaster Recovery](docs/maintenance/backup-restore.md)
- [Monitoring & Troubleshooting](docs/maintenance/monitoring.md)

---

## Contributing

Contributions are what make the open-source community such an amazing place. **Any contribution you make is greatly appreciated.**

For larger features or architectural changes, please **open an issue first** to discuss the approach before investing time in implementation.

> See [CONTRIBUTING.md](CONTRIBUTING.md) for the full contribution guide.

---

## Code of Conduct

This project adheres to the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this standard. Please report unacceptable behaviour to [info@lair-ai.it](mailto:info@lair-ai.it).

---

## Security

We take security seriously. **Please do not report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability, please send a responsible disclosure email to:

**[security@lair-ai.it](mailto:security@lair-ai.it)**

Include:
- A description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested mitigation

You can expect an acknowledgement within **48 hours** and a resolution timeline within **90 days**.

> See [SECURITY.md](SECURITY.md) for the full security policy.

---

## Support & Community

| Channel | Purpose |
|---------|---------|
| [Documentation](docs/) | Guides, references, and how-tos |
| [GitHub Issues](https://github.com/Lair-ai/lair/issues) | Bug reports and feature requests |
| [GitHub Discussions](https://github.com/Lair-ai/lair/discussions) | Questions, ideas, and community chat |
| [Commercial Support](https://www.nexid.it) | Enterprise support by NEXiD s.r.l. |

---

## License

Distributed under the **GPL3.0 License**. See [LICENSE](LICENSE) for full details.

---

## About

Lair is an open-source private AI framework born in 2024 as an internal tool by **[NEXiD s.r.l.](https://www.nexid.it)**, an Italian technology company.
Built around data sovereignty from day one — models, automation and tools that run entirely on your own infrastructure, with no SaaS lock-in and no data egress.

Created by **[NEXiD s.r.l.](https://www.nexid.it)**

---

## Acknowledgements

### Canonical

Thank you to **Canonical** for Ubuntu and MicroK8s, which provide the operating system and lightweight Kubernetes foundation used by Lair.

### OVHcloud

Thank you to **[OVHcloud](https://www.ovhcloud.com/)** for cloud infrastructure, Managed Kubernetes, S3-compatible object storage, and AI endpoint services that help make sovereign AI deployments practical.

### Ianustec

Thank you to **[IANUSTEC s.r.l.](https://ianustec.com)** for development support, technical guidance, and hands-on contributions to the Lair project.

### Open-Source Projects
Lair also thanks the open-source communities and maintainers behind the software used by the package: [Kubernetes](https://github.com/kubernetes/kubernetes), [Helm](https://github.com/helm/helm), [PostgreSQL](https://github.com/postgres/postgres), [Redis](https://github.com/redis/redis), [N8N](https://github.com/n8n-io/n8n), [OpenWebUI](https://github.com/openwebui/openwebui), [Longhorn](https://github.com/longhorn/longhorn), [cert-manager](https://github.com/cert-manager/cert-manager), [ingress-nginx](https://github.com/kubernetes/ingress-nginx), [Velero](https://github.com/vmware-tanzu/velero), [CoreDNS](https://github.com/coredns/coredns), [MetalLB](https://github.com/metallb/metallb), [Let's Encrypt](https://github.com/letsencrypt/boulder), [MinIO](https://github.com/minio/minio), [Apache Tika](https://github.com/apache/tika), [ComfyUI](https://github.com/comfyanonymous/ComfyUI), [Ollama](https://github.com/ollama/ollama), [pgvector](https://github.com/pgvector/pgvector), [Calico](https://github.com/projectcalico/calico), [Flannel](https://github.com/flannel-io/flannel), [hostpath provisioner](https://github.com/kubernetes-sigs/sig-storage-local-static-provisioner), [dnsmasq](https://github.com/thekelleys/dnsmasq), and [mkcert](https://github.com/FiloSottile/mkcert).

---

**Made in Italy by [LAiR](https://dev.lair-ai.it/)** 
