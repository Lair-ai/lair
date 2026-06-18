# ⚙️ Advanced Configuration

> **Complete guide to advanced configuration options, customizations, and integration patterns for Lair**

This guide covers advanced configuration scenarios, custom setups, multi-environment deployments, and integration patterns for power users and enterprise deployments.

---

## 🎯 Overview

Lair provides extensive customization capabilities through Helm values, environment variables, custom configurations, and integration patterns. This guide covers advanced scenarios beyond the standard setup.

### 🏗️ **Advanced Configuration Architecture**
```
┌─────────────────────────────────────────────────────────────────┐
│                    ⚙️ CONFIGURATION LAYERS                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Base Values   │  │   Environment   │  │    Custom       │  │
│  │  (values.yaml)  │  │   Overrides     │  │  Integrations   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🎯 CUSTOMIZATION AREAS                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Application   │  │   Infrastructure│  │   Integration   │  │
│  │  Configuration  │  │   Settings      │  │   Patterns      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
┌─────────────────────────────────────────────────────────────────┐
│                     🌐 DEPLOYMENT PATTERNS                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ Single-Tenant   │  │  Multi-Tenant   │  │   Federated     │  │
│  │   Deployment    │  │   Deployment    │  │   Deployment    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 📊 **Configuration Complexity Levels**

| Level | Scope | Complexity | Use Case |
|-------|-------|------------|----------|
| **Basic** | Standard templates | Low | Standard deployments |
| **Intermediate** | Custom values | Medium | Tailored deployments |
| **Advanced** | Custom integrations | High | Enterprise/specialized |
| **Expert** | Custom components | Very High | Fully customized solutions |

---

## 🔧 Custom Configuration Files

### 📋 **Configuration File Structure**

Lair uses YAML configuration files to customize deployments. Understanding the structure enables advanced customizations.

#### **Base Configuration Template**
```yaml
# values-custom.yaml - Advanced configuration example
config_name: "enterprise-production"
detection_choice: 1
use_detected_resources: false

# Platform configuration
platform:
  is_jetson: false
  has_gpu: true
  vram_percentage: 70
  access_mode: "dual"  # lan, public, or dual
  system_hostname: "aiplatform"

# Email configuration
email:
  cert_email: "admin@company.com"

# Resource overrides
resources:
  cpu_cores: 16
  memory_gb: 64
  storage_gb: 1000

# Access configuration
access:
  lan:
    enabled: true
    tls_enabled: true
    domains:
      openwebui: "ai.aiplatform.local"
      n8n: "n8n.aiplatform.local"
      comfyui: "images.aiplatform.local"
      minio: "storage.aiplatform.local"
  
  public:
    enabled: true
    domains:
      openwebui: "ai.company.com"
      n8n: "n8n.company.com"
      comfyui: "images.company.com"
      minio: "storage.company.com"

# Component-specific configurations
components:
  openwebui:
    enabled: true
    storage_size: "50Gi"
    # Advanced OpenWebUI configuration
    sso:
      enabled: true
      provider: "oidc"
      oauth:
        clientId: "lair-openwebui"
        clientSecret: "your-secret-here"
        providerUrl: "https://auth.company.com"
    rag:
      contentExtractionEngine: "tika"
      enableHybridSearch: true
      chunkSize: 1500
      chunkOverlap: 300
  
  ollama:
    enabled: true
    storage_size: "200Gi"
    gpu_enabled: true
    image: "ollama/ollama:latest"
    # Custom model preloading
    models:
      - "llama3.1:8b"
      - "codellama:13b"
      - "mistral:7b"
  
  n8n:
    enabled: true
    storage_size: "30Gi"
    workers: 4
    # Custom N8N configuration
    smtp:
      enabled: true
      host: "smtp.company.com"
      port: 587
      user: "noreply@company.com"
      password: "smtp-password"
    extraEnv:
      - name: N8N_METRICS
        value: "true"
      - name: N8N_LOG_LEVEL
        value: "debug"
  
  comfyui:
    enabled: true
    storage_size: "100Gi"
    gpu_enabled: true
    image: "mmartial/comfyui-nvidia-docker:ubuntu24_cuda12.6.3-latest"
  
  minio:
    enabled: true
    storage_size: "500Gi"
    rootUser: "admin"
    rootPassword: "secure-admin-password"
    accessKey: "lair-access"
    secretKey: "secure-secret-key"

