# 🧹 Cleanup & Maintenance Procedures

> **Complete guide to system cleanup, maintenance, and complete removal procedures for Lair**

This guide covers all cleanup and maintenance procedures, from regular maintenance tasks to complete system removal and environment restoration.

---

## 🎯 Overview

Lair provides comprehensive cleanup and maintenance tools to keep your system healthy, remove unused resources, and completely uninstall components when needed.

### 🏗️ **Cleanup Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                      🧹 CLEANUP LEVELS                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Application   │  │     System      │  │    Complete     │  │
│  │    Cleanup      │  │   Maintenance   │  │    Removal      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🎯 CLEANUP TARGETS                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │  Lair Apps      │  │   Kubernetes    │  │   System        │  │
│  │ (Helm Release)  │  │   Components    │  │ Configuration   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🗄️ DATA PRESERVATION                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Safe Mode     │  │  Selective      │  │   Complete      │  │
│  │ (Keep Data)     │  │  Removal        │  │   Wipe          │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📊 **Cleanup Types**

| Type | Scope | Data Safety | Use Case |
|------|-------|-------------|----------|
| **Application Cleanup** | Lair apps only | Data preserved | Remove apps, keep cluster |
| **Selective Cleanup** | Specific components | User choice | Targeted removal |
| **System Maintenance** | Unused resources | Data preserved | Regular maintenance |
| **Complete Removal** | Everything | User choice | Full uninstall |

---

## 🧹 Application Cleanup

### 🚀 **Lair Application Removal**

The primary cleanup script removes all Lair applications while preserving the underlying Kubernetes cluster.

#### **Basic Application Cleanup**
```bash
# Navigate to helm-chart directory
cd helm-chart/

# Run cleanup script (interactive)
sudo ./cleanup.sh

# The script will:
# 1. Detect environment (MicroK8s or managed K8s)
# 2. Show what will be removed
# 3. Ask for confirmation
# 4. Remove Lair applications safely
```

