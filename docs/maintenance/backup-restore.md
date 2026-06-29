# 💾 Backup & Disaster Recovery

> **Complete guide to data protection, backup procedures, and disaster recovery for Lair deployments**

This guide covers comprehensive backup strategies, disaster recovery procedures, and data protection best practices for Lair infrastructure and applications.

---

## 🎯 Overview

Lair backup and disaster recovery involves multiple layers of data protection, from application data to cluster configuration. This guide provides complete procedures for protecting your AI infrastructure investment.

### 🏗️ **Backup Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                      🌐 BACKUP TARGETS                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ Application     │  │ Configuration   │  │ Infrastructure  │  │
│  │ Data            │  │ Files           │  │ State           │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🔧 BACKUP METHODS                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │     Velero      │  │   Volume        │  │    Manual       │  │
│  │  (Kubernetes)   │  │  Snapshots      │  │   Scripts       │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                  💾 STORAGE DESTINATIONS                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   S3 Storage    │  │  Local Storage  │  │  Cloud Storage  │  │
│  │ (AWS/MinIO/OVH) │  │ (External HDD)  │  │ (Multi-Region)  │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📊 **Backup Strategy by Component**

| Component | Data Type | Backup Method | Frequency | Retention |
|-----------|-----------|---------------|-----------|-----------|
| **OpenWebUI** | User data, chats, documents | Velero + DB dump | Daily | 30 days |
| **N8N** | Workflows, credentials | Velero + DB dump | Daily | 30 days |
| **Ollama** | Models, configurations | Volume snapshot | Weekly | 4 weeks |
| **PostgreSQL** | Database content | pg_dump + Velero | Daily | 30 days |
| **Certificates** | TLS certificates | Kubernetes secrets | Daily | 90 days |
| **Configuration** | Helm values, configs | Git + manual export | On change | Indefinite |

---

## 🔧 Velero Backup System

### 🎯 **Overview**
Velero provides Kubernetes-native backup and restore capabilities with **complete volume data backup**, automatically configured during Lair installation when backup is enabled.

**✅ Backup Coverage:**
- **Kubernetes Resources**: Deployments, Services, ConfigMaps, Secrets, Ingress
- **Persistent Volume Data**: Complete file-system backup using Kopia/Restic
- **Database Content**: PostgreSQL databases (OpenWebUI, N8N)
- **AI Models**: Ollama models and configurations
- **Application Data**: User documents, workflows, chat history

### ⚙️ **Velero Configuration**
Velero is configured during setup with S3-compatible storage and file-system backup enabled:

```yaml
# Velero configuration (automatically applied)
velero:
  enabled: true
  namespace: velero
  configuration:
    provider: aws
    # Enable complete volume backup
    defaultVolumesToFsBackup: true
    backupStorageLocation:
      bucket: lair-backups
      config:
        region: us-east-1
        s3Url: https://s3.gra.io.cloud.ovh.net
    volumeSnapshotLocation:
      config:
        region: us-east-1
# Node-agent DaemonSet for file-system backup
deployNodeAgent: true
```

**🔑 Key Features:**
- **File-Level Backup**: Uses Kopia (modern) or Restic for incremental file-system backups
- **Node-Agent**: DaemonSet running on each node to access volume data
- **Automatic Discovery**: All PVCs are automatically included in backups
- **Incremental**: Only changed data is backed up after the first full backup
- **Compression**: Data is compressed before upload to S3

### 📋 **Backup Schedules**
Automatic backup schedules are created during installation with complete volume backup:

```bash
# Check existing backup schedules
kubectl get schedules -n velero

# Default schedule (created automatically)
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: lair-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM UTC
  template:
    includedNamespaces:
    - lair
    # Volume backup configuration
    snapshotVolumes: true
    defaultVolumesToFsBackup: true  # Enable file-system backup for all PVCs
    ttl: 720h0m0s  # 30 days retention
```

**📊 What Gets Backed Up:**

Each daily backup includes:
- ✅ **~56 Kubernetes resources** (Pods, Deployments, Services, ConfigMaps, Secrets, etc.)
- ✅ **~5 PodVolumeBackups** (one for each PVC with data):
  - **Ollama models** (~1-2 GB): AI models and configurations
  - **PostgreSQL database** (~50-100 MB): OpenWebUI + N8N databases
  - **OpenWebUI data** (~10-50 MB): User documents, chat history
  - **N8N workflows** (~1-10 MB): Automation workflows and credentials
  - **Redis cache** (~1-5 MB): Session and cache data

**⏱️ Backup Duration:**
- Initial full backup: ~5-10 minutes (depending on data size)
- Incremental backups: ~2-5 minutes (only changed data)