# Storage configuration
storage:
  class: "longhorn"
  replicas: 3
  backup_enabled: true

# Network configuration
network:
  ingress:
    class: "nginx"
    annotations:
      nginx.ingress.kubernetes.io/proxy-body-size: "100m"
      nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
  
# Backup configuration
backup:
  velero:
    enabled: true
    schedule: "0 2 * * *"
    retention: "720h"
    storage:
      provider: "aws"
      bucket: "company-lair-backups"
      region: "us-west-2"
```

### 🎛️ **Environment-Specific Configurations**

#### **Development Environment**
```yaml
# values-development.yaml
config_name: "development"
platform:
  access_mode: "lan"
  
resources:
  cpu_cores: 4
  memory_gb: 16
  storage_gb: 100

components:
  openwebui:
    storage_size: "10Gi"
  ollama:
    storage_size: "50Gi"
    models:
      - "llama3.1:8b"  # Smaller model for dev
  n8n:
    workers: 1
    storage_size: "10Gi"
  comfyui:
    enabled: false  # Disabled in dev
  minio:
    storage_size: "20Gi"

backup:
  velero:
    enabled: false  # No backup in dev
```

#### **Production Environment**
```yaml
# values-production.yaml
config_name: "production"
platform:
  access_mode: "dual"
  
resources:
  cpu_cores: 32
  memory_gb: 128
  storage_gb: 2000

components:
  openwebui:
    storage_size: "100Gi"
    sso:
      enabled: true
      provider: "oidc"
  ollama:
    storage_size: "500Gi"
    models:
      - "llama3.1:70b"
      - "codellama:34b"
      - "mistral:7b"
  n8n:
    workers: 8
    storage_size: "100Gi"
    smtp:
      enabled: true
  comfyui:
    enabled: true
    storage_size: "200Gi"
  minio:
    storage_size: "1000Gi"

storage:
  replicas: 3
  backup_enabled: true

backup:
  velero:
    enabled: true
    schedule: "0 1 * * *"  # Daily at 1 AM
    retention: "2160h"     # 90 days
```

---

## 🌐 Multi-Environment Setup

### 🏢 **Enterprise Multi-Environment Architecture**

#### **Environment Separation Strategy**
```bash
# Directory structure for multi-environment
lair-deployments/
├── environments/
│   ├── development/
│   │   ├── values-dev.yaml
│   │   ├── secrets-dev.yaml
│   │   └── deploy-dev.sh
│   ├── staging/
│   │   ├── values-staging.yaml
│   │   ├── secrets-staging.yaml
│   │   └── deploy-staging.sh
│   └── production/
│       ├── values-prod.yaml
│       ├── secrets-prod.yaml
│       └── deploy-prod.sh
├── shared/
│   ├── base-values.yaml
│   └── common-secrets.yaml
└── scripts/
    ├── deploy-all.sh
    └── promote-environment.sh
```

#### **Environment Deployment Script**
```bash
#!/bin/bash
# deploy-environment.sh - Multi-environment deployment script

ENVIRONMENT=${1:-development}
NAMESPACE="lair-${ENVIRONMENT}"

echo "Deploying Lair to environment: $ENVIRONMENT"

# Validate environment
case $ENVIRONMENT in
  development|staging|production)
    echo "✅ Valid environment: $ENVIRONMENT"
    ;;
  *)
    echo "❌ Invalid environment. Use: development, staging, or production"
    exit 1
    ;;
esac