#### **What Gets Removed**
- **Helm Release**: Complete Lair Helm deployment
- **Kubernetes Resources**: All pods, services, deployments, statefulsets
- **Certificates**: TLS certificates (Let's Encrypt, mkcert)
- **Ingress Rules**: All Lair ingress configurations
- **ConfigMaps & Secrets**: Application configuration and secrets

#### **What Gets Preserved**
- **Persistent Volumes**: All user data (unless explicitly deleted)
- **Storage Classes**: Longhorn, Hostpath storage classes
- **Kubernetes Cluster**: MicroK8s or managed cluster remains
- **System Components**: Ingress controller, cert-manager, etc.

### 🔧 **Advanced Cleanup Options**

#### **Cleanup with Storage Removal**
```bash
# Run cleanup script
sudo ./cleanup.sh

# When prompted about storage cleanup, choose 'y'
# This will remove:
# - Local storage directories
# - Longhorn data (if applicable)
# - Container images
```

#### **Selective Resource Cleanup**
```bash
# Remove specific namespace only
kubectl delete namespace lair

# Remove specific application
helm uninstall lair -n lair

# Clean up orphaned resources
kubectl delete pvc --all -n lair
kubectl delete secrets --all -n lair
```

---

## 🔧 System Maintenance

### 📋 **Regular Maintenance Tasks**

#### **Container Image Cleanup**
```bash
# For MicroK8s
sudo microk8s ctr images list | grep lair
sudo microk8s ctr images rm <image-name>

# For managed K8s (with crictl)
sudo crictl images | grep lair
sudo crictl rmi <image-id>

# For managed K8s (with docker)
sudo docker images | grep lair
sudo docker rmi <image-name>
```

#### **Storage Cleanup**
```bash
# Check storage usage
kubectl get pv
kubectl get pvc -A
df -h

# Clean up unused PVCs
kubectl get pvc -A | grep -E "(Available|Released)"
kubectl delete pvc <unused-pvc> -n <namespace>

# Longhorn volume cleanup (if applicable)
kubectl get volumes.longhorn.io -n longhorn-system
kubectl delete volume.longhorn.io <volume-name> -n longhorn-system
```

#### **Log Cleanup**
```bash
# System logs
sudo journalctl --vacuum-time=7d
sudo journalctl --vacuum-size=1G

# Kubernetes logs
sudo find /var/log/pods -name "*.log" -mtime +7 -delete
sudo find /var/lib/docker/containers -name "*.log" -mtime +7 -delete

# Lair setup logs
sudo find /var/log -name "*lair*" -mtime +30 -delete
sudo find /var/log -name "*microk8s*" -mtime +30 -delete
```

#### **Network Cleanup**
```bash
# Clean up unused network policies
kubectl get networkpolicies -A
kubectl delete networkpolicy <unused-policy> -n <namespace>

# Clean up unused services
kubectl get services -A | grep -E "(ClusterIP.*<none>|LoadBalancer.*<pending>)"

# Clean up unused ingress rules
kubectl get ingress -A
kubectl delete ingress <unused-ingress> -n <namespace>
```

### 🔄 **Automated Maintenance**

#### **Create Maintenance Script**
```bash
# Create automated maintenance script
sudo tee /usr/local/bin/lair-maintenance.sh << 'EOF'
#!/bin/bash

echo "=== Lair System Maintenance ==="
echo "Started: $(date)"

# Clean up old logs
echo "Cleaning up old logs..."
journalctl --vacuum-time=7d
find /var/log/pods -name "*.log" -mtime +7 -delete 2>/dev/null || true

# Clean up unused container images
echo "Cleaning up unused container images..."
if command -v microk8s &>/dev/null; then
    microk8s ctr images prune
elif command -v crictl &>/dev/null; then
    crictl rmi --prune
elif command -v docker &>/dev/null; then
    docker image prune -f
fi

# Check storage usage
echo "Storage usage:"
df -h | grep -E "(/$|/var|/home)"

# Check Kubernetes resource usage
echo "Kubernetes resources:"
kubectl top nodes 2>/dev/null || echo "Metrics not available"
kubectl get pvc -A | grep -E "(Bound|Available|Released)" | wc -l | xargs echo "PVCs:"

echo "Maintenance completed: $(date)"
EOF

chmod +x /usr/local/bin/lair-maintenance.sh
```

#### **Schedule Maintenance**
```bash
# Add to crontab for weekly maintenance
crontab -e

# Add this line for weekly maintenance on Sunday at 2 AM
0 2 * * 0 /usr/local/bin/lair-maintenance.sh >> /var/log/lair-maintenance.log 2>&1
```

---

## 🗑️ Complete System Removal

### 🚨 **Complete Lair Removal**

For complete removal of Lair and all associated components:

#### **Step 1: Remove Lair Applications**
```bash
# Remove all Lair applications
cd helm-chart/
sudo ./cleanup.sh

# Choose to remove storage when prompted
```

#### **Step 2: Remove Kubernetes Components (MicroK8s)**
```bash
# For MicroK8s environments
cd microk8s/
sudo ./teardown.sh

# This removes:
# - Complete MicroK8s installation
# - All addons (Longhorn, MetalLB, etc.)
# - Network configurations
# - DNS configurations
# - System modifications
```

#### **Step 3: Remove Kubernetes Components (Managed)**
```bash
# For managed Kubernetes environments
cd k8s-managed/
sudo ./teardown.sh

# This removes:
# - Longhorn storage system
# - NGINX Ingress Controller
# - Cert-Manager
# - Velero backup system
# - Associated namespaces and CRDs
```

### 🔧 **Manual Cleanup Verification**

#### **Verify Complete Removal**
```bash
# Check for remaining Kubernetes resources
kubectl get all -A 2>/dev/null || echo "kubectl not available"

# Check for remaining storage
df -h | grep -E "(longhorn|lair)"

# Check for remaining processes
ps aux | grep -E "(microk8s|longhorn|lair)"

# Check for remaining network configurations
ip route | grep -E "(10\.|172\.|192\.168\.)"
iptables -L | grep -E "(microk8s|longhorn)"
```

#### **Clean Up Remaining Files**
```bash
# Remove remaining configuration files
sudo rm -rf /var/lib/longhorn/
sudo rm -rf /var/lib/rancher/
sudo rm -rf /opt/lair/
sudo rm -rf ~/.kube/config

# Remove remaining logs
sudo rm -rf /var/log/lair*
sudo rm -rf /var/log/microk8s*
sudo rm -rf /var/log/longhorn*

# Remove remaining systemd services
sudo systemctl list-units | grep -E "(microk8s|longhorn|lair)"
# Remove any found services with:
# sudo systemctl disable <service-name>
# sudo rm /etc/systemd/system/<service-name>
```

---

## 🚨 Emergency Cleanup Procedures

### 🔧 **Stuck Resource Cleanup**

#### **Remove Stuck Namespaces**
```bash
# Get stuck namespace
kubectl get namespaces | grep Terminating

# Force remove stuck namespace
kubectl get namespace <stuck-namespace> -o json > temp-namespace.json
# Edit temp-namespace.json and remove finalizers array
kubectl replace --raw "/api/v1/namespaces/<stuck-namespace>/finalize" -f temp-namespace.json
```

#### **Remove Stuck PVCs**
```bash
# Remove finalizers from stuck PVCs
kubectl patch pvc <stuck-pvc> -n <namespace> -p '{"metadata":{"finalizers":null}}'

# Force delete stuck PVCs
kubectl delete pvc <stuck-pvc> -n <namespace> --force --grace-period=0
```

#### **Remove Stuck Pods**
```bash
# Force delete stuck pods
kubectl delete pod <stuck-pod> -n <namespace> --force --grace-period=0

# Remove from node if still stuck
kubectl patch pod <stuck-pod> -n <namespace> -p '{"metadata":{"finalizers":null}}'
```

### 🔄 **Recovery from Failed Cleanup**

#### **Longhorn Cleanup Issues**
```bash
# If Longhorn cleanup fails
kubectl delete validatingwebhookconfiguration longhorn-webhook-validator
kubectl delete mutatingwebhookconfiguration longhorn-webhook-mutator

# Remove all Longhorn CRDs
kubectl get crd | grep longhorn | awk '{print $1}' | xargs kubectl delete crd

# Force remove Longhorn namespace
kubectl patch namespace longhorn-system -p '{"metadata":{"finalizers":null}}'
kubectl delete namespace longhorn-system --force --grace-period=0
```

#### **MicroK8s Cleanup Issues**
```bash
# If MicroK8s won't uninstall
sudo snap remove microk8s --purge

# Manual cleanup
sudo rm -rf /var/snap/microk8s/
sudo rm -rf /snap/microk8s/
sudo userdel -r microk8s 2>/dev/null || true
sudo groupdel microk8s 2>/dev/null || true

# Network cleanup
sudo iptables -F
sudo iptables -X
sudo iptables -t nat -F
sudo iptables -t nat -X
```

---

## 📊 Cleanup Monitoring & Verification

### 🔍 **Pre-Cleanup Assessment**

#### **Resource Inventory**
```bash
# Create cleanup assessment script
cat > /tmp/lair-cleanup-assessment.sh << 'EOF'
#!/bin/bash

echo "=== Lair Cleanup Assessment ==="
echo "Timestamp: $(date)"
echo ""

# Kubernetes resources
echo "=== Kubernetes Resources ==="
kubectl get all -n lair 2>/dev/null || echo "Lair namespace not found"
kubectl get pvc -n lair 2>/dev/null || echo "No PVCs in lair namespace"
kubectl get secrets -n lair 2>/dev/null || echo "No secrets in lair namespace"

# Storage usage
echo ""
echo "=== Storage Usage ==="
df -h | grep -E "(/$|/var|longhorn)"

# Container images
echo ""
echo "=== Container Images ==="
if command -v microk8s &>/dev/null; then
    microk8s ctr images list | grep -E "(lair|ollama|openwebui|n8n|comfyui|minio)" | wc -l | xargs echo "Lair images:"
elif command -v crictl &>/dev/null; then
    crictl images | grep -E "(lair|ollama|openwebui|n8n|comfyui|minio)" | wc -l | xargs echo "Lair images:"
fi

# Network resources
echo ""
echo "=== Network Resources ==="
kubectl get ingress -A | grep lair || echo "No Lair ingress found"
kubectl get services -n lair 2>/dev/null || echo "No services in lair namespace"

echo ""
echo "=== Assessment Complete ==="
EOF

chmod +x /tmp/lair-cleanup-assessment.sh
/tmp/lair-cleanup-assessment.sh
```

### 🔍 **Post-Cleanup Verification**

#### **Cleanup Verification Script**
```bash
# Create verification script
cat > /tmp/lair-cleanup-verification.sh << 'EOF'
#!/bin/bash

echo "=== Lair Cleanup Verification ==="
echo "Timestamp: $(date)"
echo ""

ISSUES_FOUND=0

# Check for remaining Kubernetes resources
echo "=== Checking Kubernetes Resources ==="
if kubectl get namespace lair &>/dev/null; then
    echo "❌ Lair namespace still exists"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo "✅ Lair namespace removed"
fi

# Check for remaining Helm releases
echo ""
echo "=== Checking Helm Releases ==="
if helm list -A | grep -q lair; then
    echo "❌ Lair Helm releases still exist"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo "✅ No Lair Helm releases found"
fi

# Check for remaining storage
echo ""
echo "=== Checking Storage ==="
if ls /var/lib/longhorn/lair* &>/dev/null; then
    echo "❌ Lair storage directories still exist"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    echo "✅ No Lair storage directories found"
fi

# Check for remaining container images
echo ""
echo "=== Checking Container Images ==="
if command -v microk8s &>/dev/null; then
    LAIR_IMAGES=$(microk8s ctr images list | grep -E "(lair|ollama|openwebui|n8n|comfyui|minio)" | wc -l)
elif command -v crictl &>/dev/null; then
    LAIR_IMAGES=$(crictl images | grep -E "(lair|ollama|openwebui|n8n|comfyui|minio)" | wc -l)
else
    LAIR_IMAGES=0
fi

if [ "$LAIR_IMAGES" -gt 0 ]; then
    echo "⚠️  $LAIR_IMAGES Lair container images still present"
else
    echo "✅ No Lair container images found"
fi

echo ""
if [ $ISSUES_FOUND -eq 0 ]; then
    echo "🎉 Cleanup verification PASSED - no issues found"
else
    echo "⚠️  Cleanup verification found $ISSUES_FOUND issues"
fi
EOF

chmod +x /tmp/lair-cleanup-verification.sh
/tmp/lair-cleanup-verification.sh
```

---

## 🎯 Best Practices

### 🚀 **Cleanup Best Practices**
- **Backup First**: Always backup important data before cleanup
- **Gradual Approach**: Start with application cleanup, then system components
- **Verification**: Always verify cleanup completion
- **Documentation**: Document what was removed for future reference
- **Testing**: Test cleanup procedures in non-production environments

### 🔒 **Safety Best Practices**
- **Confirmation**: Always confirm destructive operations
- **Data Preservation**: Understand what data will be lost
- **Rollback Plan**: Have a plan to restore if needed
- **Monitoring**: Monitor system during cleanup operations
- **Staged Removal**: Remove components in logical order

### 📊 **Maintenance Best Practices**
- **Regular Schedule**: Perform maintenance on a regular schedule
- **Automation**: Automate routine maintenance tasks
- **Monitoring**: Monitor resource usage and cleanup effectiveness
- **Documentation**: Keep maintenance logs and procedures updated
- **Capacity Planning**: Plan for growth and resource needs

---

**🎯 Ready to clean up your system?** Continue with [Updates & Upgrades](../updates/README.md) or explore [Backup Procedures](../backup-restore/README.md)!
