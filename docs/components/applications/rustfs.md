# 🗄️ RustFS - S3-Compatible Object Storage

> **Complete guide to RustFS configuration, bucket management, and S3-compatible storage in Lair**

RustFS is the high-performance S3-compatible object storage platform in Lair (written in Rust, Apache-2.0 licensed), providing scalable file storage for applications, backups, and data management. It exposes the standard S3 API on port 9000, the web console on port 9001, and ships pre-built for both `amd64` and `arm64` (standard, Jetson, and DGX Spark platforms).

---

## 🎯 Overview

RustFS serves as the primary object storage solution in Lair, offering S3-compatible APIs for file storage, backup, and data management across all applications.

### ✨ **Key Features**
- **🔗 S3-Compatible API**: Works with `mc`, `aws-cli`, boto3, and any S3 SDK
- **🚀 High Performance**: Rust-based engine, memory-safe and fast
- **🌐 Web Console**: Built-in management interface (port 9001)
- **🔒 Security**: Object Lock (WORM), server-side encryption, IAM policies, OIDC/SSO
- **📊 Monitoring**: `/health` endpoint and Prometheus metrics
- **🔄 Versioning**: Object versioning, lifecycle management, bucket quota
- **🏗️ Multi-Arch**: Single image for `amd64` and `arm64` nodes
- **📜 License**: Apache 2.0 (no AGPL constraints)

### 🔗 **Integration Points**
- **OpenWebUI**: **Primary file storage backend** (automatic when RustFS is enabled)
- **N8N**: File storage for workflow automation
- **Applications**: General-purpose S3 file storage

---

## 🚀 Getting Started

> **✨ Note**: When RustFS is enabled during Lair installation, **OpenWebUI automatically uses it as the storage backend**. The bucket `openwebui-storage` is created automatically, and no manual configuration is needed for basic functionality.

### 🌐 **Accessing RustFS**

#### **Web Console Access**
```bash
# LAN Access (default configuration)
https://storage.hostname.local

# Public Access (if configured)
https://storage.example.com

# Internal Access (from within cluster)
http://lair-rustfs.lair.svc.cluster.local:9001  # Console
http://lair-rustfs.lair.svc.cluster.local:9000  # S3 API
```

#### **Credentials**
```bash
# Default root credentials (change in production!)
Access Key (user): rustfsadmin
Secret Key: rustfsadmin123

# Or custom credentials set during installation
# (root_user / root_password in the lair config file)
```

> The root credential pair provides both administrative **and** S3 API access. For anything beyond administration, create scoped users and policies through the console.

### 🔧 **Initial Setup**

#### **First Login**
```bash
# Check RustFS status
kubectl get pods -n lair -l app=rustfs

# Health check
kubectl exec -n lair deployment/rustfs -- curl -sf http://localhost:9000/health

# Access the console
# Navigate to your configured domain
# Login with the root credentials
# Create buckets and access policies as needed
```

#### **Basic Configuration**
1. **Login** to the RustFS console
2. **Create Buckets** for different applications
3. **Set Access Policies** for security
4. **Create Service Accounts** for applications
5. **Configure Notifications** (optional)

---

## 🔧 Architecture & Deployment

### 🏗️ **RustFS Architecture**

#### **Single-Node Deployment**
```
┌─────────────────────────────────────────────────────────────────┐
│                     🗄️ RUSTFS ARCHITECTURE                       │
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
# RustFS Deployment (managed by the Lair Helm chart)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rustfs
  namespace: lair
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rustfs
  template:
    spec:
      # RustFS runs as non-root user 'rustfs' (UID/GID 10001)
      securityContext:
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
      containers:
      - name: rustfs
        image: rustfs/rustfs:1.0.0
        args:
        - /data
        env:
        - name: RUSTFS_ACCESS_KEY
          value: "<root-user>"
        - name: RUSTFS_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: rustfs-secret
              key: RUSTFS_SECRET_KEY
        - name: RUSTFS_ADDRESS
          value: ":9000"
        - name: RUSTFS_CONSOLE_ADDRESS
          value: ":9001"
        - name: RUSTFS_CONSOLE_ENABLE
          value: "true"
```

#### **Service Configuration**
```yaml
# RustFS Service
apiVersion: v1
kind: Service
metadata:
  name: lair-rustfs
  namespace: lair
spec:
  selector:
    app: rustfs
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
```yaml
# values.yaml
rustfs:
  enabled: true
  image:
    repository: rustfs/rustfs   # multi-arch (amd64 + arm64)
    tag: "1.0.0"
  rootUser: rustfsadmin
  rootPassword: "strong-password"
  storage:
    size: 10Gi
  port: 9000
  consolePort: 9001
  resources:
    limits:
      memory: "1Gi"
      cpu: "500m"
    requests:
      memory: "512Mi"
      cpu: "250m"