# Set environment-specific variables
VALUES_FILE="environments/${ENVIRONMENT}/values-${ENVIRONMENT}.yaml"
SECRETS_FILE="environments/${ENVIRONMENT}/secrets-${ENVIRONMENT}.yaml"

# Validate files exist
if [ ! -f "$VALUES_FILE" ]; then
  echo "❌ Values file not found: $VALUES_FILE"
  exit 1
fi

# Create namespace if it doesn't exist
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Apply secrets if they exist
if [ -f "$SECRETS_FILE" ]; then
  echo "📋 Applying secrets for $ENVIRONMENT"
  kubectl apply -f "$SECRETS_FILE" -n "$NAMESPACE"
fi

# Deploy with Helm
echo "🚀 Deploying Lair to $ENVIRONMENT environment"
helm upgrade --install "lair-${ENVIRONMENT}" . \
  -n "$NAMESPACE" \
  -f shared/base-values.yaml \
  -f "$VALUES_FILE" \
  --wait

echo "✅ Deployment to $ENVIRONMENT completed"
```

### 🔄 **Environment Promotion Pipeline**

#### **GitOps-Style Promotion**
```bash
#!/bin/bash
# promote-environment.sh - Promote configuration between environments

SOURCE_ENV=${1:-development}
TARGET_ENV=${2:-staging}

echo "Promoting configuration from $SOURCE_ENV to $TARGET_ENV"

# Validate environments
for env in $SOURCE_ENV $TARGET_ENV; do
  case $env in
    development|staging|production) ;;
    *)
      echo "❌ Invalid environment: $env"
      exit 1
      ;;
  esac
done

# Prevent dangerous promotions
if [ "$SOURCE_ENV" = "production" ]; then
  echo "❌ Cannot promote from production environment"
  exit 1
fi

if [ "$TARGET_ENV" = "production" ] && [ "$SOURCE_ENV" != "staging" ]; then
  echo "❌ Can only promote to production from staging"
  exit 1
fi

# Copy and modify configuration
SOURCE_FILE="environments/${SOURCE_ENV}/values-${SOURCE_ENV}.yaml"
TARGET_FILE="environments/${TARGET_ENV}/values-${TARGET_ENV}.yaml"

# Create backup
cp "$TARGET_FILE" "${TARGET_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Promote configuration (with environment-specific modifications)
cp "$SOURCE_FILE" "$TARGET_FILE"

# Update environment-specific values
sed -i "s/config_name: \".*\"/config_name: \"${TARGET_ENV}\"/" "$TARGET_FILE"

# Update resource allocations for target environment
case $TARGET_ENV in
  staging)
    sed -i 's/cpu_cores: 4/cpu_cores: 8/' "$TARGET_FILE"
    sed -i 's/memory_gb: 16/memory_gb: 32/' "$TARGET_FILE"
    ;;
  production)
    sed -i 's/cpu_cores: 8/cpu_cores: 32/' "$TARGET_FILE"
    sed -i 's/memory_gb: 32/memory_gb: 128/' "$TARGET_FILE"
    ;;
esac

echo "✅ Configuration promoted from $SOURCE_ENV to $TARGET_ENV"
echo "📝 Review changes in: $TARGET_FILE"
```

---

## 🔌 Integration Patterns

### 🏢 **Enterprise SSO Integration**

#### **OIDC/OAuth2 Integration**
```yaml
# Advanced SSO configuration
openWebUI:
  sso:
    enabled: true
    provider: "oidc"
    enableLoginForm: false  # Force SSO-only login
    enableLocalSignup: false
    oauth:
      enableSignup: true
      mergeAccountsByEmail: true
      updatePictureOnLogin: true
      clientId: "lair-openwebui"
      clientSecret: "your-oidc-secret"
      providerName: "Company SSO"
      scopes: "openid email profile groups"
      providerUrl: "https://auth.company.com"
      redirectUri: "https://ai.company.com/oauth/oidc/callback"
      # Additional OIDC configuration
      extraParams:
        prompt: "select_account"
        access_type: "offline"