**💾 Storage Usage:**
- First backup: Full data size
- Subsequent backups: Only deltas (incremental)

### 🔍 **Backup Operations**

#### **Manual Backup Creation**

**✅ Complete Backup (with volume data - RECOMMENDED):**
```bash
# Create immediate full backup with volume data
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: lair-manual-backup-$(date +%Y%m%d-%H%M%S)
  namespace: velero
spec:
  includedNamespaces:
  - lair
  storageLocation: default
  ttl: 24h0m0s
  snapshotVolumes: true
  defaultVolumesToFsBackup: true  # Include PVC data
EOF

# Monitor backup progress
kubectl get backup -n velero -w

# Check PodVolumeBackups (file-system backups)
kubectl get podvolumebackups -n velero
```

**⚠️ Quick Backup (structure only, no volume data):**
```bash
# Backup only Kubernetes resources (no PVC data)
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: lair-structure-backup-$(date +%Y%m%d)
  namespace: velero
spec:
  includedNamespaces:
  - lair
  storageLocation: default
  ttl: 24h0m0s
  snapshotVolumes: false  # Skip volume data
  defaultVolumesToFsBackup: false
EOF
```

**🎯 Selective Backup:**
```bash
# Backup specific resources only
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: lair-config-backup
  namespace: velero
spec:
  includedNamespaces:
  - lair
  includedResources:
  - secrets
  - configmaps
  storageLocation: default
  ttl: 168h0m0s  # 7 days
EOF
```

#### **Backup Verification**

**📋 Check Backup Status:**
```bash
# List all backups
kubectl get backups -n velero

# Check specific backup details
kubectl describe backup lair-backup-20241201-020000 -n velero

# View backup with custom columns
kubectl get backup lair-backup-20241201-020000 -n velero -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
ITEMS:.status.progress.itemsBackedUp,\
CREATED:.status.startTimestamp,\
COMPLETED:.status.completionTimestamp
```

**🔍 Verify Volume Backups:**
```bash
# List PodVolumeBackups for a specific backup
kubectl get podvolumebackups -n velero | grep "lair-backup-20241201"

# Check PodVolumeBackup details with data size
kubectl get podvolumebackups -n velero -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
DURATION:.status.completionTimestamp,\
BYTES:.status.progress.bytesDone,\
REPO:.spec.repoIdentifier

# Detailed view of specific PodVolumeBackup
kubectl describe podvolumebackup BACKUP_NAME-xxxxx -n velero
```

**📊 Check Backup Logs:**
```bash
# View Velero pod logs
kubectl logs -n velero deployment/velero --tail=100

# View node-agent logs (file-system backup)
kubectl logs -n velero daemonset/node-agent --tail=100

# Filter logs for specific backup
kubectl logs -n velero deployment/velero | grep "lair-backup-20241201"
```

**✅ Verify Backup Completeness:**
```bash
# Check backup includes expected items
BACKUP_NAME="lair-backup-20241201-020000"

echo "=== Backup Summary ==="
kubectl get backup $BACKUP_NAME -n velero -o jsonpath='{.status.phase}'
echo ""

echo "=== Items Backed Up ==="
kubectl get backup $BACKUP_NAME -n velero -o jsonpath='{.status.progress.itemsBackedUp}/{.status.progress.totalItems}'
echo ""

echo "=== PodVolumeBackups ==="
kubectl get podvolumebackups -n velero | grep "$BACKUP_NAME" | wc -l
echo " PodVolumeBackups created"

echo "=== Warnings/Errors ==="
kubectl get backup $BACKUP_NAME -n velero -o jsonpath='{.status.warnings}'
echo " warnings"
kubectl get backup $BACKUP_NAME -n velero -o jsonpath='{.status.errors}'
echo " errors"
```

#### **Backup Monitoring**
```bash
# Monitor backup status
kubectl get backups -n velero -w

# Check backup storage location
kubectl get backupstoragelocations -n velero

# Monitor backup size and duration
velero backup get --output table
```

---

## 🗄️ Database Backup Procedures

### 📊 **PostgreSQL Backup**

