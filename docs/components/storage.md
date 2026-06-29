# 💾 Storage Configuration Guide

> **Complete guide to storage solutions in Lair: Longhorn distributed storage and Hostpath provisioner**

This guide covers all aspects of storage configuration in Lair, from Longhorn distributed storage for standard deployments to Hostpath provisioner for Jetson edge computing.

---

## 🎯 Overview

Lair uses different storage strategies based on the deployment platform to optimize performance, reliability, and resource usage. The storage layer provides persistent volumes for all applications and ensures data durability.

### 🏗️ **Storage Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                       📦 APPLICATION LAYER                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ PersistentVolume│  │ PersistentVolume│  │ PersistentVolume│  │
│  │    Claims       │  │    Claims       │  │    Claims       │  │
│  │  (OpenWebUI)    │  │   (Ollama)      │  │ (PostgreSQL)    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                       ⚙️ STORAGE CLASSES                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   lair-storage  │  │ lair-hostpath   │  │    Custom       │  │
│  │   (Longhorn)    │  │   (Jetson)      │  │  StorageClass   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                       💽 STORAGE BACKENDS                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │    Longhorn     │  │    Hostpath     │  │  Cloud Storage  │  │
│  │  (Distributed)  │  │    (Local)      │  │ (EBS/PD/Disk)   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📊 **Storage Strategy by Platform**

| Platform | Primary Storage | Backup Storage | Replication | Use Case |
|----------|----------------|----------------|-------------|----------|
| **Standard x86_64** | Longhorn | Cloud/S3 | 1-3 replicas | Production, Development |
| **NVIDIA Jetson** | Hostpath | S3/MinIO | None | Edge Computing |
| **Cloud Managed** | Cloud + Longhorn | Cloud Native | 1-3 replicas | Enterprise |

---

## 🏗️ Longhorn Distributed Storage

### 🎯 **Overview**
Longhorn is a lightweight, reliable, and easy-to-use distributed block storage system for Kubernetes. It's the default storage solution for standard x86_64 deployments.

### ✨ **Key Features**
- **📊 Distributed Storage**: Data replicated across multiple nodes
- **📸 Snapshots**: Point-in-time volume snapshots
- **🔄 Backup & Restore**: Incremental backups to S3-compatible storage
- **📈 Volume Expansion**: Dynamic volume resizing
- **🔧 Web UI**: Graphical management interface
- **🛡️ Data Protection**: Automatic replica management and healing

### 🔧 **Installation & Configuration**

#### **Automatic Installation (MicroK8s)**
Longhorn is automatically installed during MicroK8s setup:

```bash
# Installed by microk8s/lib/microk8s_longhorn.sh
# - Dependencies: open-iscsi, nfs-common, util-linux
# - Helm chart installation with MicroK8s-specific settings
# - Automatic replica count based on node count
# - Default StorageClass creation
```

#### **Manual Installation (Managed K8s)**
```bash
# Add Longhorn Helm repository
helm repo add longhorn https://charts.longhorn.io
helm repo update

# Install Longhorn
helm install longhorn longhorn/longhorn \
  --namespace longhorn-system \
  --create-namespace \
  --set defaultSettings.defaultReplicaCount=1 \
  --set persistence.defaultClass=true
```

#### **Configuration Options**
```yaml
# Longhorn Helm values
longhorn:
  defaultSettings:
    # Replica configuration
    defaultReplicaCount: 1                    # Auto-calculated based on nodes
    allowVolumeCreationWithDegradedAvailability: true
    
    # Storage configuration
    defaultDataPath: "/var/lib/longhorn"      # Storage location on nodes
    defaultDataLocality: "disabled"           # Data locality policy
    
    # Backup configuration
    backupTarget: ""                          # S3 URL for backups (optional)
    backupTargetCredentialSecret: ""          # S3 credentials secret
    
    # Performance tuning
    guaranteedEngineManagerCPU: 12            # CPU percentage for engine manager
    guaranteedReplicaManagerCPU: 12           # CPU percentage for replica manager
    
  # Storage class configuration
  persistence:
    defaultClass: true                        # Set as default StorageClass
    defaultClassReplicaCount: 1               # Replicas for default class
    reclaimPolicy: Retain                     # Volume reclaim policy
  
  # UI configuration
  ingress:
    enabled: false                            # Longhorn UI ingress (optional)
```