```

#### **Multiple SSO Providers**
```yaml
# Multi-provider SSO setup (requires custom configuration)
openWebUI:
  sso:
    enabled: true
    provider: "multiple"  # Custom multi-provider setup
    providers:
      google:
        enabled: true
        clientId: "google-client-id"
        clientSecret: "google-client-secret"
      microsoft:
        enabled: true
        clientId: "azure-client-id"
        clientSecret: "azure-client-secret"
        tenantId: "azure-tenant-id"
      github:
        enabled: true
        clientId: "github-client-id"
        clientSecret: "github-client-secret"
```

### 🔗 **API Integration Patterns**

#### **External Service Integration**
```yaml
# N8N with external service integrations
n8n:
  extraEnv:
    # External database connection
    - name: DB_POSTGRESDB_HOST
      value: "external-postgres.company.com"
    - name: DB_POSTGRESDB_PORT
      value: "5432"
    - name: DB_POSTGRESDB_DATABASE
      value: "n8n_production"
    - name: DB_POSTGRESDB_USER
      valueFrom:
        secretKeyRef:
          name: external-db-credentials
          key: username
    - name: DB_POSTGRESDB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: external-db-credentials
          key: password
    
    # External Redis for queue
    - name: QUEUE_BULL_REDIS_HOST
      value: "redis.company.com"
    - name: QUEUE_BULL_REDIS_PORT
      value: "6379"
    - name: QUEUE_BULL_REDIS_PASSWORD
      valueFrom:
        secretKeyRef:
          name: external-redis-credentials
          key: password
    
    # External S3 storage
    - name: N8N_FILESYSTEM_ALIAS_S3_ENDPOINT
      value: "s3.amazonaws.com"
    - name: N8N_FILESYSTEM_ALIAS_S3_BUCKET
      value: "company-n8n-storage"
    - name: N8N_FILESYSTEM_ALIAS_S3_ACCESS_KEY_ID
      valueFrom:
        secretKeyRef:
          name: aws-s3-credentials
          key: access-key-id
    - name: N8N_FILESYSTEM_ALIAS_S3_SECRET_ACCESS_KEY
      valueFrom:
        secretKeyRef:
          name: aws-s3-credentials
          key: secret-access-key
```

#### **Custom API Endpoints**
```yaml
# Custom service endpoints configuration
services:
  custom:
    # External Ollama service
    ollama:
      external: true
      endpoint: "https://ollama.company.com"
      apiKey: "your-api-key"
    
    # External vector database
    vectordb:
      type: "pinecone"
      endpoint: "https://your-index.pinecone.io"
      apiKey: "your-pinecone-key"
    
    # External monitoring
    monitoring:
      prometheus: "https://prometheus.company.com"
      grafana: "https://grafana.company.com"
```

### 🌐 **Network Integration**

#### **Advanced Ingress Configuration**
```yaml
# Advanced ingress with custom annotations
ingress:
  enabled: true
  className: "nginx"
  annotations:
    # Rate limiting
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
    
    # Security headers
    nginx.ingress.kubernetes.io/configuration-snippet: |
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-XSS-Protection "1; mode=block" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Custom authentication
    nginx.ingress.kubernetes.io/auth-url: "https://auth.company.com/verify"
    nginx.ingress.kubernetes.io/auth-signin: "https://auth.company.com/login"
    
    # IP whitelisting
    nginx.ingress.kubernetes.io/whitelist-source-range: "10.0.0.0/8,192.168.0.0/16"
    
    # Custom timeouts
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    
    # Large file uploads
    nginx.ingress.kubernetes.io/proxy-body-size: "1000m"
    nginx.ingress.kubernetes.io/client-max-body-size: "1000m"
  
  # Multiple hosts configuration
  hosts:
    - host: ai.company.com
      paths:
        - path: /
          pathType: Prefix
          service: openwebui
    - host: n8n.company.com
      paths:
        - path: /
          pathType: Prefix
          service: n8n
    - host: images.company.com
      paths:
        - path: /
          pathType: Prefix
          service: comfyui
    - host: storage.company.com
      paths:
        - path: /
          pathType: Prefix
          service: minio
  
  # TLS configuration
  tls:
    - secretName: company-tls-cert
      hosts:
        - ai.company.com
        - n8n.company.com
        - images.company.com
        - storage.company.com