#### **Automated Database Backup**
```bash
# Create automated backup script
cat > /usr/local/bin/lair-db-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)
NAMESPACE="lair"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup all databases
kubectl exec -n $NAMESPACE statefulset/lair-postgresql -- pg_dumpall -U postgres > "$BACKUP_DIR/lair-db-full-$DATE.sql"

# Backup individual databases
kubectl exec -n $NAMESPACE statefulset/lair-postgresql -- pg_dump -U postgres openwebui > "$BACKUP_DIR/openwebui-$DATE.sql"
kubectl exec -n $NAMESPACE statefulset/lair-postgresql -- pg_dump -U postgres n8n > "$BACKUP_DIR/n8n-$DATE.sql"

# Compress backups
gzip "$BACKUP_DIR"/*.sql

# Upload to S3 (optional)
aws s3 sync "$BACKUP_DIR" s3://lair-backups/database/

# Cleanup old backups (keep 30 days)
find "$BACKUP_DIR" -name "*.gz" -mtime +30 -delete

echo "Database backup completed: $DATE"
EOF

chmod +x /usr/local/bin/lair-db-backup.sh
```

#### **Schedule Database Backups**
```bash
# Add to crontab
crontab -e

# Add this line for daily backup at 1 AM
0 1 * * * /usr/local/bin/lair-db-backup.sh >> /var/log/lair-db-backup.log 2>&1
```

#### **Manual Database Backup**
```bash
# Backup specific database
kubectl exec -n lair statefulset/lair-postgresql -- pg_dump -U postgres openwebui > openwebui-backup-$(date +%Y%m%d).sql

# Backup all databases
kubectl exec -n lair statefulset/lair-postgresql -- pg_dumpall -U postgres > lair-full-backup-$(date +%Y%m%d).sql

# Backup with compression
kubectl exec -n lair statefulset/lair-postgresql -- pg_dump -U postgres openwebui | gzip > openwebui-backup-$(date +%Y%m%d).sql.gz
```

---

## 💾 Volume Backup Strategies

### 🔄 **Longhorn Volume Backup**

#### **Automatic Longhorn Backups**
```bash
# Configure Longhorn backup target (if not done during setup)
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-target
  namespace: longhorn-system
spec:
  value: "s3://lair-backups@us-east-1/"
---
apiVersion: longhorn.io/v1beta2
kind: Setting
metadata:
  name: backup-target-credential-secret
  namespace: longhorn-system
spec:
  value: "longhorn-backup-secret"
EOF

# Create recurring backup job
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: RecurringJob
metadata:
  name: lair-volume-backup
  namespace: longhorn-system
spec:
  cron: "0 3 * * *"
  task: "backup"
  groups: ["default"]
  retain: 14
  concurrency: 2
EOF
```

#### **Manual Volume Backup**
```bash
# Create snapshot of specific volume
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Snapshot
metadata:
  name: openwebui-snapshot-$(date +%Y%m%d)
  namespace: longhorn-system
spec:
  volume: pvc-openwebui-data
EOF

# Create backup from snapshot
# Use Longhorn UI or CLI to create backup from snapshot
```

### 📁 **Hostpath Volume Backup (Jetson)**

#### **Automated Hostpath Backup**
```bash
# Create Jetson backup script
cat > /usr/local/bin/lair-jetson-backup.sh << 'EOF'
#!/bin/bash
SOURCE_DIR="/var/snap/microk8s/common/default-storage"
BACKUP_BASE="/mnt/external/lair-backups"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_BASE/backup-$DATE"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create incremental backup
rsync -av --link-dest="$BACKUP_BASE/latest" "$SOURCE_DIR/" "$BACKUP_DIR/"

# Update latest symlink
ln -sfn "backup-$DATE" "$BACKUP_BASE/latest"

# Upload to S3 (if configured)
if command -v aws &> /dev/null; then
    aws s3 sync "$BACKUP_DIR/" "s3://lair-jetson-backups/backup-$DATE/"
fi

# Cleanup old backups (keep 7 days locally)
find "$BACKUP_BASE" -maxdepth 1 -name "backup-*" -mtime +7 -exec rm -rf {} \;

echo "Jetson backup completed: $DATE"
EOF

chmod +x /usr/local/bin/lair-jetson-backup.sh
```

#### **Schedule Jetson Backups**
```bash
# Add to crontab
crontab -e

# Daily backup at 3 AM
0 3 * * * /usr/local/bin/lair-jetson-backup.sh >> /var/log/lair-jetson-backup.log 2>&1
```

---

## 🔧 Configuration Backup

### ⚙️ **Kubernetes Configuration Backup**