### 📦 **Multi-Disk Management**

#### **Automatic Disk Detection & Configuration**
Since v1.2.4, Lair automatically detects and configures additional disks for Longhorn storage on both MicroK8s and Managed K8s deployments.

**Supported Disk Types:**
- **NVMe SSDs**: High-performance solid-state drives
- **SATA SSDs**: Standard solid-state drives  
- **HDDs**: Traditional hard disk drives

**Automatic Process:**
```bash
# During installation, the script:
# 1. Detects all unused disks (>10GB, no partitions, not mounted)
# 2. Identifies disk type (nvme/ssd/hdd) automatically
# 3. Prompts for confirmation before initializing
# 4. Formats disk with ext4 filesystem
# 5. Mounts disk to /var/lib/longhorn/diskN
# 6. Adds disk to Longhorn node configuration
# 7. Applies appropriate tags based on disk type
```

#### **Multi-Disk Configuration Examples**

**Example 1: Single Additional NVMe (nexidovh9)**
```bash
System Disk: nvme1n1 (477GB) → /
Additional: nvme0n1 (477GB) → Longhorn

# Automatic configuration:
{
  "default-disk": {
    "path": "/var/lib/longhorn/",
    "storageReserved": 128GB,          # Optimized
    "tags": []
  },
  "nvme-disk2": {
    "path": "/var/lib/longhorn/disk2/longhorn",
    "storageReserved": 10GB,
    "tags": ["nvme", "additional"]     # Auto-detected
  }
}

# Total usable: ~950GB
```

**Example 2: Single Additional HDD (nexidovh2)**
```bash
System Disk: sda (3.6TB) → /
Additional: sdb (3.6TB) → Longhorn

# Automatic configuration:
{
  "default-disk": {
    "path": "/var/lib/longhorn/",
    "storageReserved": 128GB,          # Optimized
    "tags": []
  },
  "hdd-disk2": {
    "path": "/var/lib/longhorn/disk2/longhorn",
    "storageReserved": 10GB,
    "tags": ["hdd", "additional"]      # Auto-detected
  }
}

# Total usable: ~7.1TB
```

**Example 3: Mixed Disk Types**
```bash
System: sda (500GB SSD) → /
Additional: nvme0n1 (1TB NVMe) → Longhorn
Additional: sdb (4TB HDD) → Longhorn

# Automatic configuration:
{
  "default-disk": {
    "path": "/var/lib/longhorn/",
    "storageReserved": 128GB,
    "tags": []
  },
  "nvme-disk2": {
    "path": "/var/lib/longhorn/disk2/longhorn",
    "storageReserved": 10GB,
    "tags": ["nvme", "additional"]
  },
  "hdd-disk3": {
    "path": "/var/lib/longhorn/disk3/longhorn",
    "storageReserved": 10GB,
    "tags": ["hdd", "additional"]
  }
}

# Total usable: ~5.5TB (500GB SSD + 1TB NVMe + 4TB HDD)
```

#### **Storage Reservation Optimization**

**Intelligent Storage Allocation (v1.2.6+):**
The system automatically optimizes storage reservation to maximize usable space:

```bash
# Logic: min(30% of disk, 128GB max)

Small disks (<427GB):
  Reserved = 30% of disk size
  Example: 300GB disk → 90GB reserved

Large disks (≥427GB):
  Reserved = 128GB (cap)
  Example: 3.6TB disk → 128GB reserved (only 3.5%)
```

**Before vs After Optimization:**

| Disk Size | Before (30%) | After (Optimized) | Gain |
|-----------|--------------|-------------------|------|
| 300GB | 90GB | 90GB | - |
| 1TB | 307GB | 128GB | +179GB |
| 3.6TB | 1.1TB | 128GB | +972GB |

**Benefits:**
- ✅ Small disks: Proportional reservation (sufficient for OS)
- ✅ Large disks: Fixed 128GB cap (maximizes usable space)
- ✅ Automatic: No manual intervention required
- ✅ Per-disk: Each disk optimized individually