```

---

## 🎛️ Custom Component Configuration

### 🔧 **Advanced OpenWebUI Configuration**

#### **Custom RAG Configuration**
```yaml
openWebUI:
  rag:
    # Advanced content extraction
    contentExtractionEngine: "tika"
    enableHybridSearch: true
    textSplitter: "semantic"  # semantic, token, character
    chunkSize: 2000
    chunkOverlap: 400
    topK: 10
    
    # Advanced PDF processing
    pdfExtractImages: true
    pdfImageOcr: true
    pdfImageOcrLanguage: "eng+fra+deu"
    
    # Vector database configuration
    vectorDb:
      type: "chroma"  # chroma, pinecone, weaviate
      config:
        collection_name: "lair_documents"
        embedding_model: "sentence-transformers/all-MiniLM-L6-v2"
    
    # Search configuration
    search:
      algorithm: "hybrid"  # dense, sparse, hybrid
      denseWeight: 0.7
      sparseWeight: 0.3
      rerankModel: "cross-encoder/ms-marco-MiniLM-L-6-v2"
  
  # Custom plugins configuration
  plugins:
    - name: "custom-auth-plugin"
      enabled: true
      config:
        provider: "ldap"
        server: "ldap.company.com"
        port: 389
    - name: "custom-analytics-plugin"
      enabled: true
      config:
        endpoint: "https://analytics.company.com/api"
        apiKey: "your-analytics-key"
  
  # Advanced audio configuration
  audio:
    whisperModel: "large-v3"
    whisperLanguage: "auto"
    enableSpeechToText: true
    enableTextToSpeech: true
    ttsEngine: "elevenlabs"
    ttsApiKey: "your-elevenlabs-key"
```

### 🤖 **Advanced Ollama Configuration**

#### **Custom Model Management**
```yaml
ollama:
  # Custom image with pre-installed models
  image:
    repository: "company/ollama-custom"
    tag: "v1.0.0"
  
  # Model preloading configuration
  models:
    preload:
      - name: "llama3.1:8b"
        alias: "general"
        temperature: 0.7
        context_length: 4096
      - name: "codellama:13b"
        alias: "coding"
        temperature: 0.1
        context_length: 8192
      - name: "mistral:7b"
        alias: "creative"
        temperature: 0.9
        context_length: 4096
  
  # Custom model configurations
  modelConfigs:
    "llama3.1:8b":
      num_ctx: 4096
      num_predict: 2048
      temperature: 0.7
      top_k: 40
      top_p: 0.9
      repeat_penalty: 1.1
    "codellama:13b":
      num_ctx: 8192
      num_predict: 4096
      temperature: 0.1
      top_k: 10
      top_p: 0.95
  
  # Performance tuning
  performance:
    num_parallel: 4
    num_gpu_layers: 35
    gpu_memory_fraction: 0.8
    flash_attention: true
  
  # Custom environment variables
  extraEnv:
    - name: OLLAMA_DEBUG
      value: "1"
    - name: OLLAMA_MAX_LOADED_MODELS
      value: "3"
    - name: OLLAMA_NUM_PARALLEL
      value: "4"
    - name: OLLAMA_FLASH_ATTENTION
      value: "1"
