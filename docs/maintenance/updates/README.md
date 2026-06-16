# 🔄 Updates & Upgrades

> **Complete guide to updating and upgrading Lair components, applications, and system dependencies**

This guide covers all update procedures for Lair, from application updates to system-wide upgrades, ensuring your installation stays current and secure.

---

## 🎯 Overview

Lair provides comprehensive update mechanisms to keep all components current, secure, and optimized. Updates are handled at multiple levels with different strategies and safety measures.

### 🏗️ **Update Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                       🔄 UPDATE LEVELS                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Application   │  │   Kubernetes    │  │     System      │  │
│  │    Updates      │  │    Updates      │  │   Updates       │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🎯 UPDATE STRATEGIES                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Rolling        │  │   Blue-Green    │  │   Maintenance   │  │
│  │  Updates        │  │   Deployment    │  │   Window        │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🛡️ SAFETY MECHANISMS                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │    Backup       │  │   Validation    │  │    Rollback     │  │
│  │   Before        │  │    Checks       │  │  Capability     │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📊 **Update Types**

| Type | Scope | Downtime | Risk Level | Frequency |
|------|-------|----------|------------|-----------|
| **Application Updates** | Lair apps | Minimal | Low | Weekly/Monthly |
| **Configuration Updates** | Settings only | None | Very Low | As needed |
| **Kubernetes Updates** | Cluster components | Moderate | Medium | Quarterly |
| **System Updates** | OS and dependencies | High | Medium | Monthly |
| **Security Updates** | Critical patches | Variable | Low | Immediately |

---

## 🚀 Application Updates

### 🔄 **Lair Application Updates**

The primary method for updating Lair applications uses the built-in update mechanism.

#### **Interactive Update Mode**
```bash
# Navigate to helm-chart directory
cd helm-chart/

# Run setup in update mode
sudo ./setup.sh --update

# The script will:
# 1. Auto-detect existing configuration
# 2. Load current settings
# 3. Allow modification of configuration
# 4. Apply updates with conflict resolution
```

#### **Non-Interactive Update Mode**
```bash
# Update with existing configuration file
sudo ./setup.sh --update values-myconfig.yaml

# Or update with auto-detected configuration
sudo ./setup.sh --update
```

#### **Update Process Flow**
1. **Configuration Detection**: Automatically finds existing configuration
2. **Conflict Resolution**: Handles StatefulSet and PVC conflicts
3. **Backup Creation**: Creates backup of current state (if Velero enabled)
4. **Rolling Update**: Updates applications with minimal downtime
5. **Validation**: Verifies update success and application health

### 🔧 **Manual Application Updates**

#### **Individual Component Updates**
```bash
# Update specific application
helm upgrade --install lair . -n lair -f values-myconfig.yaml

# Update with specific image versions
helm upgrade --install lair . -n lair \
  --set openwebui.image.tag=v0.3.32 \
  --set ollama.image.tag=0.3.12 \
  -f values-myconfig.yaml
```

#### **Handling Update Conflicts**
```bash
# If StatefulSet conflicts occur during update
kubectl delete statefulset ollama -n lair --cascade=orphan
kubectl delete statefulset n8n-postgres -n lair --cascade=orphan

# Then retry the update
helm upgrade --install lair . -n lair -f values-myconfig.yaml
```

### 📋 **Application Version Management**

#### **Check Current Versions**
```bash
# Check deployed versions
helm list -n lair
kubectl get pods -n lair -o wide

# Check available image versions
kubectl describe pod -n lair | grep Image:

# Check Helm chart version
helm show chart . | grep version
```

#### **Version Pinning**
```yaml
# Pin specific versions in values-myconfig.yaml
openwebui:
  image:
    tag: "v0.3.32"  # Pin to specific version

ollama:
  image:
    tag: "0.3.12"   # Pin to specific version

n8n:
  image:
    tag: "1.63.1"   # Pin to specific version
```

---

## ⚙️ Configuration Updates

### 🔧 **Configuration-Only Updates**

For updates that only change configuration without updating application versions:

#### **Resource Configuration Updates**
```bash
# Update resource allocations
sudo ./setup.sh --update

# Modify resources in the interactive menu
# Apply changes without changing application versions
```

#### **Access Mode Updates**
```bash
# Switch between LAN and Public access modes
sudo ./setup.sh --update

# Update domain configurations
# Modify certificate settings
# Update ingress configurations
```

#### **Storage Configuration Updates**
```bash
# Increase storage allocations
sudo ./setup.sh --update

# Note: PVC size can only be increased, not decreased
# Kubernetes prevents PVC size reduction for data safety
```

### 🔄 **Hot Configuration Reloads**

Some configuration changes can be applied without pod restarts:

