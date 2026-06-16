# 💾 Backup & Disaster Recovery with Velero

> **Complete guide to Velero backup configuration, data protection, and disaster recovery in Lair**

This guide covers Velero backup system configuration, backup strategies, and disaster recovery procedures for protecting your Lair infrastructure and data.

---

## 🎯 Overview

Velero provides Kubernetes-native backup and restore capabilities for Lair, enabling comprehensive data protection and disaster recovery across all components.

### 🏗️ **Velero Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                     💾 BACKUP ARCHITECTURE                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Velero CLI    │  │  Velero Server  │  │  Backup Storage │  │
│  │   (Commands)    │  │ (K8s Operator)  │  │ (S3 Compatible) │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🎯 BACKUP TARGETS                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Kubernetes    │  │  Persistent     │  │   Application   │  │
│  │   Resources     │  │   Volumes       │  │     Data        │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🗄️ STORAGE BACKENDS                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │      AWS S3     │  │   OVH Cloud     │  │     MinIO       │  │
│  │   (Cloud)       │  │   (Europe)      │  │   (Local)       │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📊 **Backup Strategy**

| Component | Backup Method | Frequency | Retention | Priority |
|-----------|---------------|-----------|-----------|----------|
| **Kubernetes Resources** | Velero API backup | Daily | 30 days | High |
| **Persistent Volumes** | Volume snapshots | Daily | 30 days | Critical |
| **Application Data** | Database dumps + Velero | Daily | 30 days | Critical |
| **Configuration** | Git + manual export | On change | Indefinite | High |

---

## 🚀 Velero Installation & Setup

### 📦 **Installation Process**

Velero is automatically installed during Lair setup when backup is enabled:

```bash
# Velero installation is handled by setup scripts
# MicroK8s setup
sudo ./microk8s/setup.sh
# Choose 'y' when prompted for Velero backup

# Managed K8s setup  
sudo ./k8s-managed/setup.sh
# Choose 'y' when prompted for Velero backup
```

#### **Manual Velero Installation**
```bash
# Install Velero CLI
curl -fsSL -o velero-v1.12.0-linux-amd64.tar.gz https://github.com/vmware-tanzu/velero/releases/download/v1.12.0/velero-v1.12.0-linux-amd64.tar.gz
tar -xzf velero-v1.12.0-linux-amd64.tar.gz
sudo mv velero-v1.12.0-linux-amd64/velero /usr/local/bin/

# Install Velero server
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm install velero vmware-tanzu/velero -n velero --create-namespace -f velero-values.yaml
```

### ⚙️ **Configuration**

#### **S3 Storage Configuration**
```yaml
# Velero configuration for S3-compatible storage
velero:
  configuration:
    provider: aws
    backupStorageLocation:
      name: default
      provider: aws
      bucket: lair-backups
      config:
        region: us-east-1
        s3Url: https://s3.gra.io.cloud.ovh.net  # OVH example
        s3ForcePathStyle: true
    volumeSnapshotLocation:
      name: default
      provider: aws
      config:
        region: us-east-1
```

#### **Credentials Configuration**
```bash
# Create credentials file
cat > credentials-velero << EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY
aws_secret_access_key = YOUR_SECRET_KEY
EOF

# Create Kubernetes secret
kubectl create secret generic cloud-credentials \
  --namespace velero \
  --from-file cloud=credentials-velero
```

#### **Backup Schedule Configuration**
```yaml
# Automatic backup schedule
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: lair-daily-backup
  namespace: velero
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  template:
    includedNamespaces:
    - lair
    - longhorn-system
    - cert-manager
    excludedResources:
    - events
    - events.events.k8s.io
    ttl: 720h  # 30 days retention
    storageLocation: default
    volumeSnapshotLocations:
    - default
```

---

## 💾 Backup Operations

### 📋 **Creating Backups**

#### **Manual Backup Creation**
```bash
# Create full Lair backup
velero backup create lair-manual-backup \
  --include-namespaces lair \
  --wait

# Create backup with specific resources
velero backup create lair-config-backup \
  --include-resources secrets,configmaps,persistentvolumeclaims \
  --include-namespaces lair,cert-manager \
  --wait

# Create backup excluding certain resources
velero backup create lair-app-backup \
  --include-namespaces lair \
  --exclude-resources events,events.events.k8s.io \
  --wait
```

#### **Application-Specific Backups**
```bash
# Backup specific application
velero backup create openwebui-backup \
  --selector app=openwebui \
  --include-namespaces lair \
  --wait

# Backup with hooks (pre/post backup commands)
velero backup create postgres-backup \
  --include-namespaces lair \
  --selector app=postgresql \
  --wait
```