#### **Export All Configurations**
```bash
# Create configuration backup script
cat > /usr/local/bin/lair-config-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/config"
DATE=$(date +%Y%m%d_%H%M%S)
CONFIG_DIR="$BACKUP_DIR/config-$DATE"

mkdir -p "$CONFIG_DIR"

# Export Lair namespace resources
kubectl get all,secrets,configmaps,ingress,pvc -n lair -o yaml > "$CONFIG_DIR/lair-namespace.yaml"

# Export certificates
kubectl get certificates,clusterissuers -A -o yaml > "$CONFIG_DIR/certificates.yaml"

# Export storage classes and PVs
kubectl get storageclass,pv -o yaml > "$CONFIG_DIR/storage.yaml"

# Export Longhorn configuration
kubectl get settings.longhorn.io,recurringjobs.longhorn.io -n longhorn-system -o yaml > "$CONFIG_DIR/longhorn.yaml"

# Export Velero configuration
kubectl get schedules,backupstoragelocations,volumesnapshotlocations -n velero -o yaml > "$CONFIG_DIR/velero.yaml"

# Backup Helm values
cp /path/to/values-*.yaml "$CONFIG_DIR/" 2>/dev/null || true

# Compress backup
tar -czf "$BACKUP_DIR/lair-config-$DATE.tar.gz" -C "$CONFIG_DIR" .
rm -rf "$CONFIG_DIR"

echo "Configuration backup completed: $DATE"
EOF

chmod +x /usr/local/bin/lair-config-backup.sh
```

#### **Helm Values Backup**
```bash
# Export current Helm values
helm get values lair -n lair > lair-current-values-$(date +%Y%m%d).yaml

# Export complete Helm configuration
helm get all lair -n lair > lair-complete-config-$(date +%Y%m%d).yaml

# Backup custom configuration files
cp values-*.yaml /backup/helm-values/
```

---

## 🚨 Disaster Recovery Procedures

### 🔄 **Automated Disaster Recovery Script**

Lair includes a comprehensive disaster recovery script that automates the restore process with enhanced safety checks, pre-cleanup, and S3 connectivity verification.

#### **🎯 Quick Recovery**
```bash
# Interactive recovery with guided cleanup (RECOMMENDED)
cd helm-chart
./disaster-recovery-restore.sh --interactive

# List available backups
./disaster-recovery-restore.sh --list-backups

# Clean installation and restore (recommended for full recovery)
./disaster-recovery-restore.sh --clean-restore lair-backup-20240921-020000

# Direct restore (if you know the backup name and namespace is clean)
./disaster-recovery-restore.sh lair-backup-20240921-020000

# Restore to different namespace (test without affecting production)
./disaster-recovery-restore.sh --to-namespace lair-test lair-backup-20240921-020000
```

**📚 For detailed restore scenarios and procedures**, see the [Complete Restore Guide](./RESTORE-GUIDE.md) which covers:
- 4 restore scenarios with step-by-step procedures
- Testing restores safely with namespace mapping
- Troubleshooting common issues
- Best practices and real-world examples

#### **⚠️ Important: Clean State Required**

Velero restore will **fail** if resources already exist in the cluster with the same names (PVCs, Pods, Services, etc.). The script handles this automatically:

