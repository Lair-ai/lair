# Installation Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| **OS** | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS / DGX OS |
| **CPU** | 4 cores | 8+ cores |
| **RAM** | 8 GB | 16+ GB |
| **Storage** | 100 GB free | 200+ GB free |
| **NVIDIA driver** | 570.26+ for x86 RTX | 590.44+ for DGX Spark ComfyUI |
| **Access** | Root/sudo | Root/sudo |

> **Note**: Lair does not work on Windows, even with WSL2 or any Windows emulation layer. Use native Ubuntu 24.04 LTS only. On DGX Spark, DGX OS (Ubuntu-based) is the recommended and fully supported environment.

For more information, see:

- `README.md` (Quick Start prerequisites)
- `docs/installation/managed-k8s-setup.md` (Kubernetes requirements)
- `docs/installation/microk8s-setup.md`