```

---

## 🪣 Bucket Management

### 📦 **Creating Buckets**

#### **Via Web Console**
1. Login to the RustFS console (port 9001)
2. Go to **Buckets** → **Create Bucket**
3. Enter bucket name (e.g., `lair-documents`)
4. Configure settings:
   - **Versioning**: Enable for data protection
   - **Object Lock**: Enable for compliance
   - **Encryption**: Enable for security

#### **Via S3 Client (rc)**
```bash
# Run rc from a temporary pod using the RustFS CLI client image
kubectl run rc-tmp -n lair --rm -it --image=rustfs/rc:latest --restart=Never -- sh

# Configure an alias (use the RustFS root credentials)
rc alias set rustfs http://lair-rustfs.lair.svc.cluster.local:9000 <access-key> <secret-key>

# Create buckets
rc mb rustfs/lair-documents
rc mb rustfs/lair-backups
rc mb rustfs/lair-models
rc mb rustfs/lair-images
```

#### **Via S3 API**
```python
# Python example using boto3 (any S3-compatible client works)
import boto3

s3_client = boto3.client(
    's3',
    endpoint_url='http://lair-rustfs:9000',
    aws_access_key_id='<your-access-key>',
    aws_secret_access_key='<your-secret-key>'
)

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

#### **Applying Policies**
```bash
# Standard canned policies
rc anonymous set public rustfs/lair-public
rc anonymous set download rustfs/lair-downloads

# Custom policy
rc anonymous set-json policy.json rustfs/lair-custom
```

---

## 🔑 Access Management

### 👤 **User Management**

#### **Creating Users / Service Accounts**
```bash
# Create a user for N8N
rc admin user add rustfs n8n-service n8n-secret-password

# Create a user for OpenWebUI
rc admin user add rustfs openwebui-service openwebui-secret-password

# Create and attach a policy
rc admin policy create rustfs n8n-policy policy.json
rc admin policy attach rustfs n8n-policy --user n8n-service
```

### 🔐 **Security Configuration**