#### **Manual Disk Management**

**Add Additional Disk Manually:**
```bash
# 1. Identify available disk
lsblk

# 2. Clean disk (if needed)
sudo wipefs -a /dev/sdc
sudo dd if=/dev/zero of=/dev/sdc bs=1M count=100

# 3. Verify disk is clean
sudo blkid /dev/sdc  # Should return nothing

# 4. Format and mount
sudo mkfs.ext4 -L LH3 /dev/sdc
sudo mkdir -p /var/lib/longhorn/disk3
sudo mount /dev/sdc /var/lib/longhorn/disk3

# 5. Add to fstab
UUID=$(sudo blkid -s UUID -o value /dev/sdc)
echo "UUID=$UUID /var/lib/longhorn/disk3 ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# 6. Add to Longhorn
kubectl patch nodes.longhorn.io -n longhorn-system $(hostname) --type='merge' -p '{
  "spec": {
    "disks": {
      "ssd-disk3": {
        "path": "/var/lib/longhorn/disk3/longhorn",
        "allowScheduling": true,
        "evictionRequested": false,
        "storageReserved": 10737418240,
        "tags": ["ssd", "additional", "manual"]
      }
    }
  }
}'
```

**Verify Disk Addition:**
```bash
# Check disk is mounted
df -h | grep longhorn

# Check Longhorn configuration
kubectl get nodes.longhorn.io -n longhorn-system $(hostname) -o jsonpath='{.spec.disks}' | jq .

# Check disk status in Longhorn UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80
# Access: http://localhost:8080 → Node → Select node → View disks
```

**Optimize Storage Reservation:**
```bash
# Get current reservation
current_reserved=$(kubectl get nodes.longhorn.io -n longhorn-system $(hostname) \
  -o jsonpath='{.spec.disks.default-disk.storageReserved}')

echo "Current: $((current_reserved / 1024 / 1024 / 1024))GB"

# Optimize to 128GB (for large disks)
kubectl patch nodes.longhorn.io -n longhorn-system $(hostname) --type='json' -p '[
  {
    "op": "replace",
    "path": "/spec/disks/default-disk/storageReserved",
    "value": 137438953472
  }
]'

# Verify
kubectl get nodes.longhorn.io -n longhorn-system $(hostname) \
  -o jsonpath='{.spec.disks.default-disk.storageReserved}' | \
  awk '{print "Optimized: " $0/1024/1024/1024 "GB"}'
```

**Remove Disk from Longhorn:**
```bash
# 1. Disable scheduling on disk
kubectl patch nodes.longhorn.io -n longhorn-system $(hostname) --type='merge' -p '{
  "spec": {
    "disks": {
      "ssd-disk3": {
        "allowScheduling": false
      }
    }
  }
}'

# 2. Wait for replicas to migrate (check Longhorn UI)

# 3. Remove disk from Longhorn
kubectl patch nodes.longhorn.io -n longhorn-system $(hostname) --type='json' -p '[
  {
    "op": "remove",
    "path": "/spec/disks/ssd-disk3"
  }
]'

# 4. Unmount and clean
sudo umount /var/lib/longhorn/disk3
sudo sed -i '/disk3/d' /etc/fstab
sudo rm -rf /var/lib/longhorn/disk3
```

#### **Disk Selection Strategies**

**By Disk Type (Performance-based):**
```yaml
# Use fast NVMe disks for databases
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-fast
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "1"
  diskSelector: "nvme"            # Only NVMe disks
  nodeSelector: ""
reclaimPolicy: Retain
```

**By Additional Tag:**
```yaml
# Use only additional disks (not system disk)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-additional
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "2"
  diskSelector: "additional"      # Only additional disks
reclaimPolicy: Delete
```

**By Specific Type:**
```yaml
# Use HDDs for large, less-frequently accessed data
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-archive
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "2"
  diskSelector: "hdd"             # Only HDD disks
  dataLocality: "disabled"
reclaimPolicy: Retain
```

### 📊 **Storage Monitoring**

