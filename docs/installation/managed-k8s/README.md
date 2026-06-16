# ☁️ Managed Kubernetes Installation Guide

> **Complete guide for deploying Lair on existing Kubernetes clusters (EKS, GKE, AKS, etc.)**

This guide covers deploying Lair on existing managed Kubernetes clusters. The `k8s-managed/setup.sh` script installs the required infrastructure components (Longhorn, Ingress-NGINX, Cert-Manager, Velero) on your existing cluster.

---

## 🎯 Overview

The Managed Kubernetes setup process (`k8s-managed/setup.sh`) prepares existing Kubernetes clusters for Lair by installing essential infrastructure components that may not be available by default.

### 🔄 **Installation Flow**
```
Prerequisites → System Setup → Component Install → Verification
     ↓              ↓              ↓              ↓
Cluster Access → Helm Install → Longhorn      → Health Check
Permissions    → Dependencies → Ingress-NGINX → Ready for Lair
Network Config → Tools Setup → Cert-Manager   → App Deployment
               → Velero      → Velero (opt)   →
```

### 📦 **What Gets Installed**
- **🛠️ Helm (OS-level)**: Helm v3.14.0 for package management
- **💾 Longhorn**: Distributed block storage with replication
- **🌐 Ingress-NGINX**: HTTP/HTTPS ingress controller with LoadBalancer
- **🔐 Cert-Manager**: Automatic TLS certificate management
- **📦 Velero**: Backup and disaster recovery (optional)
- **🔧 IngressClass**: `public` ingress class for MicroK8s compatibility

---

## 📋 Prerequisites

### ☁️ **Supported Kubernetes Platforms**

| Platform | Version | Notes |
|----------|---------|-------|
| **AWS EKS** | 1.28+ | Native LoadBalancer, EBS CSI driver |
| **Google GKE** | 1.28+ | Native LoadBalancer, Persistent Disk CSI |
| **Azure AKS** | 1.28+ | Native LoadBalancer, Azure Disk CSI |
| **DigitalOcean DOKS** | 1.28+ | Native LoadBalancer, Block Storage CSI |
| **Linode LKE** | 1.28+ | Native LoadBalancer, Block Storage CSI |
| **OpenShift** | 4.12+ | Route support, OpenShift CSI drivers |
| **Rancher** | 1.28+ | Rancher-managed clusters |
| **Self-Managed** | 1.28+ | Manual LoadBalancer configuration required |

### 🔧 **Cluster Requirements**

#### **Access & Permissions**
```bash
# Required: kubectl access to cluster
kubectl cluster-info

# Required: Cluster admin permissions
kubectl auth can-i create clusterrole
kubectl auth can-i create namespace
kubectl auth can-i create customresourcedefinition
```

#### **Resource Requirements**
| Component | CPU | Memory | Storage | Nodes |
|-----------|-----|--------|---------|-------|
| **Longhorn** | 500m per node | 512Mi per node | 20GB per node | 1+ |
| **Ingress-NGINX** | 100m | 90Mi | - | 1+ |
| **Cert-Manager** | 10m | 32Mi | - | 1+ |
| **Velero** | 500m | 128Mi | - | 1+ |
| **Total Overhead** | ~1.1 cores | ~762Mi | 20GB+ | 1+ |

#### **Node Requirements (Per Node)**
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 4+ cores | 8+ cores |
| **RAM** | 8GB | 16GB+ |
| **Storage** | 100GB free | 200GB+ free |
| **Network** | 1Gbps | 10Gbps+ |

#### **Network Requirements**
```bash
# Required: Internet access for image pulls
kubectl run test-connectivity --image=busybox --rm -it -- ping google.com

# Required: LoadBalancer support (cloud platforms)
kubectl get services -A | grep LoadBalancer

# Optional: Dynamic DNS for public access
nslookup your-domain.com
```

### 🖥️ **Local System Requirements**
- **OS**: Linux or macOS (WSL2/Windows not supported)
- **Tools**: curl or wget, tar
- **Access**: Internet connectivity for downloads
- **Permissions**: sudo access for Helm installation

---

## 🚀 Quick Start

### 🎯 **Simple Installation**
```bash
# Clone repository
git clone https://github.com/Lair-ai/lair.git
cd lair

# Run managed K8s setup
sudo ./k8s-managed/setup.sh
```

