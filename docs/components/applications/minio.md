# 🗄️ MinIO - S3-Compatible Object Storage

> **Complete guide to MinIO configuration, bucket management, and S3-compatible storage in Lair**

MinIO is the high-performance S3-compatible object storage platform in Lair, providing scalable file storage for applications, backups, and data management. This guide covers installation, configuration, bucket management, and integration.

---

## 🎯 Overview

MinIO serves as the primary object storage solution in Lair, offering S3-compatible APIs for file storage, backup, and data management across all applications.

### ✨ **Key Features**
- **🔗 S3-Compatible API**: Drop-in replacement for Amazon S3
- **🚀 High Performance**: Optimized for speed and throughput
- **🌐 Web Console**: User-friendly management interface
- **🔒 Security**: Built-in encryption, access policies, and authentication
- **📊 Monitoring**: Comprehensive metrics and health monitoring
- **🔄 Versioning**: Object versioning and lifecycle management
- **⚡ Scalability**: Horizontal scaling and distributed storage

### 🔗 **Integration Points**
- **OpenWebUI**: **Primary file storage backend** (automatic when MinIO is enabled)
- **N8N**: File storage for workflow automation
- **ComfyUI**: Model and image storage
- **Velero**: Backup storage backend
- **Applications**: General-purpose file storage

---

## 🚀 Getting Started

> **✨ Note**: When MinIO is enabled during Lair installation, **OpenWebUI automatically uses it as the storage backend**. The bucket `openwebui-storage` is created automatically, and no manual configuration is needed for basic functionality.

### 🌐 **Accessing MinIO**

#### **Web Console Access**
```bash
# LAN Access (default configuration)
https://storage.hostname.local

# Public Access (if configured)
https://storage.example.com

# Internal Access (from within cluster)
http://lair-minio.lair.svc.cluster.local:9001  # Console
http://lair-minio.lair.svc.cluster.local:9000  # S3 API
```

#### **Default Credentials**
```bash
# Default root credentials (change in production!)
Username: minioadmin
Password: minioadmin123

# Or custom credentials set during installation
Username: <your-root-user>
Password: <your-root-password>
```

### 🔧 **Initial Setup**

#### **First Login**
```bash
# Check MinIO status
kubectl get pods -n lair -l app=minio

# Access MinIO console
# Navigate to your configured domain
# Login with root credentials
# Create first bucket and access keys
```

#### **Basic Configuration**
1. **Login** to MinIO console
2. **Create Buckets** for different applications
3. **Set Access Policies** for security
4. **Generate Access Keys** for applications
5. **Configure Notifications** (optional)

---

## 🔧 Architecture & Deployment

### 🏗️ **MinIO Architecture**

#### **Single-Node Deployment**
```
┌─────────────────────────────────────────────────────────────────┐
│                     🗄️ MINIO ARCHITECTURE                        │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Web Console   │  │    S3 API       │  │   Storage       │  │
│  │   (Port 9001)   │  │  (Port 9000)    │  │   Backend       │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                       💾 STORAGE LAYER                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Persistent    │  │     Buckets     │  │   Policies      │  │
│  │    Volume       │  │   (Namespaces)  │  │  (Access Control)│ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

#### **Deployment Configuration**
```yaml
# MinIO Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: lair
spec:
  replicas: 1  # Single replica for simplicity
  selector:
    matchLabels:
      app: minio
  template:
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - ":9001"
```

#### **Service Configuration**
```yaml
# MinIO Service
apiVersion: v1
kind: Service
metadata:
  name: lair-minio
  namespace: lair
spec:
  selector:
    app: minio
  ports:
  - name: api
    port: 9000
    targetPort: 9000
  - name: console
    port: 80
    targetPort: 9001
  type: ClusterIP
```

### 📊 **Resource Configuration**

#### **Standard Configuration**
```yaml
minio:
  resources:
    limits:
      memory: "1Gi"
      cpu: "500m"
    requests:
      memory: "512Mi"
      cpu: "250m"
  
  storage:
    size: "50Gi"
    storageClassName: "longhorn"
```

#### **High-Performance Configuration**
```yaml
minio:
  resources:
    limits:
      memory: "2Gi"
      cpu: "1000m"
    requests:
      memory: "1Gi"
      cpu: "500m"
  
  storage:
    size: "200Gi"
    storageClassName: "longhorn"