#### **Check Disk Usage**
```bash
# System-level disk usage
df -h | grep longhorn

# Longhorn volume usage
kubectl get volumes.longhorn.io -n longhorn-system \
  -o custom-columns=NAME:.metadata.name,SIZE:.spec.size,STATE:.status.state

# Per-disk usage in Longhorn
kubectl get nodes.longhorn.io -n longhorn-system -o json | \
  jq '.items[] | {
    node: .metadata.name,
    disks: .status.diskStatus | 
      to_entries | 
      map({
        name: .key,
        total: (.value.storageMaximum / 1024 / 1024 / 1024 | round),
        used: ((.value.storageMaximum - .value.storageAvailable) / 1024 / 1024 / 1024 | round),
        available: (.value.storageAvailable / 1024 / 1024 / 1024 | round)
      })
  }'
```

#### **Monitor Disk Health**
```bash
# Check disk conditions
kubectl get nodes.longhorn.io -n longhorn-system -o json | \
  jq '.items[] | {
    node: .metadata.name,
    conditions: .status.conditions | 
      map({type: .type, status: .status, reason: .reason})
  }'

# Check for disk pressure
kubectl get nodes.longhorn.io -n longhorn-system -o json | \
  jq '.items[] | select(.status.diskStatus | 
    to_entries | 
    any(.value.storageAvailable < (.value.storageMaximum * 0.1))
  ) | .metadata.name'
```

### 🔍 **Verification & Management**

#### **Check Installation Status**
```bash
# Check Longhorn pods
kubectl get pods -n longhorn-system

# Check storage class
kubectl get storageclass longhorn

# Check Longhorn nodes
kubectl get nodes.longhorn.io -n longhorn-system
```

#### **Access Longhorn UI**
```bash
# Port forward to access UI
kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80

# Access UI at: http://localhost:8080
# Or configure ingress for permanent access
```

#### **Volume Management**
```bash
# List Longhorn volumes
kubectl get volumes.longhorn.io -n longhorn-system

# Check volume details
kubectl describe volume.longhorn.io <volume-name> -n longhorn-system

# List persistent volumes
kubectl get pv | grep longhorn
```

### 📸 **Snapshots & Backups**

#### **Volume Snapshots**
```bash
# Create snapshot via Longhorn UI or CLI
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: openwebui-snapshot-$(date +%Y%m%d)
  namespace: longhorn-system
spec:
  volume: pvc-openwebui-data
EOF

# List snapshots
kubectl get snapshots.longhorn.io -n longhorn-system
```

#### **Backup Configuration**
```yaml
# Configure S3 backup target
apiVersion: v1
kind: Secret
metadata:
  name: s3-backup-secret
  namespace: longhorn-system
type: Opaque
data:
  AWS_ACCESS_KEY_ID: <base64-encoded-key>
  AWS_SECRET_ACCESS_KEY: <base64-encoded-secret>
  AWS_ENDPOINTS: <base64-encoded-endpoint>
---
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-target
  namespace: longhorn-system
spec:
  value: "s3://my-backup-bucket@us-east-1/"
---
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-target-credential-secret
  namespace: longhorn-system
spec:
  value: "s3-backup-secret"
```

#### **Automated Backups**
```bash
# Create recurring backup job
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: daily-backup
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"          # Daily at 2 AM
  task: "backup"
  groups:
  - default
  retain: 7                   # Keep 7 backups
  concurrency: 2              # Max concurrent backups
EOF
```

### 🚨 **Troubleshooting Longhorn**

#### **Common Issues**

##### **Pods Stuck in Pending**
```bash
# Check node requirements
kubectl describe nodes

# Check iSCSI daemon
sudo systemctl status iscsid
sudo systemctl status open-iscsi

# Install missing dependencies
sudo apt update
sudo apt install open-iscsi nfs-common util-linux
sudo systemctl enable --now iscsid
```

##### **Volume Mount Failures**
```bash
# Check Longhorn engine logs
kubectl logs -n longhorn-system -l app=longhorn-engine

# Check instance manager logs
kubectl logs -n longhorn-system -l app=longhorn-instance-manager

# Check volume attachment
kubectl get volumeattachments
```