The script will guide you through:
1. **🔍 Preflight Checks**: Cluster access and permissions verification
2. **🛠️ System Setup**: Local dependencies and Helm installation
3. **📦 Component Installation**: Infrastructure components deployment
4. **🔄 Backup Configuration**: Optional Velero backup setup
5. **✅ Verification**: Component health checks

### 📊 **Interactive Prompts**

#### **🔄 Backup Configuration**
```
Enable Velero backups? (y/n) [default: y]:
```
- **Yes**: Configure S3-compatible backup storage
- **No**: Skip backup configuration (can be added later)

#### **☁️ Storage Configuration**
```
📦 Bucket name: my-cluster-backups
🌐 Storage endpoint URL [default: https://s3.gra.io.cloud.ovh.net]:
🗺️ Region code: us-east-1
🔑 Access Key: AKIAIOSFODNN7EXAMPLE
🔒 Secret Key: [hidden input]
```

---

## 🔧 Detailed Installation Process

### 📝 **Step-by-Step Breakdown**

The `k8s-managed/setup.sh` script orchestrates the installation through several phases:

#### **Phase 1: Preflight Checks** (`lib/preflight.sh`)
```bash
# What happens:
- Kubernetes cluster connectivity verification
- kubectl command availability check
- Cluster admin permissions verification
- Node readiness assessment
- Network connectivity tests
```

**Verification Commands**:
```bash
# Check cluster access
kubectl cluster-info

# Verify admin permissions
kubectl auth can-i '*' '*' --all-namespaces

# Check node status
kubectl get nodes -o wide

# Test internet connectivity
kubectl run connectivity-test --image=busybox --rm -it -- ping -c 3 google.com
```

#### **Phase 2: System Setup** (`lib/system_setup.sh`)
```bash
# What happens:
- System package updates
- Required dependencies installation
- User permissions configuration
- Environment preparation
```

#### **Phase 3: Helm Installation** (`lib/helm_os_install.sh`)
```bash
# What happens:
- Architecture detection (amd64, arm64, arm)
- Helm v3.14.0 download and installation
- Standard Helm repositories addition
- Installation verification
```

**Helm Repositories Added**:
```bash
helm repo add stable https://charts.helm.sh/stable
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add jetstack https://charts.jetstack.io
helm repo add longhorn https://charts.longhorn.io
```

#### **Phase 4: Component Installation** (`lib/component_install.sh`)

##### **🗄️ Longhorn Storage Installation**
```bash
# What happens:
- Longhorn Helm repository addition
- Longhorn installation with optimized settings
- Replica count based on node count
- Volume expansion enabled
- Deployment readiness verification
```

**Longhorn Configuration**:
```yaml
# Automatic configuration applied:
defaultSettings:
  allowVolumeCreationWithDegradedAvailability: true
  defaultReplicaCount: 1  # Auto-calculated based on nodes
storageClass:
  allowVolumeExpansion: true
```

##### **🌐 Ingress-NGINX Installation**
```bash
# What happens:
- Ingress-NGINX Helm repository addition
- Controller installation with LoadBalancer service
- 'public' IngressClass creation for MicroK8s compatibility
- Controller readiness verification
```

**IngressClass Configuration**:
```yaml
# Created automatically:
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: public
spec:
  controller: k8s.io/ingress-nginx
```

##### **🔐 Cert-Manager Installation**
```bash
# What happens:
- Jetstack Helm repository addition
- Cert-Manager v1.12.0 installation with CRDs
- Webhook deployment verification
- Certificate issuer preparation
```

#### **Phase 5: Velero Installation** (`lib/k8s_velero.sh` - Optional)
```bash
# What happens (if enabled):
- Interactive backup configuration
- S3-compatible storage setup
- Velero Helm installation with AWS plugin
- Backup storage location configuration
- Credentials secret creation
```

---

## ☁️ Cloud Platform Specific Guides

### 🟠 **Amazon EKS**

#### **Prerequisites**
```bash
# Install AWS CLI and configure
aws configure
aws eks update-kubeconfig --region us-west-2 --name my-cluster

# Verify EKS access
kubectl get nodes
kubectl get storageclass  # Should show gp2/gp3
```

#### **EKS-Specific Considerations**
- **LoadBalancer**: Uses AWS Application Load Balancer (ALB) or Network Load Balancer (NLB)
- **Storage**: EBS CSI driver pre-installed, Longhorn adds distributed storage
- **Networking**: VPC CNI, compatible with Longhorn
- **IAM**: Ensure cluster has permissions for LoadBalancer and EBS operations

