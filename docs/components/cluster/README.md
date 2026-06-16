# 🔧 Kubernetes Cluster Configuration

> **Complete guide to Kubernetes cluster management, configuration, and optimization in Lair**

This guide covers the core Kubernetes cluster functionality that powers Lair, from MicroK8s configuration to managed cluster setup and optimization.

---

## 🎯 Overview

The Kubernetes cluster is the foundation of Lair, providing container orchestration, service discovery, and resource management. This guide covers cluster-level configuration and management.

### 🏗️ **Cluster Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                     🔧 CLUSTER COMPONENTS                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Control       │  │     Nodes       │  │    Addons       │  │
│  │   Plane         │  │   (Workers)     │  │  (Extensions)   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🌐 NETWORKING LAYER                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │      CNI        │  │   Load Balancer │  │     Ingress     │  │
│  │ (Calico/Flannel)│  │    (MetalLB)    │  │    (NGINX)      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                       💾 STORAGE LAYER                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │    Longhorn     │  │    Hostpath     │  │   Cloud CSI     │  │
│  │ (Distributed)   │  │   (Local)       │  │ (EBS/GCE/Azure) │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📊 **Cluster Types**

| Type | Use Case | Nodes | Management | Best For |
|------|----------|-------|------------|----------|
| **MicroK8s** | Local development, edge | Single/Multi | Self-managed | Development, Jetson, single-node |
| **Managed K8s** | Production, enterprise | Multi | Cloud-managed | AWS EKS, GKE, AKS |
| **Custom K8s** | Specialized deployments | Variable | Self-managed | Advanced users, custom requirements |

---

## 🔧 MicroK8s Configuration

### 🚀 **Core Configuration**

#### **Basic Cluster Setup**
```bash
# Install MicroK8s
sudo snap install microk8s --classic

# Check status
sudo microk8s status --wait-ready

# Enable core addons
sudo microk8s enable dns ingress helm3

# Get cluster info
sudo microk8s kubectl cluster-info
```

#### **Addon Management**
```bash
# List available addons
sudo microk8s status

# Enable storage (Longhorn for standard, Hostpath for Jetson)
sudo microk8s enable hostpath-storage  # Basic storage
# OR
sudo microk8s enable longhorn          # Distributed storage

# Enable additional addons
sudo microk8s enable cert-manager      # Certificate management
sudo microk8s enable metallb           # Load balancer
sudo microk8s enable gpu               # GPU support (if available)
```

#### **Network Configuration**
```bash
# Check CNI status
sudo microk8s kubectl get pods -n kube-system | grep -E "(calico|flannel)"

# For Jetson: Flannel is automatically configured
# For Standard: Calico is default

# Check network policies
sudo microk8s kubectl get networkpolicies -A
```

### 🤖 **Jetson-Specific Configuration**

#### **Jetson Optimizations**
```bash
# Jetson automatically configures:
# - Flannel CNI (instead of Calico)
# - Hostpath storage (instead of Longhorn)
# - Single-node mode only
# - ARM64 optimizations

# Check Jetson-specific settings
sudo microk8s kubectl get nodes -o wide
sudo microk8s kubectl get storageclass
```

#### **Jetson Resource Limits**
```yaml
# Jetson resource configuration
apiVersion: v1
kind: ResourceQuota
metadata:
  name: jetson-quota
  namespace: lair
spec:
  hard:
    requests.cpu: "3"      # Reserve 1 CPU for system
    requests.memory: "6Gi" # Reserve 2GB for system
    persistentvolumeclaims: "10"
```

---

## ☁️ Managed Kubernetes Configuration

### 🔧 **AWS EKS Configuration**

#### **Cluster Access**
```bash
# Configure kubectl for EKS
aws eks update-kubeconfig --region us-west-2 --name lair-cluster

# Verify access
kubectl cluster-info
kubectl get nodes
```

#### **EKS-Specific Components**
```bash
# Install AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=lair-cluster

# Install EBS CSI driver
kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.19"
```

### 🔧 **Google GKE Configuration**

#### **Cluster Access**
```bash
# Configure kubectl for GKE
gcloud container clusters get-credentials lair-cluster --zone us-central1-a

# Verify access
kubectl cluster-info
kubectl get nodes
```

#### **GKE-Specific Components**
```bash
# GKE uses built-in ingress and storage
# Verify GKE components
kubectl get storageclass
kubectl get ingressclass
```

### 🔧 **Azure AKS Configuration**

#### **Cluster Access**
```bash
# Configure kubectl for AKS
az aks get-credentials --resource-group lair-rg --name lair-cluster

# Verify access
kubectl cluster-info
kubectl get nodes
```