```

---

## 🪣 Bucket Management

### 📦 **Creating Buckets**

#### **Via Web Console**
1. Login to MinIO console
2. Click **"Create Bucket"**
3. Enter bucket name (e.g., `lair-documents`)
4. Configure settings:
   - **Versioning**: Enable for data protection
   - **Object Locking**: Enable for compliance
   - **Encryption**: Enable for security

#### **Via MinIO Client (mc)**
```bash
# Install MinIO client in container
kubectl exec -it -n lair deployment/lair-minio -- /bin/bash

# Configure mc alias
mc alias set local http://localhost:9000 minioadmin minioadmin123

# Create buckets
mc mb local/lair-documents
mc mb local/lair-backups
mc mb local/lair-models
mc mb local/lair-images
```

#### **Via S3 API**
```python
# Python example using boto3
import boto3

# Configure S3 client for MinIO
s3_client = boto3.client(
    's3',
    endpoint_url='http://lair-minio:9000',
    aws_access_key_id='minioadmin',
    aws_secret_access_key='minioadmin123'
)

# Create bucket
s3_client.create_bucket(Bucket='lair-documents')
```

### 🔒 **Bucket Policies**

#### **Public Read Policy**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::lair-public/*"
    }
  ]
}
```

#### **Application-Specific Policy**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::*:user/n8n-service"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::lair-workflows/*"
    }
  ]
}
```

#### **Applying Policies**
```bash
# Via MinIO client
mc policy set public local/lair-public
mc policy set download local/lair-downloads
mc policy set upload local/lair-uploads

# Custom policy
mc policy set-json policy.json local/lair-custom
```

---

## 🔑 Access Management

### 👤 **User Management**

#### **Creating Service Accounts**
```bash
# Create service account for N8N
mc admin user add local n8n-service n8n-secret-password

# Create service account for OpenWebUI
mc admin user add local openwebui-service openwebui-secret-password

# Create service account for ComfyUI
mc admin user add local comfyui-service comfyui-secret-password
```

#### **Access Keys**
```bash
# Generate access keys
mc admin user svcacct add local n8n-service --access-key n8n-access --secret-key n8n-secret

# List service accounts
mc admin user svcacct list local n8n-service

# Remove service account
mc admin user svcacct rm local n8n-access
```

### 🔐 **Security Configuration**

#### **TLS/SSL Configuration**
```yaml
# TLS configuration (handled by ingress)
minio:
  tls:
    enabled: true
    certSecret: "minio-tls"
```

#### **Encryption at Rest**
```bash
# Enable server-side encryption
mc encrypt set sse-s3 local/lair-sensitive

# Configure encryption key
mc encrypt set sse-kms local/lair-encrypted --kms-key-id lair-key
```

#### **Access Logging**
```bash
# Enable access logging
mc admin config set local logger_webhook:1 endpoint="http://log-server:9000/minio"

# Configure audit logging
mc admin config set local audit_webhook:1 endpoint="http://audit-server:9000/minio"
```

---

## 🔌 Application Integration

### 🤖 **OpenWebUI Integration (Automatic)**

#### **Automatic S3 Backend**
When MinIO is enabled, OpenWebUI automatically uses it as the primary storage backend for all files, replacing the default local filesystem storage.

**Features:**
- ✅ **Automatic bucket creation**: `openwebui-storage` bucket is created on first deployment
- ✅ **Zero configuration required**: Credentials and endpoints configured automatically
- ✅ **Scalable storage**: No storage size limits, only MinIO capacity
- ✅ **Better performance**: Optimized for concurrent access and large files
- ✅ **RAG document storage**: All uploaded documents stored in S3
- ✅ **User file uploads**: Profile pictures, attachments, and media

#### **Storage Structure**
```bash
# OpenWebUI bucket structure in MinIO
openwebui-storage/
├── data/              # User data and configurations
├── uploads/           # File uploads and attachments
├── cache/             # Temporary cache files
├── docs/              # RAG documents
└── static/            # Static assets
```

#### **Configuration**
```yaml
# Automatic configuration when MinIO is enabled
openWebUI:
  s3:
    enabled: true                        # Auto-enabled when minio.enabled: true
    bucketName: "openwebui-storage"     # Default bucket name
    region: "us-east-1"                 # MinIO default region
    addressingStyle: "path"             # Path-style for MinIO
    useAccelerateEndpoint: false        # Disabled for MinIO
    enableTagging: false                # Disabled for MinIO
    keyPrefix: ""                       # Optional S3 key prefix

# Environment variables (automatically configured)
env:
  STORAGE_PROVIDER: "s3"
  S3_ENDPOINT_URL: "http://lair-minio.lair.svc.cluster.local:9000"
  S3_BUCKET_NAME: "openwebui-storage"
  S3_REGION_NAME: "us-east-1"
  S3_ADDRESSING_STYLE: "path"
  AWS_ACCESS_KEY_ID: "<from-minio-config>"
  AWS_SECRET_ACCESS_KEY: "<from-minio-config>"