#### **ConfigMap Updates**
```bash
# Update ConfigMaps directly
kubectl patch configmap lair-services-config -n lair --patch '{"data":{"key":"new-value"}}'

# Some applications automatically reload configuration
# Others may require pod restart
kubectl rollout restart deployment/openwebui -n lair
```

#### **Secret Updates**
```bash
# Update secrets (e.g., API keys, passwords)
kubectl patch secret lair-secrets -n lair --patch '{"data":{"key":"bmV3LXZhbHVl"}}'

# Restart affected applications
kubectl rollout restart deployment/n8n -n lair
```

---

## 🔧 Kubernetes Component Updates

### 🚀 **MicroK8s Updates**

#### **MicroK8s Core Updates**
```bash
# Check current MicroK8s version
sudo microk8s version

# Update MicroK8s to latest stable
sudo snap refresh microk8s --classic

# Or update to specific version
sudo snap refresh microk8s --channel=1.29/stable --classic

# Verify update
sudo microk8s status --wait-ready
```

#### **Addon Updates**
```bash
# Update Longhorn
sudo microk8s disable longhorn
sudo microk8s enable longhorn

# Update MetalLB
sudo microk8s disable metallb
sudo microk8s enable metallb:10.64.140.43-10.64.140.49

# Update Cert-Manager
sudo microk8s disable cert-manager
sudo microk8s enable cert-manager
```

#### **Helm Updates**
```bash
# Update Helm repositories
sudo microk8s helm3 repo update

# Update specific charts
sudo microk8s helm3 upgrade longhorn longhorn/longhorn -n longhorn-system
sudo microk8s helm3 upgrade velero vmware-tanzu/velero -n velero
```

### ☁️ **Managed Kubernetes Updates**

#### **Cluster Updates**
```bash
# For AWS EKS
aws eks update-cluster-version --name lair-cluster --kubernetes-version 1.29

# For Google GKE
gcloud container clusters upgrade lair-cluster --master --cluster-version 1.29

# For Azure AKS
az aks upgrade --resource-group lair-rg --name lair-cluster --kubernetes-version 1.29
```

#### **Node Group Updates**
```bash
# Update node groups after cluster update
# AWS EKS
aws eks update-nodegroup-version --cluster-name lair-cluster --nodegroup-name lair-nodes

# GKE (automatic with cluster update)
# AKS (automatic with cluster update)
```

#### **Component Updates**
```bash
# Update Longhorn
helm repo update
helm upgrade longhorn longhorn/longhorn -n longhorn-system

# Update NGINX Ingress Controller
helm upgrade ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx

# Update Cert-Manager
helm upgrade cert-manager jetstack/cert-manager -n cert-manager
```

---

## 🖥️ System Updates

### 🔧 **Operating System Updates**

#### **Ubuntu/Debian Systems**
```bash
# Update package lists
sudo apt update

# Upgrade packages
sudo apt upgrade -y

# Upgrade distribution (if needed)
sudo apt dist-upgrade -y

# Clean up
sudo apt autoremove -y
sudo apt autoclean
```

#### **Container Runtime Updates**
```bash
# Update containerd (MicroK8s)
sudo snap refresh microk8s --classic

# Update Docker (if used)
sudo apt update
sudo apt upgrade docker-ce docker-ce-cli containerd.io

# Restart services
sudo systemctl restart docker
```

#### **System Dependencies**
```bash
# Update Python dependencies
sudo apt update
sudo apt upgrade python3 python3-yaml

# Update network tools
sudo apt upgrade iputils-ping dnsutils curl wget

# Update security tools
sudo apt upgrade iptables ufw fail2ban
```

### 🔄 **Automated System Updates**

#### **Unattended Upgrades Setup**
```bash
# Install unattended-upgrades
sudo apt install unattended-upgrades

# Configure automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades

# Edit configuration
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

#### **Custom Update Script**
```bash
# Create system update script
sudo tee /usr/local/bin/lair-system-update.sh << 'EOF'
#!/bin/bash

echo "=== Lair System Update ==="
echo "Started: $(date)"

# Update package lists
echo "Updating package lists..."
apt update

# Upgrade packages
echo "Upgrading packages..."
apt upgrade -y

# Update MicroK8s if present
if command -v microk8s &>/dev/null; then
    echo "Updating MicroK8s..."
    snap refresh microk8s --classic
    microk8s status --wait-ready
fi

# Update Helm repositories
if command -v helm &>/dev/null; then
    echo "Updating Helm repositories..."
    helm repo update
fi

# Clean up
echo "Cleaning up..."
apt autoremove -y
apt autoclean

echo "System update completed: $(date)"
EOF