---

## 🔍 Cluster Monitoring & Management

### 📊 **Cluster Health Monitoring**

#### **Basic Health Checks**
```bash
# Cluster status
kubectl cluster-info
kubectl get componentstatuses

# Node status
kubectl get nodes -o wide
kubectl describe nodes

# System pods
kubectl get pods -n kube-system
kubectl get pods -A --field-selector=status.phase!=Running
```

#### **Resource Monitoring**
```bash
# Resource usage
kubectl top nodes
kubectl top pods -A

# Cluster capacity
kubectl describe nodes | grep -A 5 "Allocated resources"

# Storage usage
kubectl get pv
kubectl get pvc -A
```

### 🔧 **Cluster Maintenance**

#### **Node Management**
```bash
# Drain node for maintenance
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Uncordon node after maintenance
kubectl uncordon <node-name>

# Remove node from cluster
kubectl delete node <node-name>
```

#### **Addon Management**
```bash
# MicroK8s addon management
sudo microk8s enable <addon-name>
sudo microk8s disable <addon-name>
sudo microk8s status

# Check addon status
kubectl get pods -n kube-system
kubectl get services -n kube-system
```

---

## 🚨 Troubleshooting

### 🔧 **Common Cluster Issues**

#### **Node Not Ready**
```bash
# Symptom: Node shows NotReady status
kubectl get nodes
kubectl describe node <node-name>

# Check kubelet logs
sudo journalctl -u snap.microk8s.daemon-kubelet -f

# Common solutions:
# 1. Restart MicroK8s
sudo microk8s stop
sudo microk8s start

# 2. Check disk space
df -h

# 3. Check memory
free -h
```

#### **Pod Scheduling Issues**
```bash
# Symptom: Pods stuck in Pending state
kubectl get pods -A | grep Pending
kubectl describe pod <pod-name> -n <namespace>

# Check resource constraints
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check taints and tolerations
kubectl describe nodes | grep -A 5 Taints
```

#### **Network Issues**
```bash
# Symptom: Pods cannot communicate
# Check CNI pods
kubectl get pods -n kube-system | grep -E "(calico|flannel)"

# Test pod-to-pod connectivity
kubectl run network-test --image=busybox --rm -it -- ping <target-ip>

# Check DNS resolution
kubectl run dns-test --image=busybox --rm -it -- nslookup kubernetes.default
```

### 🔄 **Recovery Procedures**

#### **Cluster Recovery**
```bash
# MicroK8s cluster reset
sudo microk8s reset --destructive

# Reinstall and reconfigure
sudo ./microk8s/setup.sh

# Restore from backup (if Velero configured)
velero restore create cluster-restore --from-backup cluster-backup-latest
```

#### **Addon Recovery**
```bash
# Reset specific addon
sudo microk8s disable <addon-name>
sudo microk8s enable <addon-name>

# Check addon status
kubectl get pods -n kube-system -l app=<addon-name>
```

---

## 🎯 Best Practices

### 🚀 **Performance Best Practices**
- **Resource Allocation**: Set appropriate resource requests and limits
- **Node Sizing**: Use appropriate node sizes for workload
- **Storage**: Choose appropriate storage classes for performance needs
- **Network**: Optimize CNI configuration for your environment
- **Monitoring**: Implement comprehensive cluster monitoring

### 🔒 **Security Best Practices**
- **RBAC**: Implement proper role-based access control
- **Network Policies**: Restrict pod-to-pod communication
- **Pod Security**: Use pod security standards
- **Secrets Management**: Properly manage sensitive data
- **Regular Updates**: Keep cluster components updated

### 📊 **Operational Best Practices**
- **Backup Strategy**: Regular cluster and data backups
- **Monitoring**: Comprehensive monitoring and alerting
- **Documentation**: Document cluster configuration and procedures
- **Testing**: Regular disaster recovery testing
- **Capacity Planning**: Monitor and plan for growth

---

## 🔮 Advanced Configuration

### 🎛️ **Custom Resource Definitions**
```yaml
# Example CRD for Lair-specific resources
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: lairconfigs.lair.io
spec:
  group: lair.io
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              platform:
                type: string
              resources:
                type: object
  scope: Namespaced
  names:
    plural: lairconfigs
    singular: lairconfig
    kind: LairConfig
```

### 🔧 **Cluster Autoscaling**
```yaml
# Cluster autoscaler configuration (for managed clusters)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.21.0
        name: cluster-autoscaler
        command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/lair-cluster
```

---

**🎯 Ready to optimize your cluster?** Continue with [Backup Configuration](../backup/README.md) or explore [Network Configuration](../networking/README.md)!