#### **Backup with Annotations**
```yaml
# Add backup annotations to pods
apiVersion: v1
kind: Pod
metadata:
  name: lair-postgresql-0
  namespace: lair
  annotations:
    backup.velero.io/backup-volumes: data
    pre.hook.backup.velero.io/command: '["/bin/bash", "-c", "pg_dump -U postgres > /tmp/backup.sql"]'
    post.hook.backup.velero.io/command: '["/bin/bash", "-c", "rm /tmp/backup.sql"]'
```

### 🔍 **Backup Monitoring**

#### **Backup Status**
```bash
# List all backups
velero backup get

# Check specific backup status
velero backup describe lair-daily-backup-20241201

# Check backup logs
velero backup logs lair-daily-backup-20241201

# Monitor backup progress
velero backup get --output table
```

#### **Backup Verification**
```bash
# Download backup for inspection
velero backup download lair-daily-backup-20241201

# Verify backup contents
tar -tzf lair-daily-backup-20241201.tar.gz | head -20

# Check backup size and duration
velero backup get lair-daily-backup-20241201 -o json | jq '.status'
```

---

## 🔄 Restore Operations

### 📥 **Restore Procedures**

#### **Complete System Restore**
```bash
# List available backups
velero backup get

# Create restore from backup
velero restore create lair-restore-$(date +%Y%m%d) \
  --from-backup lair-daily-backup-latest \
  --wait

# Check restore status
velero restore describe lair-restore-$(date +%Y%m%d)

# Monitor restore progress
velero restore get
```

#### **Selective Restore**
```bash
# Restore specific namespace
velero restore create lair-namespace-restore \
  --from-backup lair-daily-backup-latest \
  --include-namespaces lair \
  --wait

# Restore specific resources
velero restore create lair-secrets-restore \
  --from-backup lair-daily-backup-latest \
  --include-resources secrets,configmaps \
  --wait

# Restore with namespace mapping
velero restore create lair-test-restore \
  --from-backup lair-daily-backup-latest \
  --namespace-mappings lair:lair-test \
  --wait
```

#### **Application-Specific Restore**
```bash
# Restore specific application
velero restore create openwebui-restore \
  --from-backup lair-daily-backup-latest \
  --selector app=openwebui \
  --wait

# Restore with resource modifications
velero restore create lair-modified-restore \
  --from-backup lair-daily-backup-latest \
  --restore-volumes=false \
  --wait
```

### 🔧 **Restore Verification**

#### **Post-Restore Checks**
```bash
# Check restored resources
kubectl get all -n lair
kubectl get pvc -n lair
kubectl get secrets -n lair

# Verify application functionality
kubectl exec -n lair deployment/lair-openwebui -- curl -f http://localhost:8080/health
kubectl exec -n lair statefulset/lair-ollama -- curl -f http://localhost:11434/api/tags

# Check data integrity
kubectl exec -n lair statefulset/lair-postgresql -- psql -U postgres -c "\l"
```

---

## 🗄️ Storage Backend Configuration

### ☁️ **Cloud Storage Backends**

#### **AWS S3 Configuration**
```yaml
# AWS S3 backend
velero:
  configuration:
    provider: aws
    backupStorageLocation:
      bucket: lair-backups
      config:
        region: us-west-2
        kmsKeyId: arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012
```

#### **OVH Cloud Storage**
```yaml
# OVH S3-compatible storage
velero:
  configuration:
    provider: aws
    backupStorageLocation:
      bucket: lair-backups
      config:
        region: gra
        s3Url: https://s3.gra.io.cloud.ovh.net
        s3ForcePathStyle: true
```

#### **Google Cloud Storage**
```yaml
# GCS backend
velero:
  configuration:
    provider: gcp
    backupStorageLocation:
      bucket: lair-backups
      config:
        serviceAccount: velero@project-id.iam.gserviceaccount.com
```

### 🏠 **Local Storage Backends**

#### **MinIO Configuration**
```yaml
# Local MinIO backend
velero:
  configuration:
    provider: aws
    backupStorageLocation:
      bucket: lair-backups
      config:
        region: minio
        s3Url: http://lair-minio:9000
        s3ForcePathStyle: true
        publicUrl: http://lair-minio:9000
```

#### **NFS Storage**
```yaml
# NFS backend (via CSI)
velero:
  configuration:
    provider: csi
    backupStorageLocation:
      bucket: lair-backups
      config:
        path: /nfs/backups
```

---

## 📊 Monitoring & Alerting

### 🔍 **Backup Monitoring**