```

#### **Bucket Management**
```bash
# Check OpenWebUI bucket
kubectl exec -n lair deployment/lair-minio -- mc ls minio/openwebui-storage

# View bucket size
kubectl exec -n lair deployment/lair-minio -- mc du minio/openwebui-storage

# List recent uploads
kubectl exec -n lair deployment/lair-minio -- mc ls --recursive minio/openwebui-storage/uploads

# Backup OpenWebUI data
kubectl exec -n lair deployment/lair-minio -- mc mirror minio/openwebui-storage /tmp/backup

# Set bucket versioning (recommended)
kubectl exec -n lair deployment/lair-minio -- mc version enable minio/openwebui-storage
```

#### **Migration from Local Storage**
If you're upgrading from a previous installation with local filesystem storage:

```bash
# 1. Backup existing OpenWebUI data
kubectl cp lair/lair-openwebui-xxx:/app/backend/data ./openwebui-backup

# 2. Enable MinIO in configuration
# Edit values-config.yaml:
# minio:
#   enabled: true

# 3. Upgrade deployment
helm upgrade --install lair . -n lair -f values-config.yaml
 

# 4. Upload backup data to MinIO (optional)
kubectl cp ./openwebui-backup lair/lair-openwebui-xxx:/tmp/
kubectl exec -n lair deployment/lair-openwebui -- mc mirror /tmp/openwebui-backup minio/openwebui-storage
```

#### **Troubleshooting OpenWebUI-MinIO Integration**
```bash
# Check if S3 storage is enabled
kubectl exec -n lair deployment/lair-openwebui -- env | grep S3

# Test MinIO connectivity from OpenWebUI
kubectl exec -n lair deployment/lair-openwebui -- curl http://lair-minio:9000

# Check bucket creation logs
kubectl logs -n lair deployment/lair-openwebui -c minio-bucket-setup

# Verify bucket exists
kubectl exec -n lair deployment/lair-minio -- mc ls minio/ | grep openwebui-storage

# Check S3 credentials
kubectl get configmap -n lair services-config -o jsonpath='{.data.MINIO_ACCESS_KEY}'
```

---

### ⚡ **N8N Integration**

#### **N8N S3 Configuration**
```yaml
# N8N environment variables for MinIO
n8n:
  extraEnv:
    - name: N8N_FILESYSTEM_ALIAS_S3_ENDPOINT
      value: "http://lair-minio:9000"
    - name: N8N_FILESYSTEM_ALIAS_S3_ACCESS_KEY_ID
      value: "n8n-access"
    - name: N8N_FILESYSTEM_ALIAS_S3_SECRET_ACCESS_KEY
      value: "n8n-secret"
    - name: N8N_FILESYSTEM_ALIAS_S3_BUCKET_NAME
      value: "lair-workflows"
```

#### **N8N Workflow Example**
```json
{
  "name": "File Upload to MinIO",
  "nodes": [
    {
      "name": "File Input",
      "type": "n8n-nodes-base.webhook"
    },
    {
      "name": "Upload to S3",
      "type": "n8n-nodes-base.s3",
      "parameters": {
        "operation": "upload",
        "bucketName": "lair-documents",
        "fileName": "={{$json.filename}}",
        "binaryData": true
      }
    }
  ]
}
```

### 🤖 **OpenWebUI Integration**

#### **Document Storage Configuration**
```yaml
# OpenWebUI MinIO integration
openWebUI:
  extraEnv:
    - name: MINIO_ENDPOINT
      value: "lair-minio:9000"
    - name: MINIO_ACCESS_KEY
      value: "openwebui-access"
    - name: MINIO_SECRET_KEY
      value: "openwebui-secret"
    - name: MINIO_BUCKET
      value: "lair-documents"
```

### 🎨 **ComfyUI Integration**

#### **Model Storage Configuration**
```yaml
# ComfyUI model storage in MinIO
comfyUI:
  extraEnv:
    - name: COMFYUI_S3_ENDPOINT
      value: "http://lair-minio:9000"
    - name: COMFYUI_S3_ACCESS_KEY
      value: "comfyui-access"
    - name: COMFYUI_S3_SECRET_KEY
      value: "comfyui-secret"
    - name: COMFYUI_S3_BUCKET
      value: "lair-models"
```

---

## 📊 Monitoring & Management

### 🔍 **Health Monitoring**

#### **MinIO Health Checks**
```bash
# Basic health check
kubectl exec -n lair deployment/lair-minio -- curl -f http://localhost:9000/minio/health/live