chmod +x /usr/local/bin/lair-system-update.sh
```

---

## 🛡️ Security Updates

### 🚨 **Critical Security Updates**

#### **Immediate Security Patches**
```bash
# Apply security updates immediately
sudo apt update
sudo apt upgrade -y

# Check for security advisories
sudo apt list --upgradable | grep -i security

# Apply specific security updates
sudo apt install --only-upgrade <package-name>
```

#### **Container Image Security Updates**
```bash
# Update base images
docker pull ubuntu:22.04
docker pull alpine:latest

# Update application images
docker pull ghcr.io/open-webui/open-webui:main
docker pull ollama/ollama:latest
docker pull n8nio/n8n:latest
```

#### **Kubernetes Security Updates**
```bash
# Update Kubernetes components
sudo microk8s refresh-certs

# Update RBAC policies
kubectl apply -f updated-rbac.yaml

# Update network policies
kubectl apply -f updated-network-policies.yaml
```

### 🔒 **Security Scanning**

#### **Vulnerability Scanning**
```bash
# Scan container images
trivy image ghcr.io/open-webui/open-webui:main
trivy image ollama/ollama:latest

# Scan Kubernetes cluster
kube-bench run --targets master,node

# Scan system packages
sudo apt list --upgradable | grep -i security
```

---

## 🔄 Update Strategies

### 📋 **Rolling Updates**

#### **Zero-Downtime Updates**
```bash
# Configure rolling update strategy
kubectl patch deployment openwebui -n lair -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":0,"maxSurge":1}}}}'

# Apply update
helm upgrade --install lair . -n lair -f values-myconfig.yaml

# Monitor rollout
kubectl rollout status deployment/openwebui -n lair
```

#### **Canary Deployments**
```bash
# Deploy canary version
helm upgrade --install lair . -n lair \
  --set openwebui.replicaCount=2 \
  --set openwebui.image.tag=v0.3.33-beta \
  -f values-myconfig.yaml

# Monitor canary
kubectl get pods -n lair -l app=openwebui

# Promote or rollback based on results
```

### 🔄 **Blue-Green Deployments**

#### **Blue-Green Strategy**
```bash
# Create green environment
kubectl create namespace lair-green

# Deploy to green environment
helm install lair-green . -n lair-green -f values-myconfig.yaml

# Test green environment
kubectl port-forward -n lair-green svc/openwebui 8080:80

# Switch traffic (update ingress)
kubectl patch ingress lair-ingress -n lair --patch '{"spec":{"rules":[{"host":"lair.example.com","http":{"paths":[{"path":"/","pathType":"Prefix","backend":{"service":{"name":"openwebui","namespace":"lair-green"}}}]}}]}}'

# Clean up blue environment after verification
kubectl delete namespace lair
kubectl create namespace lair
```

### 🕐 **Maintenance Windows**

#### **Scheduled Maintenance**
```bash
# Create maintenance window script
cat > /usr/local/bin/lair-maintenance-update.sh << 'EOF'
#!/bin/bash

echo "=== Lair Maintenance Update ==="
echo "Started: $(date)"

# Put system in maintenance mode
kubectl scale deployment openwebui -n lair --replicas=0
kubectl scale deployment n8n -n lair --replicas=0

# Perform updates
helm upgrade --install lair . -n lair -f values-myconfig.yaml

# Wait for deployment
kubectl rollout status deployment/openwebui -n lair
kubectl rollout status deployment/n8n -n lair

# Scale back up
kubectl scale deployment openwebui -n lair --replicas=1
kubectl scale deployment n8n -n lair --replicas=1

echo "Maintenance update completed: $(date)"
EOF

chmod +x /usr/local/bin/lair-maintenance-update.sh
```

---

## 🔍 Update Monitoring & Validation

### 📊 **Pre-Update Checks**

#### **System Health Assessment**
```bash
# Create pre-update check script
cat > /tmp/lair-pre-update-check.sh << 'EOF'
#!/bin/bash

echo "=== Lair Pre-Update Health Check ==="
echo "Timestamp: $(date)"
echo ""

# Check cluster health
echo "=== Cluster Health ==="
kubectl cluster-info
kubectl get nodes

# Check application health
echo ""
echo "=== Application Health ==="
kubectl get pods -n lair
kubectl get services -n lair

# Check storage health
echo ""
echo "=== Storage Health ==="
kubectl get pvc -n lair
df -h | grep -E "(/$|/var)"

# Check resource usage
echo ""
echo "=== Resource Usage ==="
kubectl top nodes 2>/dev/null || echo "Metrics not available"
kubectl top pods -n lair 2>/dev/null || echo "Pod metrics not available"