- **Interactive Mode**: Offers to clean existing installation before restore
- **Clean Restore Mode**: Automatically cleans and then restores
- **Manual Cleanup**: See [Manual Pre-Restore Cleanup](#manual-pre-restore-cleanup) below

#### **📋 Prerequisites for Disaster Recovery**
Before using the disaster recovery script, ensure:

| Requirement | Description | Verification |
|-------------|-------------|--------------|
| **New Cluster Ready** | Fresh Kubernetes cluster running | `kubectl cluster-info` |
| **Velero Installed** | Velero deployed with same BSL config | `kubectl get pods -n velero` |
| **Node-Agent Running** | ⚠️ **CRITICAL**: Required for volume data restore | `kubectl get daemonset node-agent -n velero` |
| **S3 Access** | Same S3 bucket and credentials | `kubectl get backupstoragelocations -n velero` |
| **Network Connectivity** | Access to S3 endpoint | `ping s3.your-region.provider.com` |
| **Sufficient Resources** | Meet minimum system requirements | See system requirements below |

**⚠️ IMPORTANT: Node-Agent Requirement**

To restore volume data (databases, models, documents), the target cluster **MUST** have the node-agent DaemonSet running:

```bash
# Verify node-agent is installed and running
kubectl get daemonset -n velero
# Should show: node-agent   DESIRED  CURRENT  READY  UP-TO-DATE  AVAILABLE

kubectl get pods -n velero -l name=node-agent
# Should show pods in Running state

# If node-agent is missing, reinstall Velero with correct configuration
helm upgrade velero vmware-tanzu/velero -n velero \
  --set configuration.defaultVolumesToFsBackup=true \
  --set deployNodeAgent=true \
  --reuse-values
```

**Without node-agent:** ❌ Restore will recreate PVCs but they will be EMPTY (all data lost)  
**With node-agent:** ✅ Restore will recreate PVCs with complete data from backup

#### **💻 System Requirements for Recovery**
| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 4+ cores | 8+ cores |
| **RAM** | 8GB | 16GB+ |
| **Storage** | 100GB free | 200GB+ free |
| **Network** | 1Gbps | 10Gbps+ |

#### **🔍 Enhanced Safety Features**
The disaster recovery script includes comprehensive verification:

- **✅ Prerequisites Check**: Verifies kubectl access, Velero installation, and deployment status
- **✅ BackupStorageLocation Verification**: Ensures S3 storage is accessible and properly configured
- **✅ S3 Connectivity Test**: Tests actual connectivity to backup storage before restore
- **✅ Backup Status Validation**: Confirms backup is in 'Completed' state before proceeding
- **✅ Smart Backup Discovery**: Finds both manual (`lair-backup`) and automatic (`lair-backup-YYYYMMDD-HHMMSS`) backups
- **✅ Real-time Monitoring**: Tracks restore progress with detailed status updates

#### **📋 Supported Backup Patterns**
The script automatically detects various backup naming patterns:
- `lair-backup` - Manual/scheduled backups
- `lair-backup-20240921-020000` - Automatic timestamped backups
- Any backup with `lair` namespace inclusion

### 🔄 **Complete System Recovery**

#### **Recovery Planning**
```bash
# Recovery priority order:
1. Cluster infrastructure (Kubernetes)
2. Storage backend (Longhorn/Hostpath)
3. Core services (Ingress, Cert-Manager)
4. Lair applications
5. Data restoration
6. Configuration restoration
```

#### **Cluster Recovery (MicroK8s)**
```bash
# 1. Fresh MicroK8s installation
sudo snap install microk8s --classic
sudo microk8s status --wait-ready

# 2. Enable required addons
sudo microk8s enable dns ingress helm3 cert-manager

# 3. Configure storage (Longhorn or Hostpath)
# Follow original installation procedures

# 4. Install Velero
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero -n velero --create-namespace -f velero-values.yaml
```

#### **Manual Pre-Restore Cleanup**

If not using the automated script, you **must** clean the namespace before restore:

```bash
# 1. Scale down all workloads
kubectl scale deployment --all --replicas=0 -n lair
kubectl scale statefulset --all --replicas=0 -n lair

# 2. Wait for pods to terminate
kubectl wait --for=delete pod --all -n lair --timeout=60s

# 3. Delete PersistentVolumeClaims (CRITICAL)
kubectl delete pvc --all -n lair

# 4. Delete all other resources
kubectl delete all --all -n lair
kubectl delete configmap --all -n lair
kubectl delete secret --all -n lair
kubectl delete ingress --all -n lair

# 5. Optional: Delete and recreate namespace for complete cleanup
kubectl delete namespace lair
kubectl create namespace lair
```

#### **Application Recovery from Velero**
```bash
# 1. List available backups
kubectl get backups -n velero

# 2. Create restore resource (namespace must be clean!)
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: lair-restore-$(date +%Y%m%d-%H%M%S)
  namespace: velero
spec:
  backupName: lair-backup-20240921-020000
  includedNamespaces:
  - lair
  restorePVs: true
  preserveNodePorts: true
EOF

# 3. Monitor restore status
kubectl get restore -n velero -w

# 4. Check restore details
RESTORE_NAME=$(kubectl get restore -n velero --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
kubectl describe restore $RESTORE_NAME -n velero

# 5. Verify application status
kubectl get pods -n lair
kubectl get pvc -n lair
```

#### **Selective Recovery**
```bash
# Restore specific namespace
velero restore create lair-namespace-restore \
  --from-backup lair-daily-backup-latest \
  --include-namespaces lair \
  --wait

# Restore specific resources
velero restore create lair-secrets-restore \
  --from-backup lair-daily-backup-latest \
  --include-resources secrets \
  --namespace-mappings lair:lair-restored \
  --wait

# Restore specific application
velero restore create openwebui-restore \
  --from-backup lair-daily-backup-latest \
  --selector app=openwebui \
  --wait
```

### 🗄️ **Database Recovery**

#### **PostgreSQL Recovery**
```bash
# 1. Ensure PostgreSQL pod is running
kubectl get pods -n lair -l app=postgresql

# 2. Restore from SQL dump
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "DROP DATABASE IF EXISTS openwebui;"
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "CREATE DATABASE openwebui;"
kubectl exec -i -n lair statefulset/lair-postgresql -- psql -U postgres openwebui < openwebui-backup.sql

# 3. Verify restoration
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "\l"
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres openwebui -c "\dt"
```

#### **Database Recovery with Compression**
```bash
# Restore from compressed backup
gunzip -c openwebui-backup.sql.gz | kubectl exec -i -n lair statefulset/lair-postgresql -- psql -U postgres openwebui
```

### 💾 **Volume Recovery**

#### **Longhorn Volume Recovery**
```bash
# 1. Restore volume from Longhorn backup
# Use Longhorn UI to restore volume from S3 backup

# 2. Create PVC for restored volume
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openwebui-data-restored
  namespace: lair
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: longhorn
  volumeName: restored-volume-name
  resources:
    requests:
      storage: 20Gi
EOF

# 3. Update application to use restored PVC
kubectl patch deployment lair-openwebui -n lair -p '{"spec":{"template":{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"openwebui-data-restored"}}]}}}}'
```

#### **Hostpath Recovery (Jetson)**
```bash
# 1. Stop applications
kubectl scale deployment --all --replicas=0 -n lair

# 2. Restore from backup
sudo rsync -av /mnt/external/lair-backups/latest/ /var/snap/microk8s/common/default-storage/

# 3. Restart applications
kubectl scale deployment --all --replicas=1 -n lair

# 4. Verify data integrity
kubectl exec -n lair deployment/lair-openwebui -- ls -la /app/backend/data
```

---

## 🔍 Backup Verification & Testing

### ✅ **Backup Integrity Checks**

#### **Automated Backup Verification**
```bash
# Create backup verification script
cat > /usr/local/bin/lair-backup-verify.sh << 'EOF'
#!/bin/bash
DATE=$(date +%Y%m%d)

# Check Velero backup status
echo "=== Velero Backup Status ==="
velero backup get | grep $(date +%Y-%m-%d)

# Check database backup integrity
echo "=== Database Backup Verification ==="
if [ -f "/backup/postgresql/lair-db-full-${DATE}*.sql.gz" ]; then
    gunzip -t /backup/postgresql/lair-db-full-${DATE}*.sql.gz
    echo "Database backup integrity: OK"
else
    echo "Database backup integrity: FAILED"
fi

# Check S3 backup sync
echo "=== S3 Backup Status ==="
aws s3 ls s3://lair-backups/ --recursive | grep $(date +%Y-%m-%d)

# Check backup sizes
echo "=== Backup Sizes ==="
du -sh /backup/* 2>/dev/null

echo "Backup verification completed: $(date)"
EOF

chmod +x /usr/local/bin/lair-backup-verify.sh
```

#### **Recovery Testing**
```bash
# Create test recovery environment
kubectl create namespace lair-test

# Test restore to different namespace
velero restore create lair-test-restore \
  --from-backup lair-daily-backup-latest \
  --namespace-mappings lair:lair-test \
  --wait

# Verify test environment
kubectl get pods -n lair-test

# Cleanup test environment
kubectl delete namespace lair-test
```

### 📊 **Backup Monitoring**

#### **Backup Status Dashboard**
```bash
# Create backup status script
cat > /usr/local/bin/lair-backup-status.sh << 'EOF'
#!/bin/bash
echo "=== LAIR BACKUP STATUS REPORT ==="
echo "Generated: $(date)"
echo

echo "=== Velero Backups ==="
velero backup get | head -10

echo
echo "=== Recent Database Backups ==="
ls -lht /backup/postgresql/ | head -5

echo
echo "=== Storage Usage ==="
df -h /backup

echo
echo "=== Last Backup Logs ==="
tail -5 /var/log/lair-db-backup.log

echo
echo "=== Backup Schedule Status ==="
kubectl get schedules -n velero
EOF

chmod +x /usr/local/bin/lair-backup-status.sh
```

#### **Backup Alerting**
```bash
# Create backup alert script
cat > /usr/local/bin/lair-backup-alert.sh << 'EOF'
#!/bin/bash
ALERT_EMAIL="admin@example.com"
BACKUP_AGE_LIMIT=25  # Hours

# Check if backup is older than limit
LAST_BACKUP=$(velero backup get --output json | jq -r '.items[0].metadata.creationTimestamp')
LAST_BACKUP_EPOCH=$(date -d "$LAST_BACKUP" +%s)
CURRENT_EPOCH=$(date +%s)
AGE_HOURS=$(( (CURRENT_EPOCH - LAST_BACKUP_EPOCH) / 3600 ))

if [ $AGE_HOURS -gt $BACKUP_AGE_LIMIT ]; then
    echo "ALERT: Last backup is $AGE_HOURS hours old" | mail -s "Lair Backup Alert" $ALERT_EMAIL
fi

# Check backup failures
FAILED_BACKUPS=$(velero backup get --output json | jq -r '.items[] | select(.status.phase == "Failed") | .metadata.name')
if [ ! -z "$FAILED_BACKUPS" ]; then
    echo "ALERT: Failed backups detected: $FAILED_BACKUPS" | mail -s "Lair Backup Failure" $ALERT_EMAIL
fi
EOF

chmod +x /usr/local/bin/lair-backup-alert.sh

# Schedule alert checks
crontab -e
# Add: 0 */6 * * * /usr/local/bin/lair-backup-alert.sh
```

---

## 🔧 Troubleshooting Common Issues

### ❌ **Issue 1: "Unable to get UUID for /dev/sdX" during Longhorn disk setup**

**Symptoms:**
```
ERROR: Unable to get UUID for /dev/sdc
ERROR: Failed to initialize disk /dev/sdc
```

**Cause:** The kernel hasn't refreshed the partition table after `mkfs.ext4`, so `blkid` can't read the UUID immediately.

**Solution:** The issue is now fixed in `microk8s/lib/longhorn_multi_disk.sh` with automatic retries and partition table refresh. If you still encounter this:

```bash
# Manual fix:
sudo partprobe /dev/sdX
sudo blockdev --rereadpt /dev/sdX
sudo udevadm settle
sleep 2
sudo blkid /dev/sdX  # Should now show UUID
```

**Prevention:** Update to latest version of Lair setup scripts.

---

### ❌ **Issue 2: Velero restore fails with "already exists" warnings**

**Symptoms:**
```
could not restore, PersistentVolumeClaim: n8n-pvc already exists.
Warning: the in-cluster version is different than the backed-up version
could not restore, Pod: n8n-xxx already exists.
could not restore, Service: lair-n8n already exists.
```

**Cause:** Velero cannot restore resources that already exist in the cluster. This happens when:
- Trying to restore on a cluster that already has Lair running
- Previous restore wasn't cleaned up
- Reboot recreated resources from Helm

**⚠️ CRITICAL NOTE about Volume Data:**
Even if the restore shows "Completed" with these warnings, **your PVC data may be EMPTY** if the cluster doesn't have node-agent running! The warnings mean Kubernetes resources were skipped, but the real problem is missing volume data.

**Solution 1: Use the automated disaster recovery script (RECOMMENDED)**
```bash
cd helm-chart
./disaster-recovery-restore.sh --clean-restore BACKUP_NAME
```

**Solution 2: Manual cleanup before restore**
```bash
# Delete all Lair resources
kubectl scale deployment --all --replicas=0 -n lair
kubectl scale statefulset --all --replicas=0 -n lair
kubectl delete pvc --all -n lair
kubectl delete all,configmap,secret,ingress --all -n lair

# Then perform restore
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: lair-restore-$(date +%Y%m%d-%H%M%S)
  namespace: velero
spec:
  backupName: YOUR_BACKUP_NAME
  includedNamespaces:
  - lair
  restorePVs: true
EOF
```

**Solution 3: Complete namespace reset**
```bash
# Nuclear option - completely remove and recreate namespace
kubectl delete namespace lair
kubectl create namespace lair

# Then restore
./disaster-recovery-restore.sh BACKUP_NAME
```

**Best Practice:** Always clean the namespace before restore, or use `--clean-restore` mode.

---

### ❌ **Issue 3: Backup schedule exists but no backups are created**

**Symptoms:**
```bash
kubectl get schedules -n velero
# Shows: lair-backup   Enabled   0 2 * * *

kubectl get backups -n velero
# Shows: No resources found
```

**Cause:** 
- Schedule created but hasn't triggered yet (runs at 2 AM)
- S3 connectivity issues
- Velero pod not running properly

**Solution:**
```bash
# 1. Check Velero pod status
kubectl get pods -n velero

# 2. Check BackupStorageLocation
kubectl get backupstoragelocations -n velero
# Status should be: Available

# 3. Check Velero logs for errors
kubectl logs -n velero deployment/velero --tail=100

# 4. Test with manual backup
kubectl apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: test-backup
  namespace: velero
spec:
  includedNamespaces:
  - lair
  storageLocation: default
  ttl: 24h0m0s
EOF

# 5. Monitor backup
kubectl get backup test-backup -n velero -w
kubectl describe backup test-backup -n velero
```

---

### ❌ **Issue 4: Restored pods stuck in Pending or CrashLoopBackOff**

**Symptoms:** After restore, pods don't start properly.

**Common Causes & Solutions:**

**A. PVCs not binding:**
```bash
# Check PVC status
kubectl get pvc -n lair

# If Pending, check storage class
kubectl get sc
kubectl describe pvc PENDING_PVC_NAME -n lair

# Solution: Ensure Longhorn is running
kubectl get pods -n longhorn-system
```

**B. Resource constraints:**
```bash
# Check node resources
kubectl describe nodes

# Check pod events
kubectl describe pod POD_NAME -n lair

# Solution: Scale down or increase node resources
```

**C. Configuration errors:**
```bash
# Check pod logs
kubectl logs POD_NAME -n lair

# Check secrets exist
kubectl get secrets -n lair

# Solution: Verify all secrets were restored
kubectl describe restore RESTORE_NAME -n velero
```

---

### ❌ **Issue 5: Restored PVCs are empty - no data restored**

**Symptoms:**
- Restore completes successfully
- All Kubernetes resources are restored
- Pods are running
- But PVCs are empty / databases are empty / models missing

**Cause:** Node-agent was not running during restore, so PodVolumeRestores were not created.

**Solution:**
```bash
# 1. Check if node-agent is running
kubectl get daemonset node-agent -n velero
kubectl get pods -n velero -l name=node-agent

# 2. If missing, upgrade Velero
helm upgrade velero vmware-tanzu/velero -n velero \
  --set configuration.defaultVolumesToFsBackup=true \
  --set deployNodeAgent=true \
  --reuse-values

# 3. Wait for node-agent to be ready
kubectl rollout status daemonset/node-agent -n velero

# 4. Re-do the restore (after cleaning namespace)
./disaster-recovery-restore.sh --clean-restore BACKUP_NAME
```

**Verification:**
```bash
# During restore, check if PodVolumeRestores are being created
kubectl get podvolumerestores -n velero -w

# Should see multiple PodVolumeRestores in "InProgress" then "Completed"
# If none appear, node-agent is not properly configured
```

---

### ❌ **Issue 6: Disk shows data but marked as unused during setup**

**Symptoms:**
```
WARN: Disk /dev/sda appears to have data or is in use - skipping for safety
```

**Cause:** Disk has existing filesystem or partitions.

**Solution:**
```bash
# Check what's on the disk
sudo lsblk /dev/sda -f
sudo blkid /dev/sda

# If safe to wipe:
sudo wipefs -a /dev/sda

# Then re-run setup or manual script
./add-ssd-to-longhorn.sh --device /dev/sda --mount-path /var/lib/longhorn/disk2
```

---

## 📋 Backup Best Practices

### 🔒 **Security Best Practices**
- **Encrypt backups**: Use encryption for sensitive data
- **Secure credentials**: Protect S3 access keys and database passwords
- **Access control**: Limit backup access to authorized personnel
- **Audit trails**: Log all backup and restore operations

### 📊 **Operational Best Practices**
- **Regular testing**: Test restore procedures monthly
- **Multiple locations**: Store backups in multiple geographic locations
- **Retention policies**: Implement appropriate backup retention
- **Monitoring**: Set up alerts for backup failures
- **Documentation**: Keep recovery procedures up to date

### 🚀 **Performance Best Practices**
- **Incremental backups**: Use incremental backups where possible
- **Compression**: Compress backups to save storage space
- **Scheduling**: Schedule backups during low-usage periods
- **Bandwidth management**: Limit backup bandwidth during business hours

---

## 🔄 Recovery Time Objectives (RTO) & Recovery Point Objectives (RPO)

### 📊 **Target Metrics**

| Component | RPO | RTO | Backup Method |
|-----------|-----|-----|---------------|
| **Critical Data** | 1 hour | 4 hours | Continuous replication |
| **Application Data** | 24 hours | 2 hours | Daily Velero backup |
| **Configuration** | 24 hours | 1 hour | Daily config export |
| **Models & Assets** | 7 days | 4 hours | Weekly volume backup |

### 🎯 **Recovery Scenarios**

#### **Scenario 1: Single Pod Failure**
- **RTO**: 5 minutes
- **Method**: Kubernetes automatic restart
- **Action**: Monitor and investigate root cause

#### **Scenario 2: Node Failure**
- **RTO**: 15 minutes
- **Method**: Pod rescheduling + volume reattachment
- **Action**: Replace failed node

#### **Scenario 3: Data Corruption**
- **RTO**: 2 hours
- **Method**: Restore from latest backup
- **Action**: Identify corruption source

#### **Scenario 4: Complete Cluster Loss**
- **RTO**: 4-8 hours
- **Method**: Full disaster recovery procedure
- **Action**: Rebuild cluster and restore all data

---

**🎯 Ready to protect your data?** Continue with [Monitoring Setup](monitoring.md) or explore [Update Procedures](updates.md)!