#### **Post-Installation Verification**
```bash
# Check AWS Load Balancer creation
kubectl get services -n ingress-nginx

# Verify EBS volume creation
kubectl get pv | grep longhorn
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/cluster/my-cluster,Values=owned"
```

### 🔵 **Google GKE**

#### **Prerequisites**
```bash
# Install gcloud CLI and configure
gcloud auth login
gcloud container clusters get-credentials my-cluster --zone us-central1-a

# Verify GKE access
kubectl get nodes
kubectl get storageclass  # Should show standard/ssd
```

#### **GKE-Specific Considerations**
- **LoadBalancer**: Uses Google Cloud Load Balancer
- **Storage**: Persistent Disk CSI driver, Longhorn adds replication
- **Networking**: GKE CNI (Calico or Cilium), compatible with Longhorn
- **IAM**: Ensure service account has Compute Engine and Load Balancer permissions

#### **Post-Installation Verification**
```bash
# Check GCP Load Balancer creation
kubectl get services -n ingress-nginx
gcloud compute forwarding-rules list

# Verify Persistent Disk creation
kubectl get pv | grep longhorn
gcloud compute disks list --filter="name~longhorn"
```

### 🔷 **Azure AKS**

#### **Prerequisites**
```bash
# Install Azure CLI and configure
az login
az aks get-credentials --resource-group myResourceGroup --name myAKSCluster

# Verify AKS access
kubectl get nodes
kubectl get storageclass  # Should show default/managed-premium
```

#### **AKS-Specific Considerations**
- **LoadBalancer**: Uses Azure Load Balancer
- **Storage**: Azure Disk CSI driver, Longhorn adds distribution
- **Networking**: Azure CNI or Kubenet, compatible with Longhorn
- **RBAC**: Ensure cluster identity has Network Contributor role

#### **Post-Installation Verification**
```bash
# Check Azure Load Balancer creation
kubectl get services -n ingress-nginx
az network lb list --resource-group MC_*

# Verify Azure Disk creation
kubectl get pv | grep longhorn
az disk list --resource-group MC_* --query "[?contains(name,'longhorn')]"
```

---

## 🔍 Verification & Testing

### ✅ **Component Health Checks**

#### **Longhorn Storage**
```bash
# Check Longhorn deployment
kubectl get pods -n longhorn-system

# Verify storage class
kubectl get storageclass longhorn

# Test PVC creation
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-longhorn-pvc
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF

# Check PVC status
kubectl get pvc test-longhorn-pvc

# Cleanup
kubectl delete pvc test-longhorn-pvc
```

#### **Ingress-NGINX Controller**
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx

# Check LoadBalancer service
kubectl get services -n ingress-nginx

# Test ingress functionality
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
spec:
  rules:
  - host: test.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kubernetes
            port:
              number: 443
EOF

# Check ingress creation
kubectl get ingress test-ingress

# Cleanup
kubectl delete ingress test-ingress
```

#### **Cert-Manager**
```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# Verify CRDs installation
kubectl get crd | grep cert-manager

# Test certificate issuance (Let's Encrypt staging)
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-staging
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory
    email: test@example.com
    privateKeySecretRef:
      name: letsencrypt-staging
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Check issuer status
kubectl get clusterissuer letsencrypt-staging

# Cleanup
kubectl delete clusterissuer letsencrypt-staging
```

#### **Velero (if installed)**
```bash
# Check Velero deployment
kubectl get pods -n velero

# Check backup storage location
kubectl get backupstoragelocations -n velero

# Test backup creation
velero backup create test-backup --include-namespaces default

# Check backup status
velero backup get test-backup

# Cleanup
velero backup delete test-backup --confirm
```

### 🚨 **Common Issues & Solutions**

#### **Longhorn Installation Issues**
```bash
# Issue: Longhorn pods stuck in Pending
# Check node requirements
kubectl describe nodes

# Verify iSCSI support
kubectl get pods -n longhorn-system | grep longhorn-manager
kubectl logs -n longhorn-system daemonset/longhorn-manager

# Solution: Install iSCSI on nodes (if self-managed)
# For managed clusters, this is usually pre-configured
```

#### **Ingress Controller Issues**
```bash
# Issue: LoadBalancer stuck in Pending
# Check cloud provider LoadBalancer limits
kubectl describe service -n ingress-nginx