##### **Performance Issues**
```bash
# Check disk performance
sudo fio --name=test --ioengine=libaio --rw=randrw --bs=4k --numjobs=1 --size=1G --runtime=60 --direct=1

# Check network latency between nodes
kubectl run network-test --image=busybox --rm -it -- ping <node-ip>

# Adjust Longhorn settings for performance
kubectl patch setting.longhorn.io guaranteed-engine-manager-cpu -n longhorn-system -p '{"spec":{"value":"20"}}'
```

---

## 📁 Hostpath Provisioner (Jetson)

### 🎯 **Overview**
Hostpath provisioner creates persistent volumes using local node storage. This is the optimal solution for NVIDIA Jetson devices where distributed storage would be inefficient.

### ✨ **Key Features**
- **🚀 High Performance**: Direct local storage access
- **💾 SD Card Optimized**: Optimized for flash storage characteristics
- **⚡ Low Overhead**: Minimal resource consumption
- **🔧 Simple Management**: No complex configuration required
- **📱 Edge Computing**: Perfect for single-node edge deployments

### 🔧 **Installation & Configuration**

#### **Automatic Installation (Jetson)**
Hostpath is automatically configured for Jetson platforms:

```bash
# Configured by microk8s/lib/microk8s_hostpath.sh
# - Enable hostpath-storage addon
# - Set as default StorageClass
# - Optimize for Jetson platform
```

#### **Manual Configuration**
```bash
# Enable hostpath storage addon
microk8s enable hostpath-storage

# Verify installation
kubectl get storageclass microk8s-hostpath
kubectl get pods -n kube-system -l app=hostpath-provisioner
```

#### **Storage Class Configuration**
```yaml
# Hostpath StorageClass (automatically created)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: microk8s-hostpath
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: microk8s.io/hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
parameters:
  pvDir: /var/snap/microk8s/common/default-storage
```

### 📊 **Storage Optimization for Jetson**

#### **SD Card Optimization**
```bash
# Recommended SD card settings for Jetson
# Use high-quality, high-endurance SD cards (Class 10, UHS-I or better)

# Mount options for better performance
# Add to /etc/fstab:
/dev/mmcblk0p1 /var/snap/microk8s/common/default-storage ext4 defaults,noatime,commit=60 0 2
```

#### **Storage Layout**
```bash
# Jetson storage organization
/var/snap/microk8s/common/default-storage/
├── openwebui-data/          # OpenWebUI documents and config
├── ollama-models/           # LLM models (largest storage user)
├── n8n-workflows/           # N8N workflow data
├── postgresql-data/         # Database files
├── redis-data/              # Redis persistence
└── minio-data/              # MinIO object storage (if enabled)
```

#### **Performance Tuning**
```yaml
# Jetson-optimized resource allocation
openWebUI:
  persistence:
    size: 10Gi                # Moderate size for documents
    
ollama:
  persistence:
    size: 30Gi                # Larger for models
    
n8n:
  persistence:
    size: 5Gi                 # Small for workflows
    
postgres:
  persistence:
    size: 5Gi                 # Small for database
```

### 🔍 **Monitoring Hostpath Storage**

#### **Check Storage Usage**
```bash
# Check overall storage usage
df -h /var/snap/microk8s/common/default-storage

# Check individual PV usage
kubectl get pv -o custom-columns=NAME:.metadata.name,SIZE:.spec.capacity.storage,USED:.status.phase

# Check PVC usage
kubectl exec -n lair deployment/lair-openwebui -- df -h /app/backend/data
```

#### **Storage Cleanup**
```bash
# Clean up unused volumes (careful!)
kubectl get pv | grep Released

# Manual cleanup of hostpath directories
sudo find /var/snap/microk8s/common/default-storage -type d -empty -delete

# Check for large files
sudo du -sh /var/snap/microk8s/common/default-storage/*
```

---

## ☁️ Cloud Storage Integration

### 🎯 **Overview**
For managed Kubernetes deployments, Lair can leverage cloud-native storage solutions alongside Longhorn for optimal performance and integration.

### 🔧 **Multi-Storage Strategy**

#### **AWS EKS**
```yaml
# Use EBS for databases, Longhorn for applications
postgres:
  persistence:
    storageClass: gp3          # AWS EBS GP3 for database
    
openWebUI:
  persistence:
    storageClass: longhorn     # Longhorn for application data
```