```

### 🔄 **Advanced N8N Configuration**

#### **Enterprise N8N Setup**
```yaml
n8n:
  # Custom image with pre-installed nodes
  image:
    repository: "company/n8n-enterprise"
    tag: "v1.0.0"
  
  # Advanced worker configuration
  worker:
    enabled: true
    replicas: 8
    resources:
      limits:
        memory: 4Gi
        cpu: 2000m
      requests:
        memory: 2Gi
        cpu: 1000m
    
    # Worker-specific environment
    extraEnv:
      - name: N8N_WORKER_TYPE
        value: "main"
      - name: EXECUTIONS_PROCESS
        value: "own"
      - name: N8N_METRICS
        value: "true"
  
  # Advanced database configuration
  database:
    type: "postgresdb"
    external: true
    host: "postgres.company.com"
    port: 5432
    database: "n8n_production"
    ssl: true
    sslMode: "require"
  
  # Advanced queue configuration
  queue:
    type: "redis"
    external: true
    host: "redis.company.com"
    port: 6379
    db: 0
    ssl: true
    cluster: true
    
    # Queue settings
    settings:
      maxJobs: 1000
      maxStalledCount: 3
      maxmemoryPolicy: "allkeys-lru"
  
  # Custom nodes and credentials
  customNodes:
    - "@n8n/n8n-nodes-langchain"
    - "n8n-nodes-ollama"
    - "company-custom-nodes"
  
  # Advanced security configuration
  security:
    encryptionKey:
      secretName: "n8n-encryption-key"
      secretKey: "key"
    jwtSecret:
      secretName: "n8n-jwt-secret"
      secretKey: "secret"
    
    # User management
    userManagement:
      enabled: true
      jwtSessionDuration: 168  # 7 days
      jwtRefreshTimeout: 168   # 7 days
    
    # API security
    api:
      rateLimit: true
      rateLimitMax: 100
      rateLimitWindow: 60
  
  # Monitoring and observability
  monitoring:
    metrics:
      enabled: true
      port: 9090
      path: "/metrics"
    
    logging:
      level: "info"
      format: "json"
      outputs:
        - "console"
        - "file"
      
    tracing:
      enabled: true
      jaegerEndpoint: "http://jaeger.company.com:14268/api/traces"
```

---

## 🔒 Security Hardening

### 🛡️ **Advanced Security Configuration**

#### **Network Security**
```yaml
# Network policies for micro-segmentation
networkPolicies:
  enabled: true
  policies:
    # Deny all by default
    - name: "default-deny-all"
      podSelector: {}
      policyTypes:
        - Ingress
        - Egress
    
    # Allow OpenWebUI to Ollama
    - name: "openwebui-to-ollama"
      podSelector:
        matchLabels:
          app: openwebui
      egress:
        - to:
          - podSelector:
              matchLabels:
                app: ollama
          ports:
            - protocol: TCP
              port: 11434
    
    # Allow N8N to external services
    - name: "n8n-external-access"
      podSelector:
        matchLabels:
          app: n8n
      egress:
        - to: []  # Allow all external
          ports:
            - protocol: TCP
              port: 443
            - protocol: TCP
              port: 80

# Pod security standards
podSecurityStandards:
  enforceLevel: "restricted"
  auditLevel: "restricted"
  warnLevel: "restricted"

# Security contexts
securityContexts:
  openwebui:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
    capabilities:
      drop:
        - ALL
  
  ollama:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    # GPU access requires privileged mode
    privileged: false
    allowPrivilegeEscalation: false
```

#### **Secrets Management**
```yaml
# External secrets integration
externalSecrets:
  enabled: true
  provider: "vault"  # vault, aws-secrets-manager, azure-keyvault
  
  vault:
    server: "https://vault.company.com"
    path: "secret/lair"
    auth:
      method: "kubernetes"
      role: "lair-role"
  
  secrets:
    - name: "openwebui-sso-credentials"
      keys:
        - key: "client-id"
          property: "openwebui.sso.oauth.clientId"
        - key: "client-secret"
          property: "openwebui.sso.oauth.clientSecret"
    
    - name: "n8n-encryption-key"
      keys:
        - key: "encryption-key"
          property: "n8n.encryptionKey"
    
    - name: "database-credentials"
      keys:
        - key: "username"
          property: "n8n.postgres.user"
        - key: "password"
          property: "n8n.postgres.password"