# Check cloud provider quotas
# AWS: EC2 → Load Balancers
# GCP: Network Services → Load Balancing
# Azure: Load Balancers

# Solution: Increase quotas or use NodePort
kubectl patch service ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"NodePort"}}'
```

#### **Cert-Manager Issues**
```bash
# Issue: Certificate challenges failing
# Check DNS propagation
nslookup your-domain.com

# Check HTTP-01 challenge accessibility
curl -I http://your-domain.com/.well-known/acme-challenge/test

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

---

## 🔧 Advanced Configuration

### 🎛️ **Custom Storage Configuration**

#### **Multiple Storage Classes**
```bash
# Keep cloud provider storage + Longhorn
kubectl get storageclass

# Example: Use cloud storage for databases, Longhorn for applications
# Update Lair configuration to specify storage classes per component
```

#### **Longhorn Customization**
```yaml
# Custom Longhorn values
longhorn:
  defaultSettings:
    defaultReplicaCount: 2  # Increase for production
    backupTarget: "s3://my-backup-bucket"
    defaultDataPath: "/var/lib/longhorn"
  persistence:
    defaultClass: true
    defaultClassReplicaCount: 2
```

### 🌐 **Advanced Ingress Configuration**

#### **Multiple Ingress Controllers**
```bash
# Keep cloud provider ingress + NGINX
kubectl get ingressclass

# Use different controllers for different services
# Example: ALB for public APIs, NGINX for applications
```

#### **Custom Ingress Annotations**
```yaml
# Cloud provider specific annotations
metadata:
  annotations:
    # AWS ALB
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    
    # GCP GCE
    kubernetes.io/ingress.class: gce
    kubernetes.io/ingress.global-static-ip-name: my-global-ip
    
    # Azure Application Gateway
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
```

### 🔐 **Enterprise Security Configuration**

#### **Network Policies**
```yaml
# Restrict Longhorn network access
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: longhorn-network-policy
  namespace: longhorn-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: lair
```

#### **Pod Security Standards**
```yaml
# Apply pod security standards
apiVersion: v1
kind: Namespace
metadata:
  name: lair
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

---

## 🔄 Migration from MicroK8s

### 📦 **Data Migration Process**

#### **1. Backup MicroK8s Data**
```bash
# On MicroK8s cluster
kubectl get all -n lair -o yaml > lair-backup.yaml
kubectl get pvc -n lair -o yaml > lair-pvc-backup.yaml

# Backup persistent data
kubectl exec -n lair deployment/lair-postgresql -- pg_dump -U postgres lair > postgres-backup.sql
```

#### **2. Prepare Managed Cluster**
```bash
# Run k8s-managed setup
sudo ./k8s-managed/setup.sh

# Verify components
kubectl get storageclass
kubectl get pods -n longhorn-system
kubectl get pods -n ingress-nginx
```

#### **3. Restore Data**
```bash
# Create namespace and restore configurations
kubectl create namespace lair
kubectl apply -f lair-backup.yaml

# Restore database
kubectl exec -n lair deployment/lair-postgresql -- psql -U postgres lair < postgres-backup.sql
```

### 🔧 **Configuration Adjustments**

#### **Update Storage Classes**
```yaml
# Change from microk8s-hostpath to longhorn
global:
  storageClass: longhorn  # Instead of microk8s-hostpath
```

#### **Update Ingress Classes**
```yaml
# Change ingress class if needed
ingress:
  className: nginx  # Instead of public (if using cloud provider ingress)
```

---

## 🔄 Next Steps

After successful managed K8s setup:

1. **✅ Verify Installation**: Run all verification checks above
2. **📦 Deploy Applications**: Proceed to [Helm Chart Deployment](../helm-chart/README.md)
3. **🔧 Configure Access**: Set up [Access Modes](../../configuration/access-modes/README.md)
4. **🔐 Setup Certificates**: Configure [TLS Certificates](../../configuration/certificates/README.md)
5. **📊 Monitor System**: Set up [Monitoring](../../maintenance/monitoring/README.md)
6. **💾 Configure Backups**: Set up [Backup Procedures](../../maintenance/backup-restore/README.md)

---

**🎯 Ready for applications?** Continue with [Helm Chart Deployment Guide](../helm-chart/README.md) or explore [Cloud-Specific Optimizations](../../configuration/advanced/README.md)!