#### **Google GKE**
```yaml
# Use Persistent Disk for databases, Longhorn for applications
postgres:
  persistence:
    storageClass: standard-rwo # GCP Persistent Disk
    
openWebUI:
  persistence:
    storageClass: longhorn     # Longhorn for application data
```

#### **Azure AKS**
```yaml
# Use Azure Disk for databases, Longhorn for applications
postgres:
  persistence:
    storageClass: managed-premium # Azure Premium SSD
    
openWebUI:
  persistence:
    storageClass: longhorn        # Longhorn for application data
```

---

## 🔧 Storage Class Management

### 📋 **Available Storage Classes**
```bash
# List all storage classes
kubectl get storageclass

# Typical Lair storage classes:
NAME                    PROVISIONER                     RECLAIMPOLICY
longhorn (default)      driver.longhorn.io              Delete
microk8s-hostpath      microk8s.io/hostpath            Delete
lair-storage           driver.longhorn.io              Retain
lair-hostpath          microk8s.io/hostpath            Retain
```

### ⚙️ **Custom Storage Classes**

#### **High-Performance Storage Class**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: lair-fast
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "1"           # Single replica for speed
  staleReplicaTimeout: "30"       # Quick failover
  fromBackup: ""
  diskSelector: "ssd"             # Use SSD nodes only
reclaimPolicy: Retain
volumeBindingMode: Immediate
```

#### **High-Availability Storage Class**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: lair-ha
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"           # Triple replication
  dataLocality: "strict-local"    # Keep data local when possible
  diskSelector: ""
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

#### **Backup-Optimized Storage Class**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: lair-backup
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "2"
  recurringJobSelector: '[{"name":"daily-backup", "isGroup":false}]'
reclaimPolicy: Retain
```

### 🔄 **Storage Class Migration**
```bash
# Migrate PVC to different storage class
# 1. Create new PVC with desired storage class
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openwebui-data-new
  namespace: lair
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: lair-fast
  resources:
    requests:
      storage: 20Gi
EOF

# 2. Copy data between PVCs
kubectl run data-migration --image=busybox --rm -it -- sh
# Mount both volumes and copy data

# 3. Update application to use new PVC
# 4. Delete old PVC
```

---

## 📊 Performance Optimization

### 🚀 **Longhorn Performance Tuning**

#### **CPU & Memory Optimization**
```yaml
# Longhorn performance settings
longhorn:
  defaultSettings:
    guaranteedEngineManagerCPU: 20      # Increase for better performance
    guaranteedReplicaManagerCPU: 20     # Increase for better performance
    
  # Resource allocation for Longhorn components
  longhornManager:
    resources:
      limits:
        cpu: 500m
        memory: 512Mi
      requests:
        cpu: 100m
        memory: 128Mi
```

#### **Network Optimization**
```bash
# Optimize network for Longhorn
# Increase network buffer sizes
echo 'net.core.rmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 65536 134217728' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 134217728' >> /etc/sysctl.conf
sysctl -p
```

#### **Disk Performance**
```bash
# Check disk performance
sudo fio --name=longhorn-test --ioengine=libaio --rw=randrw --bs=4k --numjobs=4 --size=1G --runtime=60 --direct=1 --directory=/var/lib/longhorn

# Optimize disk scheduler for SSDs
echo noop | sudo tee /sys/block/sda/queue/scheduler

# Disable swap for better performance
sudo swapoff -a
```

### ⚡ **Hostpath Performance Tuning**

#### **SD Card Optimization (Jetson)**
```bash
# Optimize SD card mount options
sudo mount -o remount,noatime,commit=60 /var/snap/microk8s/common/default-storage

# Reduce write amplification
echo 'vm.dirty_ratio = 5' >> /etc/sysctl.conf
echo 'vm.dirty_background_ratio = 2' >> /etc/sysctl.conf
sysctl -p
```