# Ready check
kubectl exec -n lair deployment/lair-minio -- curl -f http://localhost:9000/minio/health/ready

# Cluster status
kubectl exec -n lair deployment/lair-minio -- mc admin info local
```

#### **Resource Monitoring**
```bash
# Pod resource usage
kubectl top pod -n lair -l app=minio

# Storage usage
kubectl exec -n lair deployment/lair-minio -- df -h /data

# Bucket usage
kubectl exec -n lair deployment/lair-minio -- mc du local/
```

### 📝 **Logging & Metrics**

#### **MinIO Logs**
```bash
# Application logs
kubectl logs -n lair deployment/lair-minio -f

# Filter for errors
kubectl logs -n lair deployment/lair-minio | grep -i "error\|fail\|exception"

# Access logs
kubectl logs -n lair deployment/lair-minio | grep -E "GET|PUT|POST|DELETE"
```

#### **Metrics Collection**
```bash
# MinIO metrics endpoint
kubectl exec -n lair deployment/lair-minio -- curl http://localhost:9000/minio/v2/metrics/cluster

# Prometheus metrics
kubectl exec -n lair deployment/lair-minio -- curl http://localhost:9000/minio/prometheus/metrics
```

### 📊 **Performance Monitoring**

#### **Performance Metrics**
```bash
# Create performance monitoring script
cat > minio-performance.sh << 'EOF'
#!/bin/bash
echo "=== MinIO Performance Report ==="
echo "Timestamp: $(date)"

# API response time
echo "=== API Response Time ==="
time kubectl exec -n lair deployment/lair-minio -- curl -s http://localhost:9000/minio/health/live >/dev/null

# Storage usage
echo "=== Storage Usage ==="
kubectl exec -n lair deployment/lair-minio -- df -h /data

# Bucket statistics
echo "=== Bucket Statistics ==="
kubectl exec -n lair deployment/lair-minio -- mc du local/ --recursive

# Resource usage
echo "=== Resource Usage ==="
kubectl top pod -n lair -l app=minio
EOF

chmod +x minio-performance.sh
```

---

## 🚨 Troubleshooting

### 🔧 **Common Issues**

#### **Connection Refused**
```bash
# Symptom: Cannot connect to MinIO API or console
# Check pod status
kubectl get pods -n lair -l app=minio

# Check service
kubectl get services -n lair lair-minio

# Check port forwarding
kubectl port-forward -n lair deployment/lair-minio 9000:9000 9001:9001

# Test local connection
curl http://localhost:9000/minio/health/live
curl http://localhost:9001
```

#### **Authentication Failures**
```bash
# Symptom: Access denied or authentication errors
# Check credentials
kubectl exec -n lair deployment/lair-minio -- env | grep MINIO_

# Test credentials
kubectl exec -n lair deployment/lair-minio -- mc alias set test http://localhost:9000 minioadmin minioadmin123

# Reset root password
kubectl set env deployment/lair-minio -n lair MINIO_ROOT_PASSWORD=new-password
```

#### **Storage Issues**
```bash
# Symptom: Cannot write files or storage full
# Check storage usage
kubectl exec -n lair deployment/lair-minio -- df -h /data

# Check PVC status
kubectl get pvc -n lair minio-pvc

# Check storage class
kubectl describe pvc -n lair minio-pvc

# Expand storage (if supported)
kubectl patch pvc minio-pvc -n lair -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

#### **Performance Issues**
```bash
# Symptom: Slow upload/download speeds
# Check resource limits
kubectl describe pod -n lair -l app=minio | grep -A 5 -B 5 "Limits\|Requests"

# Monitor I/O
kubectl exec -n lair deployment/lair-minio -- iostat -x 1 5

# Check network connectivity
kubectl exec -n lair deployment/lair-openwebui -- curl -w "%{time_total}" http://lair-minio:9000/minio/health/live
```

### 🔄 **Recovery Procedures**

#### **Data Recovery**
```bash
# Backup MinIO data
kubectl exec -n lair deployment/lair-minio -- tar -czf /tmp/minio-backup.tar.gz /data

# Copy backup out
kubectl cp lair/lair-minio-0:/tmp/minio-backup.tar.gz minio-backup.tar.gz

# Restore data
kubectl cp minio-backup.tar.gz lair/lair-minio-0:/tmp/
kubectl exec -n lair deployment/lair-minio -- tar -xzf /tmp/minio-backup.tar.gz -C /
```