- **TLS/SSL**: terminated by the ingress (mkcert for LAN, Let's Encrypt for public)
- **Server-side encryption**: supported (KMS backends: Vault KV2/Transit, AWS KMS)
- **OIDC/SSO**: supported for console and API authentication
- **Audit**: request-level audit targets to external endpoints

---

## 🔌 Application Integration

### 🤖 **OpenWebUI Integration (Automatic)**

#### **Automatic S3 Backend**
When RustFS is enabled, OpenWebUI automatically uses it as the primary storage backend for all files, replacing the default local filesystem storage.

**Features:**
- ✅ **Automatic bucket creation**: `openwebui-storage` bucket is created on first deployment
- ✅ **Zero configuration required**: Credentials and endpoints configured automatically
- ✅ **Scalable storage**: No storage size limits, only RustFS capacity
- ✅ **Better performance**: Optimized for concurrent access and large files
- ✅ **RAG document storage**: All uploaded documents stored in S3
- ✅ **User file uploads**: Profile pictures, attachments, and media

#### **Storage Structure**
```
openwebui-storage/
├── data/              # User data and configurations
├── uploads/           # File uploads and attachments
├── cache/             # Temporary cache files
├── docs/              # RAG documents
└── static/            # Static assets
```

#### **Configuration**
```yaml
# Automatic configuration when RustFS is enabled
openWebUI:
  s3:
    enabled: true                        # Auto-enabled when rustfs.enabled: true
    bucketName: "openwebui-storage"      # Default bucket name
    region: "us-east-1"                  # S3 default region
    addressingStyle: "path"              # Path-style addressing
    useAccelerateEndpoint: false
    enableTagging: false
    keyPrefix: ""                        # Optional S3 key prefix

# Environment variables (automatically configured in the pod)
env:
  STORAGE_PROVIDER: "s3"
  S3_ENDPOINT_URL: "http://lair-rustfs.lair.svc.cluster.local:9000"
  S3_BUCKET_NAME: "openwebui-storage"
  S3_REGION_NAME: "us-east-1"
  S3_ADDRESSING_STYLE: "path"
  AWS_ACCESS_KEY_ID: "<from-rustfs-config>"
  AWS_SECRET_ACCESS_KEY: "<from-rustfs-config>"
```

#### **Bucket Management**
```bash
# Check OpenWebUI bucket
kubectl run rc-tmp -n lair --rm -it --image=rustfs/rc:latest --restart=Never -- \
  sh -c "rc alias set rustfs http://lair-rustfs.lair.svc.cluster.local:9000 $USER $PASS && rc ls rustfs/openwebui-storage"

# View bucket size
rc du rustfs/openwebui-storage

# List recent uploads
rc ls --recursive rustfs/openwebui-storage/uploads

# Backup OpenWebUI data
rc mirror rustfs/openwebui-storage /tmp/backup
```

#### **Troubleshooting OpenWebUI-RustFS Integration**
```bash
# Check if S3 storage is enabled
kubectl exec -n lair deployment/lair-openwebui -- env | grep S3

# Test RustFS connectivity from OpenWebUI
kubectl exec -n lair deployment/lair-openwebui -- curl -sf http://lair-rustfs:9000/health

# Check bucket creation logs (init container)
kubectl logs -n lair deployment/lair-openwebui -c rustfs-bucket-setup

# Check S3 credentials
kubectl get configmap -n lair services-config -o jsonpath='{.data.RUSTFS_ACCESS_KEY}'
```

---

### ⚡ **N8N Integration**

N8N uses the S3 filesystem alias for file storage (endpoint and credentials are injected
automatically when RustFS is enabled):

```yaml
# Automatically configured in the N8N deployment
env:
  N8N_FILESYSTEM_ALIAS_S3_ENDPOINT: "http://lair-rustfs.lair.svc.cluster.local:9000"
  N8N_FILESYSTEM_ALIAS_S3_ACCESS_KEY_ID: "<from-rustfs-config>"
  N8N_FILESYSTEM_ALIAS_S3_SECRET_ACCESS_KEY: "<from-rustfs-config>"
```

---

## 📊 Monitoring & Management

### 🔍 **Health Monitoring**

```bash
# Health check (API)
kubectl exec -n lair deployment/rustfs -- curl -sf http://localhost:9000/health

# Pod status
kubectl get pods -n lair -l app=rustfs

# Storage usage
kubectl exec -n lair deployment/rustfs -- df -h /data
```

### 📝 **Logging & Metrics**

```bash
# Application logs
kubectl logs -n lair deployment/rustfs -f

# Filter for errors
kubectl logs -n lair deployment/rustfs | grep -i "error\|fail\|exception"
```

RustFS also exposes Prometheus-compatible metrics and can be wired into an external
observability stack (Grafana / Prometheus / OpenTelemetry) via its configuration options.

---

## 🚨 Troubleshooting

### 🔧 **Common Issues**

#### **Connection Refused**
```bash
# Check pod status
kubectl get pods -n lair -l app=rustfs

# Check service
kubectl get services -n lair lair-rustfs

# Port forwarding
kubectl port-forward -n lair deployment/rustfs 9000:9000 9001:9001

# Test local connection
curl http://localhost:9000/health
curl http://localhost:9001
```

#### **Authentication Failures**
```bash
# Check credentials
kubectl exec -n lair deployment/rustfs -- env | grep RUSTFS_

# Verify credentials with rc
rc alias set test http://lair-rustfs.lair.svc.cluster.local:9000 <access-key> <secret-key>
```

#### **Permission Issues**
```bash
# RustFS runs as non-root user 10001 - make sure the PVC is group-writable
kubectl describe pvc -n lair rustfs-pvc

# Check volume permissions
kubectl exec -n lair deployment/rustfs -- ls -la /data
```

#### **Storage Issues**
```bash
# Check storage usage
kubectl exec -n lair deployment/rustfs -- df -h /data

# Check PVC status
kubectl get pvc -n lair rustfs-pvc

# Expand storage (if supported by the storage class)
kubectl patch pvc rustfs-pvc -n lair -p '{"spec":{"resources":{"requests":{"storage":"100Gi"}}}}'
```

---

## 🎯 Best Practices

### 🚀 **Performance Best Practices**
- **Resource Allocation**: Allocate sufficient CPU and memory for I/O operations
- **Storage Backend**: Use high-performance storage classes (SSD-based)
- **Network Optimization**: Ensure low-latency network connectivity
- **Concurrent Connections**: Tune connection limits based on workload

### 🔐 **Security Best Practices**
- **Access Control**: Use least-privilege access policies
- **Credential Management**: Never use the default `rustfsadmin` credentials in production
- **Encryption**: Enable encryption at rest and in transit
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