#### **Application-Specific Optimization**
```yaml
# Optimize applications for local storage
ollama:
  # Use memory mapping for models
  env:
    OLLAMA_MMAP: "1"
    OLLAMA_NUMA: "false"

postgres:
  # Optimize for flash storage
  config:
    shared_buffers: "128MB"
    effective_cache_size: "1GB"
    random_page_cost: "1.1"      # Lower for SSD
    checkpoint_completion_target: "0.9"
```

---

## 💾 Backup & Disaster Recovery

### 🔄 **Longhorn Backup Strategy**
```bash
# Configure S3 backup target
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-target
  namespace: longhorn-system
spec:
  value: "s3://lair-backups@us-east-1/"
EOF

# Create backup schedule
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: lair-daily-backup
  namespace: longhorn-system
spec:
  cron: "0 3 * * *"
  task: "backup"
  groups: ["default"]
  retain: 14
  concurrency: 2
EOF
```

### 📁 **Hostpath Backup Strategy**
```bash
# Automated backup script for Jetson
#!/bin/bash
BACKUP_DIR="/mnt/external/lair-backups"
SOURCE_DIR="/var/snap/microk8s/common/default-storage"
DATE=$(date +%Y%m%d_%H%M%S)

# Create incremental backup
rsync -av --link-dest="$BACKUP_DIR/latest" "$SOURCE_DIR/" "$BACKUP_DIR/backup-$DATE/"
ln -sfn "backup-$DATE" "$BACKUP_DIR/latest"

# Upload to S3 (optional)
aws s3 sync "$BACKUP_DIR/backup-$DATE/" "s3://lair-jetson-backups/backup-$DATE/"
```

### 🚨 **Disaster Recovery**
```bash
# Longhorn disaster recovery
# 1. Restore from S3 backup
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Restore
metadata:
  name: restore-openwebui
  namespace: longhorn-system
spec:
  fromBackup: "s3://lair-backups/backup-xxx"
  restoreVolumeRecurringJob: true
EOF

# 2. Create PVC from restored volume
# 3. Update application to use restored PVC

# Hostpath disaster recovery
# 1. Restore from external backup
sudo rsync -av /mnt/external/lair-backups/latest/ /var/snap/microk8s/common/default-storage/

# 2. Restart applications
kubectl rollout restart deployment -n lair
```

---

## 🔍 Monitoring & Alerting

### 📊 **Storage Monitoring**
```bash
# Monitor storage usage
kubectl get pvc -n lair -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.spec.resources.requests.storage,STORAGECLASS:.spec.storageClassName

# Check Longhorn volume health
kubectl get volumes.longhorn.io -n longhorn-system -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness

# Monitor disk usage on nodes
kubectl top nodes
```

### 🚨 **Storage Alerts**
```bash
# Example monitoring script
#!/bin/bash
# Check storage usage and alert if > 80%
USAGE=$(df /var/snap/microk8s/common/default-storage | tail -1 | awk '{print $5}' | sed 's/%//')
if [ $USAGE -gt 80 ]; then
    echo "WARNING: Storage usage is ${USAGE}%"
    # Send alert (email, Slack, etc.)
fi

# Check Longhorn volume health
kubectl get volumes.longhorn.io -n longhorn-system -o json | jq -r '.items[] | select(.status.robustness != "healthy") | .metadata.name'
```

---

## 🎯 Best Practices

### 🔒 **Security Best Practices**
- **Encrypt at rest**: Enable encryption for sensitive data
- **Access control**: Use RBAC for storage resource access
- **Backup encryption**: Encrypt backups in transit and at rest
- **Regular audits**: Monitor storage access and usage

### 📊 **Performance Best Practices**
- **Right-size volumes**: Don't over-provision storage
- **Monitor IOPS**: Track storage performance metrics
- **Use appropriate storage classes**: Match storage type to workload
- **Regular maintenance**: Clean up unused volumes and snapshots

### 🔧 **Operational Best Practices**
- **Regular backups**: Automated, tested backup procedures
- **Capacity planning**: Monitor growth and plan for expansion
- **Documentation**: Clear procedures for storage management
- **Testing**: Regular disaster recovery testing

---

**🎯 Ready to protect your data?** Continue with [Backup & Disaster Recovery](../maintenance/backup-restore.md) or explore [Troubleshooting Storage Issues](../troubleshooting/common-issues.md)!