#### **Configuration Recovery**
```bash
# Export bucket policies
kubectl exec -n lair deployment/lair-minio -- mc policy get-json local/lair-documents > bucket-policy.json

# Restore bucket policies
kubectl cp bucket-policy.json lair/lair-minio-0:/tmp/
kubectl exec -n lair deployment/lair-minio -- mc policy set-json /tmp/bucket-policy.json local/lair-documents
```

---

## 🔧 Advanced Configuration

### 🎛️ **Advanced Features**

#### **Object Versioning**
```bash
# Enable versioning
mc version enable local/lair-documents

# List object versions
mc ls --versions local/lair-documents/

# Restore specific version
mc cp local/lair-documents/file.txt --version-id version-id local/lair-documents/file-restored.txt
```

#### **Lifecycle Management**
```json
{
  "Rules": [
    {
      "ID": "DeleteOldVersions",
      "Status": "Enabled",
      "Filter": {"Prefix": "temp/"},
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 30
      }
    },
    {
      "ID": "TransitionToIA",
      "Status": "Enabled",
      "Transition": {
        "Days": 30,
        "StorageClass": "STANDARD_IA"
      }
    }
  ]
}
```

#### **Event Notifications**
```bash
# Configure webhook notifications
mc event add local/lair-documents arn:minio:sqs::webhook:http://webhook-server:9000/minio

# Configure AMQP notifications
mc event add local/lair-documents arn:minio:amqp::amqp:amqp://rabbitmq:5672
```

### 🔌 **API Integration**

#### **Python SDK Example**
```python
from minio import Minio
from minio.error import S3Error

# Initialize MinIO client
client = Minio(
    "lair-minio:9000",
    access_key="minioadmin",
    secret_key="minioadmin123",
    secure=False
)

# Upload file
def upload_file(bucket_name, object_name, file_path):
    try:
        client.fput_object(bucket_name, object_name, file_path)
        print(f"File {file_path} uploaded successfully")
    except S3Error as e:
        print(f"Error uploading file: {e}")

# Download file
def download_file(bucket_name, object_name, file_path):
    try:
        client.fget_object(bucket_name, object_name, file_path)
        print(f"File downloaded successfully to {file_path}")
    except S3Error as e:
        print(f"Error downloading file: {e}")

# List objects
def list_objects(bucket_name):
    try:
        objects = client.list_objects(bucket_name)
        for obj in objects:
            print(f"Object: {obj.object_name}, Size: {obj.size}")
    except S3Error as e:
        print(f"Error listing objects: {e}")
```

#### **JavaScript SDK Example**
```javascript
const Minio = require('minio');

// Initialize MinIO client
const minioClient = new Minio.Client({
    endPoint: 'lair-minio',
    port: 9000,
    useSSL: false,
    accessKey: 'minioadmin',
    secretKey: 'minioadmin123'
});

// Upload file
async function uploadFile(bucketName, objectName, filePath) {
    try {
        await minioClient.fPutObject(bucketName, objectName, filePath);
        console.log('File uploaded successfully');
    } catch (error) {
        console.error('Error uploading file:', error);
    }
}

// Generate presigned URL
async function generatePresignedUrl(bucketName, objectName) {
    try {
        const url = await minioClient.presignedGetObject(bucketName, objectName, 24*60*60);
        console.log('Presigned URL:', url);
        return url;
    } catch (error) {
        console.error('Error generating URL:', error);
    }
}
```

---

## 🎯 Best Practices

### 🚀 **Performance Best Practices**
- **Resource Allocation**: Allocate sufficient CPU and memory for I/O operations
- **Storage Backend**: Use high-performance storage classes (SSD-based)
- **Network Optimization**: Ensure low-latency network connectivity
- **Concurrent Connections**: Tune connection limits based on workload
- **Caching**: Implement client-side caching for frequently accessed objects

### 🔒 **Security Best Practices**
- **Access Control**: Use least-privilege access policies
- **Encryption**: Enable encryption at rest and in transit
- **Credential Management**: Rotate access keys regularly
- **Network Security**: Restrict network access to authorized services
- **Audit Logging**: Enable comprehensive audit logging

### 📊 **Operational Best Practices**
- **Regular Monitoring**: Monitor storage usage and performance metrics
- **Backup Strategy**: Implement regular data backups
- **Lifecycle Management**: Configure object lifecycle policies
- **Version Control**: Enable versioning for critical data
- **Documentation**: Document bucket policies and access patterns

---

**🎯 Ready to manage your object storage?** Continue with [PostgreSQL Database](../services-overview.md) or explore [Redis Cache](../services-overview.md)!