# Check backup status (if Velero enabled)
echo ""
echo "=== Backup Status ==="
velero backup get 2>/dev/null | head -5 || echo "Velero not available"

echo ""
echo "=== Pre-Update Check Complete ==="
EOF

chmod +x /tmp/lair-pre-update-check.sh
/tmp/lair-pre-update-check.sh
```

### 🔍 **Post-Update Validation**

#### **Update Verification Script**
```bash
# Create post-update validation script
cat > /tmp/lair-post-update-validation.sh << 'EOF'
#!/bin/bash

echo "=== Lair Post-Update Validation ==="
echo "Timestamp: $(date)"
echo ""

ISSUES_FOUND=0

# Check pod status
echo "=== Pod Status ==="
NOT_RUNNING=$(kubectl get pods -n lair --no-headers | grep -v Running | wc -l)
if [ "$NOT_RUNNING" -gt 0 ]; then
    echo "❌ $NOT_RUNNING pods not running"
    kubectl get pods -n lair | grep -v Running
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo "✅ All pods running"
fi

# Check service endpoints
echo ""
echo "=== Service Endpoints ==="
ENDPOINTS=$(kubectl get endpoints -n lair --no-headers | wc -l)
if [ "$ENDPOINTS" -eq 0 ]; then
    echo "❌ No service endpoints found"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo "✅ $ENDPOINTS service endpoints active"
fi

# Check ingress status
echo ""
echo "=== Ingress Status ==="
if kubectl get ingress -n lair &>/dev/null; then
    echo "✅ Ingress configured"
else
    echo "⚠️  No ingress found"
fi

# Test application connectivity
echo ""
echo "=== Application Connectivity ==="
if kubectl exec -n lair deployment/openwebui -- curl -f http://localhost:8080/health &>/dev/null; then
    echo "✅ OpenWebUI health check passed"
else
    echo "❌ OpenWebUI health check failed"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

if kubectl exec -n lair statefulset/ollama -- curl -f http://localhost:11434/api/tags &>/dev/null; then
    echo "✅ Ollama health check passed"
else
    echo "❌ Ollama health check failed"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

echo ""
if [ $ISSUES_FOUND -eq 0 ]; then
    echo "🎉 Post-update validation PASSED - no issues found"
else
    echo "⚠️  Post-update validation found $ISSUES_FOUND issues"
fi
EOF

chmod +x /tmp/lair-post-update-validation.sh
/tmp/lair-post-update-validation.sh
```

---

## 🔄 Rollback Procedures

### ⏪ **Application Rollback**

#### **Helm Rollback**
```bash
# Check release history
helm history lair -n lair

# Rollback to previous version
helm rollback lair -n lair

# Rollback to specific revision
helm rollback lair 2 -n lair

# Verify rollback
kubectl get pods -n lair
kubectl rollout status deployment/openwebui -n lair
```

#### **Kubernetes Rollback**
```bash
# Rollback specific deployment
kubectl rollout undo deployment/openwebui -n lair

# Rollback to specific revision
kubectl rollout undo deployment/openwebui -n lair --to-revision=2

# Check rollout status
kubectl rollout status deployment/openwebui -n lair
```

### 🔄 **System Rollback**

#### **Package Rollback**
```bash
# Hold packages at current version
sudo apt-mark hold microk8s

# Downgrade specific package
sudo apt install package-name=version

# Remove hold
sudo apt-mark unhold microk8s
```

#### **Snapshot Rollback**
```bash
# If using LVM snapshots
sudo lvconvert --merge /dev/vg0/root-snapshot

# If using filesystem snapshots
sudo btrfs subvolume snapshot /root-backup /

# Reboot to activate snapshot
sudo reboot
```

---

## 🎯 Best Practices

### 🚀 **Update Best Practices**
- **Backup First**: Always backup before updates
- **Test Updates**: Test in non-production environment first
- **Staged Rollout**: Update components in logical order
- **Monitor Progress**: Monitor update progress and system health
- **Validate Results**: Verify functionality after updates

### 🔒 **Safety Best Practices**
- **Maintenance Windows**: Schedule updates during low-usage periods
- **Rollback Plan**: Always have a rollback plan ready
- **Health Checks**: Implement comprehensive health checks
- **Gradual Updates**: Update gradually, not all at once
- **Communication**: Communicate update schedules to users

### 📊 **Operational Best Practices**
- **Regular Schedule**: Maintain regular update schedule
- **Security Priority**: Prioritize security updates
- **Documentation**: Document all update procedures
- **Automation**: Automate routine updates where possible
- **Monitoring**: Monitor for available updates regularly

---

**🎯 Ready to keep your system updated?** Continue with [Monitoring & Health](../monitoring/README.md) or explore [Backup Procedures](../backup-restore/README.md)!