#### **Backup Health Checks**
```bash
# Create backup monitoring script
cat > /usr/local/bin/velero-health-check.sh << 'EOF'
#!/bin/bash

echo "=== Velero Health Check ==="
echo "Timestamp: $(date)"

# Check Velero pods
echo "=== Velero Pods ==="
kubectl get pods -n velero

# Check recent backups
echo "=== Recent Backups ==="
velero backup get | head -10

# Check backup failures
echo "=== Failed Backups ==="
velero backup get --output json | jq -r '.items[] | select(.status.phase == "Failed") | .metadata.name'

# Check storage location
echo "=== Storage Location Status ==="
velero backup-location get

# Check schedule status
echo "=== Backup Schedules ==="
velero schedule get
EOF

chmod +x /usr/local/bin/velero-health-check.sh
```

#### **Automated Monitoring**
```bash
# Schedule health checks
crontab -e

# Add monitoring job
0 */6 * * * /usr/local/bin/velero-health-check.sh >> /var/log/velero-health.log 2>&1
```

### 🚨 **Backup Alerting**

#### **Backup Failure Alerts**
```bash
# Create backup alert script
cat > /usr/local/bin/velero-alerts.sh << 'EOF'
#!/bin/bash

ALERT_EMAIL="admin@example.com"
WEBHOOK_URL=""  # Slack/Discord webhook

# Check for failed backups in last 24 hours
FAILED_BACKUPS=$(velero backup get --output json | jq -r '.items[] | select(.status.phase == "Failed" and (.metadata.creationTimestamp | fromdateiso8601) > (now - 86400)) | .metadata.name')

if [ ! -z "$FAILED_BACKUPS" ]; then
    MESSAGE="Velero backup failures detected: $FAILED_BACKUPS"
    
    # Email alert
    if [ ! -z "$ALERT_EMAIL" ]; then
        echo "$MESSAGE" | mail -s "Velero Backup Alert" "$ALERT_EMAIL"
    fi
    
    # Webhook alert
    if [ ! -z "$WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"🚨 $MESSAGE\"}" \
            "$WEBHOOK_URL"
    fi
fi

# Check backup age
LAST_BACKUP_AGE=$(velero backup get --output json | jq -r '.items[0].metadata.creationTimestamp | fromdateiso8601 | now - . | floor')
if [ $LAST_BACKUP_AGE -gt 172800 ]; then  # 48 hours
    MESSAGE="Last backup is older than 48 hours"
    echo "$MESSAGE" | mail -s "Velero Backup Age Alert" "$ALERT_EMAIL"
fi
EOF

chmod +x /usr/local/bin/velero-alerts.sh
```

---

## 🚨 Troubleshooting

### 🔧 **Common Issues**

#### **Backup Failures**
```bash
# Symptom: Backups failing or incomplete
# Check Velero logs
kubectl logs -n velero deployment/velero

# Check backup details
velero backup describe <backup-name>
velero backup logs <backup-name>

# Common solutions:
# 1. Check storage credentials
kubectl get secret -n velero cloud-credentials -o yaml

# 2. Verify storage location
velero backup-location get

# 3. Check permissions
# Ensure service account has proper permissions
```

#### **Restore Issues**
```bash
# Symptom: Restore operations failing
# Check restore status
velero restore describe <restore-name>
velero restore logs <restore-name>

# Check for resource conflicts
kubectl get events -n lair | grep -i error

# Solution: Clean up conflicting resources
kubectl delete <resource-type> <resource-name> -n lair
```

#### **Storage Connection Issues**
```bash
# Symptom: Cannot connect to backup storage
# Test storage connectivity
kubectl exec -n velero deployment/velero -- aws s3 ls s3://lair-backups/

# Check credentials
kubectl get secret -n velero cloud-credentials -o jsonpath='{.data.cloud}' | base64 -d

# Verify storage location configuration
kubectl get backupstoragelocations -n velero -o yaml
```

---

## 🎯 Best Practices

### 💾 **Backup Best Practices**
- **Regular Testing**: Test restore procedures regularly
- **Multiple Locations**: Use multiple backup storage locations
- **Encryption**: Enable backup encryption for sensitive data
- **Retention Policies**: Implement appropriate retention policies
- **Monitoring**: Set up comprehensive backup monitoring and alerting

### 🔒 **Security Best Practices**
- **Access Control**: Limit access to backup storage
- **Encryption**: Encrypt backups at rest and in transit
- **Credential Management**: Rotate backup credentials regularly
- **Network Security**: Secure backup network traffic
- **Audit Logging**: Enable audit logging for backup operations

### 📊 **Operational Best Practices**
- **Documentation**: Document backup and restore procedures
- **Automation**: Automate backup operations where possible
- **Capacity Planning**: Monitor backup storage usage
- **Performance**: Optimize backup performance for large datasets
- **Disaster Recovery**: Maintain off-site backup copies

---

**🎯 Ready to protect your data?** Continue with [Disaster Recovery Procedures](../../maintenance/backup-restore/README.md) or explore [Storage Configuration](../storage/README.md)!