# Certificate management
certificates:
  provider: "cert-manager"
  issuer: "letsencrypt-prod"
  
  # Custom CA for internal services
  customCA:
    enabled: true
    secretName: "company-ca-cert"
    
  # Certificate rotation
  rotation:
    enabled: true
    renewBefore: "720h"  # 30 days
```

---

## 📊 Monitoring & Observability

### 🔍 **Advanced Monitoring Configuration**

#### **Prometheus Integration**
```yaml
# Prometheus monitoring configuration
monitoring:
  prometheus:
    enabled: true
    namespace: "monitoring"
    
    # Service monitors
    serviceMonitors:
      openwebui:
        enabled: true
        path: "/metrics"
        port: "metrics"
        interval: "30s"
      
      ollama:
        enabled: true
        path: "/metrics"
        port: "metrics"
        interval: "30s"
      
      n8n:
        enabled: true
        path: "/metrics"
        port: "metrics"
        interval: "30s"
    
    # Custom metrics
    customMetrics:
      - name: "lair_active_users"
        help: "Number of active users"
        type: "gauge"
        labels: ["service", "environment"]
      
      - name: "lair_request_duration"
        help: "Request duration in seconds"
        type: "histogram"
        labels: ["service", "method", "status"]
  
  # Grafana dashboards
  grafana:
    enabled: true
    dashboards:
      - name: "lair-overview"
        configMap: "lair-grafana-dashboard"
      - name: "lair-performance"
        configMap: "lair-performance-dashboard"
  
  # Alerting rules
  alerting:
    rules:
      - name: "lair-high-cpu"
        expr: "rate(container_cpu_usage_seconds_total[5m]) > 0.8"
        for: "5m"
        labels:
          severity: "warning"
        annotations:
          summary: "High CPU usage detected"
      
      - name: "lair-pod-down"
        expr: "up{job=~'lair-.*'} == 0"
        for: "1m"
        labels:
          severity: "critical"
        annotations:
          summary: "Lair pod is down"
```

#### **Distributed Tracing**
```yaml
# Jaeger tracing configuration
tracing:
  jaeger:
    enabled: true
    endpoint: "http://jaeger-collector.monitoring:14268/api/traces"
    
    # Sampling configuration
    sampling:
      type: "probabilistic"
      param: 0.1  # 10% sampling
    
    # Service configuration
    services:
      openwebui:
        enabled: true
        serviceName: "openwebui"
      n8n:
        enabled: true
        serviceName: "n8n"
      ollama:
        enabled: true
        serviceName: "ollama"
```

---

## 🎯 Best Practices

### 🚀 **Configuration Best Practices**
- **Version Control**: Store all configuration files in version control
- **Environment Separation**: Use separate configurations for each environment
- **Secret Management**: Never store secrets in configuration files
- **Validation**: Validate configurations before deployment
- **Documentation**: Document all custom configurations

### 🔒 **Security Best Practices**
- **Least Privilege**: Apply principle of least privilege
- **Network Segmentation**: Use network policies for micro-segmentation
- **Secret Rotation**: Implement regular secret rotation
- **Security Scanning**: Regularly scan for vulnerabilities
- **Audit Logging**: Enable comprehensive audit logging

### 📊 **Operational Best Practices**
- **Monitoring**: Implement comprehensive monitoring
- **Alerting**: Set up meaningful alerts
- **Backup**: Regular backup of configurations and data
- **Testing**: Test configurations in non-production environments
- **Automation**: Automate deployment and configuration management

---

**🎯 Ready to implement advanced configurations?** Continue with [Multi-Environment Setup](multi-environment.md) or explore [Custom Configurations](custom-configs.md)!
