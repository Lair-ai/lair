#!/bin/bash

# ============================================================================
# YAML-GENERATION.SH - YAML Configuration Generation Functions
# ============================================================================

# Helper function to generate the complete YAML configuration
lair_base64_encode_value() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

lair_base64_decode_value() {
  local value=$1
  printf '%s' "$value" | base64 --decode 2>/dev/null || printf '%s' "$value" | base64 -D 2>/dev/null
}

lair_url_encode_postgres_password() {
  local value=$1
  value=${value//%/%25}
  value=${value//+/%2B}
  value=${value//\//%2F}
  value=${value//=/%3D}
  printf '%s' "$value"
}

ensure_n8n_postgres_secret() {
  local namespace=${1:-$NAMESPACE}
  local release_name=${2:-${RELEASE_NAME:-lair}}
  local secret_name="n8n-postgres-secret"
  local existing_password_b64=""
  local PG_PASSWORD=""
  local PG_PASSWORD_URL=""
  local PG_PASSWORD_B64=""
  local PG_PASSWORD_URL_B64=""

  if [ -z "$KUBECTL_CMD" ]; then
    echo -e "${RED}❌ kubectl command not configured; cannot create PostgreSQL Secret${NC}"
    return 1
  fi

  if [ -z "$namespace" ]; then
    echo -e "${RED}❌ Namespace not configured; cannot create PostgreSQL Secret${NC}"
    return 1
  fi

  if ! $KUBECTL_CMD get namespace "$namespace" &>/dev/null; then
    echo -e "${RED}❌ Namespace '$namespace' does not exist; cannot create PostgreSQL Secret${NC}"
    return 1
  fi

  existing_password_b64=$($KUBECTL_CMD get secret "$secret_name" -n "$namespace" -o jsonpath="{.data['postgres-password']}" 2>/dev/null || true)
  if [ -n "$existing_password_b64" ]; then
    PG_PASSWORD=$(lair_base64_decode_value "$existing_password_b64")
    if [ -z "$PG_PASSWORD" ]; then
      echo -e "${RED}❌ Unable to decode existing PostgreSQL Secret password${NC}"
      return 1
    fi
    echo -e "${GREEN}🔐 Existing PostgreSQL Secret found; preserving password${NC}"
  else
    if ! command -v openssl >/dev/null 2>&1; then
      echo -e "${RED}❌ openssl is required to generate the PostgreSQL password${NC}"
      return 1
    fi

    PG_PASSWORD=$(openssl rand -base64 24)
    if [ -z "$PG_PASSWORD" ]; then
      echo -e "${RED}❌ Failed to generate PostgreSQL password${NC}"
      return 1
    fi
    echo -e "${GREEN}🔐 Creating PostgreSQL Secret with generated password${NC}"
  fi

  PG_PASSWORD_URL=$(lair_url_encode_postgres_password "$PG_PASSWORD")
  PG_PASSWORD_B64=$(lair_base64_encode_value "$PG_PASSWORD")
  PG_PASSWORD_URL_B64=$(lair_base64_encode_value "$PG_PASSWORD_URL")

  if $KUBECTL_CMD get secret "$secret_name" -n "$namespace" &>/dev/null; then
    if ! $KUBECTL_CMD patch secret "$secret_name" -n "$namespace" --type merge -p "{\"data\":{\"postgres-password\":\"$PG_PASSWORD_B64\",\"postgres-password-url\":\"$PG_PASSWORD_URL_B64\"}}" >/dev/null; then
      echo -e "${RED}❌ Failed to update PostgreSQL Secret${NC}"
      return 1
    fi
  else
    if ! $KUBECTL_CMD create secret generic "$secret_name" -n "$namespace" \
      --from-literal=postgres-password="$PG_PASSWORD" \
      --from-literal=postgres-password-url="$PG_PASSWORD_URL" >/dev/null; then
      echo -e "${RED}❌ Failed to create PostgreSQL Secret${NC}"
      return 1
    fi
  fi

  if ! $KUBECTL_CMD label secret "$secret_name" -n "$namespace" \
    "app.kubernetes.io/managed-by=Helm" --overwrite >/dev/null; then
    echo -e "${RED}❌ Failed to label PostgreSQL Secret for Helm ownership${NC}"
    return 1
  fi

  if ! $KUBECTL_CMD annotate secret "$secret_name" -n "$namespace" \
    "meta.helm.sh/release-name=$release_name" \
    "meta.helm.sh/release-namespace=$namespace" \
    "helm.sh/resource-policy=keep" --overwrite >/dev/null; then
    echo -e "${RED}❌ Failed to annotate PostgreSQL Secret for Helm ownership${NC}"
    return 1
  fi

  echo -e "${GREEN}✅ PostgreSQL Secret ready: $secret_name${NC}"
}

generate_complete_yaml_configuration() {
  # Get cert-manager configuration based on access mode
  if [ "$ACCESS_MODE" = "lan" ]; then
    LETSENCRYPT_COMMENT="# Let's Encrypt disabled for LAN mode (.local domains)"
    CREATE_CLUSTER_ISSUER="false"
  else
    LETSENCRYPT_COMMENT="# Let's Encrypt enabled for public mode"
    CREATE_CLUSTER_ISSUER="true"
  fi
  
  cat <<-EOF >> $CONFIG_FILE
$LETSENCRYPT_COMMENT
certManager:
  email: $CERT_EMAIL
  createClusterIssuer: $CREATE_CLUSTER_ISSUER
  clusterIssuer: lair-letsencrypt
  
ingress:
  className: public
EOF

  # Generate LAN ingress configuration
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    cat <<-EOF >> $CONFIG_FILE
  lan:
    enabled: true
    enableTLS: $([ "$ENABLE_LAN_TLS" = "true" ] && echo "true" || echo "false")
    tlsSecretName: lair-tls-local
    hosts:
      - host: $OPENWEBUI_DOMAIN_LAN
        serviceName: openwebui
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
      - host: $N8N_DOMAIN_LAN
        serviceName: n8n
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
EOF

    # Add ComfyUI LAN ingress only if domain is specified
    if [ -n "$COMFYUI_DOMAIN_LAN" ] && [ "$COMFYUI_DOMAIN_LAN" != "" ]; then
      cat <<-EOF >> $CONFIG_FILE
      - host: $COMFYUI_DOMAIN_LAN
        serviceName: comfyui
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
EOF
    fi

    # Add MinIO LAN ingress only if domain is specified
    if [ -n "$MINIO_DOMAIN_LAN" ] && [ "$MINIO_DOMAIN_LAN" != "" ]; then
      cat <<-EOF >> $CONFIG_FILE
      - host: $MINIO_DOMAIN_LAN
        serviceName: minio
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
EOF
    fi

    # Add Ollama LAN ingress only if domain is specified
    if [ -n "$OLLAMA_DOMAIN_LAN" ] && [ "$OLLAMA_DOMAIN_LAN" != "" ]; then
      cat <<-EOF >> $CONFIG_FILE
      - host: $OLLAMA_DOMAIN_LAN
        serviceName: ollama
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
EOF
    fi
  else
    cat <<-EOF >> $CONFIG_FILE
  lan:
    enabled: false
EOF
  fi

  # Generate Public ingress configuration
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    cat <<-EOF >> $CONFIG_FILE
  public:
    enabled: true
    hosts:
      - host: $OPENWEBUI_DOMAIN_PUBLIC
        serviceName: openwebui
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
      - host: $N8N_DOMAIN_PUBLIC
        serviceName: n8n
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
EOF

    # Add ComfyUI public ingress only if domain is specified
    if [ -n "$COMFYUI_DOMAIN_PUBLIC" ] && [ "$COMFYUI_DOMAIN_PUBLIC" != "" ]; then
      cat <<-EOF >> $CONFIG_FILE
      - host: $COMFYUI_DOMAIN_PUBLIC
        serviceName: comfyui
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
EOF
    fi

    # Add MinIO public ingress only if domain is specified
    if [ -n "$MINIO_DOMAIN_PUBLIC" ] && [ "$MINIO_DOMAIN_PUBLIC" != "" ]; then
      cat <<-EOF >> $CONFIG_FILE
      - host: $MINIO_DOMAIN_PUBLIC
        serviceName: minio
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
EOF
    fi

    # Add Ollama public ingress only if domain is specified
    if [ -n "$OLLAMA_DOMAIN_PUBLIC" ] && [ "$OLLAMA_DOMAIN_PUBLIC" != "" ]; then
      cat <<-EOF >> $CONFIG_FILE
      - host: $OLLAMA_DOMAIN_PUBLIC
        serviceName: ollama
        servicePort: 80
        paths:
          - path: /
            pathType: Prefix
EOF
    fi
  else
    cat <<-EOF >> $CONFIG_FILE
  public:
    enabled: false
EOF
  fi

  # Legacy hosts configuration for backward compatibility
  cat <<-EOF >> $CONFIG_FILE
  hosts:
    - host: $OPENWEBUI_DOMAIN
      serviceName: openwebui
      servicePort: 80
      paths:
        - path: /
          pathType: Prefix
    - host: $N8N_DOMAIN
      serviceName: n8n
      servicePort: 80
      paths:
        - path: /
          pathType: Prefix
EOF

  # Add legacy ComfyUI ingress only if domain is specified
  if [ -n "$COMFYUI_DOMAIN" ] && [ "$COMFYUI_DOMAIN" != "" ]; then
    cat <<-EOF >> $CONFIG_FILE
    - host: $COMFYUI_DOMAIN
      serviceName: comfyui
      servicePort: 80
      paths:
        - path: /
          pathType: Prefix
EOF
  fi

  # Add legacy MinIO ingress only if domain is specified
  if [ -n "$MINIO_DOMAIN" ] && [ "$MINIO_DOMAIN" != "" ]; then
    cat <<-EOF >> $CONFIG_FILE
    - host: $MINIO_DOMAIN
      serviceName: minio
      servicePort: 80
      paths:
        - path: /
          pathType: Prefix
EOF
  fi

  # Add legacy Ollama ingress only if domain is specified
  if [ -n "$OLLAMA_DOMAIN" ] && [ "$OLLAMA_DOMAIN" != "" ]; then
    cat <<-EOF >> $CONFIG_FILE
    - host: $OLLAMA_DOMAIN
      serviceName: ollama
      servicePort: 80
      paths:
        - path: /
          pathType: Prefix
EOF
  fi

  cat <<-EOF >> $CONFIG_FILE

openWebUI:
  persistence:
    enabled: true
    size: $OPENWEBUI_STORAGE_SIZE
    enablePersistentConfig: true
  # RAG Configuration
  rag:
    contentExtractionEngine: "tika"
    enableHybridSearch: true
    textSplitter: "token"
    chunkSize: 1000
    chunkOverlap: 200
    topK: 5
    pdfExtractImages: true
  # Audio Configuration
  audio:
    whisperModel: "turbo"
    vadFilter: true
    autoUpdate: false
    sttEngine: "whisper"
    ttsEngine: "openai"
  # Authentication and User Management
  auth:
    enableSignup: true
    defaultUserRole: "pending"
    userPermissions:
      chatDeletion: true
  # Feature Configuration
  features:
    enableCommunitySharing: true
    enableMessageRating: true
  resources:
    limits:
      memory: ${MEM_OPENWEBUI}Mi
      cpu: ${CPU_OPENWEBUI}m
    requests:
      memory: ${MEM_OPENWEBUI_REQ}Mi
      cpu: ${CPU_OPENWEBUI_REQ}m
EOF

  # Add OpenWebUI SSO configuration if enabled
  if [[ "$ENABLE_OPENWEBUI_SSO" == "y" || "$ENABLE_OPENWEBUI_SSO" == "Y" ]]; then
    cat <<-EOF >> $CONFIG_FILE
  sso:
    enabled: true
    provider: "$OPENWEBUI_SSO_PROVIDER"
    enableLoginForm: false
    enableLocalSignup: false
    oauth:
      enableSignup: $([ "$ENABLE_OPENWEBUI_OAUTH_SIGNUP" = "y" ] && echo "true" || echo "false")
      mergeAccountsByEmail: $([ "$ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS" = "y" ] && echo "true" || echo "false")
      updatePictureOnLogin: $([ "$ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE" = "y" ] && echo "true" || echo "false")
EOF

    case "$OPENWEBUI_SSO_PROVIDER" in
      "google")
        cat <<-EOF >> $CONFIG_FILE
    google:
      clientId: "$OPENWEBUI_GOOGLE_CLIENT_ID"
      clientSecret: "$OPENWEBUI_GOOGLE_CLIENT_SECRET"
      redirectUri: "$OPENWEBUI_GOOGLE_REDIRECT_URI"
EOF
        ;;
      "microsoft")
        cat <<-EOF >> $CONFIG_FILE
    microsoft:
      clientId: "$OPENWEBUI_MICROSOFT_CLIENT_ID"
      clientSecret: "$OPENWEBUI_MICROSOFT_CLIENT_SECRET"
      tenantId: "$OPENWEBUI_MICROSOFT_CLIENT_TENANT_ID"
      redirectUri: "$OPENWEBUI_MICROSOFT_REDIRECT_URI"
EOF
        ;;
      "github")
        cat <<-EOF >> $CONFIG_FILE
    github:
      clientId: "$OPENWEBUI_GITHUB_CLIENT_ID"
      clientSecret: "$OPENWEBUI_GITHUB_CLIENT_SECRET"
EOF
        ;;
      "oidc")
        cat <<-EOF >> $CONFIG_FILE
    oauth:
      clientId: "$OPENWEBUI_OAUTH_CLIENT_ID"
      clientSecret: "$OPENWEBUI_OAUTH_CLIENT_SECRET"
      providerName: "$OPENWEBUI_OAUTH_PROVIDER_NAME"
      scopes: "$OPENWEBUI_OAUTH_SCOPES"
      providerUrl: "$OPENWEBUI_OPENID_PROVIDER_URL"
      redirectUri: "$OPENWEBUI_OPENID_REDIRECT_URI"
EOF
        ;;
      "trusted-header")
        cat <<-EOF >> $CONFIG_FILE
    trustedHeader:
      emailHeader: "$OPENWEBUI_TRUSTED_EMAIL_HEADER"
EOF
        if [[ -n "$OPENWEBUI_TRUSTED_NAME_HEADER" ]]; then
          cat <<-EOF >> $CONFIG_FILE
      nameHeader: "$OPENWEBUI_TRUSTED_NAME_HEADER"
EOF
        fi
        ;;
    esac
  fi

  cat <<-EOF >> $CONFIG_FILE

ollama:
  gpuEnabled: $OLLAMA_GPU_ENABLED
  vramPercentage: $VRAM_PERCENTAGE
  persistence:
    size: $OLLAMA_STORAGE_SIZE
  resources:
    limits:
      memory: ${MEM_OLLAMA}Mi
      cpu: ${CPU_OLLAMA}m
    requests:
      memory: ${MEM_OLLAMA_REQ}Mi
      cpu: ${CPU_OLLAMA_REQ}m
EOF

  # Add Jetson-specific Ollama image configuration if specified or auto-detected
  # Safety check: ensure IS_JETSON is defined
  IS_JETSON=${IS_JETSON:-"n"}
  
  if [ "$IS_JETSON" = "y" ] && [ -n "$OLLAMA_IMAGE" ]; then
    cat <<-EOF >> $CONFIG_FILE
  image:
    repository: $(echo "$OLLAMA_IMAGE" | cut -d':' -f1)
    tag: $(echo "$OLLAMA_IMAGE" | cut -d':' -f2)
EOF
  elif [ "$IS_JETSON" = "y" ]; then
    # Auto-set Jetson image if platform is Jetson but no image specified
    # OLLAMA_IMAGE="dustynv/ollama:r36.3.0"
    OLLAMA_IMAGE="ollama/ollama:latest"
    cat <<-EOF >> $CONFIG_FILE
  image:
    repository: $(echo "$OLLAMA_IMAGE" | cut -d':' -f1)
    tag: $(echo "$OLLAMA_IMAGE" | cut -d':' -f2)
EOF
  fi

  cat <<-EOF >> $CONFIG_FILE
EOF



  # N8N and PostgreSQL configuration
  # N8N_WORKER_REPLICAS is already calculated in helpers.sh based on available memory and nodes
  if [ "$N8N_WORKER_REPLICAS" -eq 1 ]; then
    if [ "$K8S_MEMORY_MB" -lt 8192 ]; then
      echo -e "${YELLOW}⚠️  Available RAM below 8GB ($(echo "scale=1; $K8S_MEMORY_MB/1024" | bc)GB): setting 1 N8N worker to optimize resources${NC}"
    else
      echo -e "${YELLOW}⚠️  Single node detected: setting 1 N8N worker (RAM: $(echo "scale=1; $K8S_MEMORY_MB/1024" | bc)GB)${NC}"
    fi
  else
    if [ -z "$NODES_COUNT" ] || [ "$NODES_COUNT" -eq 0 ]; then
      echo -e "${GREEN}✅ Sufficient RAM ($(echo "scale=1; $K8S_MEMORY_MB/1024" | bc)GB): configuring $N8N_WORKER_REPLICAS N8N workers for optimal performance${NC}"
    else
      echo -e "${GREEN}✅ Sufficient RAM ($(echo "scale=1; $K8S_MEMORY_MB/1024" | bc)GB) and $NODES_COUNT nodes: configuring $N8N_WORKER_REPLICAS N8N workers for optimal performance${NC}"
    fi
  fi
  
    cat <<-EOF >> $CONFIG_FILE

n8n:
  encryptionKey: "$N8N_KEY"
  database:
    type: postgresdb
  worker:
    enabled: true
    replicas: $N8N_WORKER_REPLICAS
    resources:
      limits:
        memory: ${MEM_N8N_WORKER}Mi
        cpu: ${CPU_N8N_WORKER}m
      requests:
        memory: ${MEM_N8N_WORKER_REQ}Mi
        cpu: ${CPU_N8N_WORKER_REQ}m
EOF

  # Add N8N admin user configuration - COMMENTED OUT: Admin functionality doesn't work properly
  # cat <<-EOF >> $CONFIG_FILE
  # adminUser:
  #   email: "$N8N_ADMIN_EMAIL"
  #   password: "$N8N_ADMIN_PASSWORD"
  #   firstName: "$N8N_ADMIN_FIRST_NAME"
  #   lastName: "$N8N_ADMIN_LAST_NAME"
  # EOF

  # Compute secure cookie based on domain usage
  SECURE_COOKIE_VALUE="true"
  # If LAN access is enabled and n8n LAN domain ends with .local → not secure cookie (HTTP)
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]] && [[ -n "$N8N_DOMAIN_LAN" ]] && [[ "$N8N_DOMAIN_LAN" == *.local ]]; then
    SECURE_COOKIE_VALUE="false"
  fi
  # If public access uses a .local host (rare) → not secure cookie
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]] && [[ -n "$N8N_DOMAIN_PUBLIC" ]] && [[ "$N8N_DOMAIN_PUBLIC" == *.local ]]; then
    SECURE_COOKIE_VALUE="false"
  fi

  # Add N8N SMTP configuration if enabled
  if [[ "$ENABLE_N8N_SMTP" == "y" || "$ENABLE_N8N_SMTP" == "Y" ]]; then
    cat <<-EOF >> $CONFIG_FILE
  extraEnv:
    # SMTP Configuration
    - name: N8N_EMAIL_MODE
      value: "smtp"
    - name: N8N_SMTP_HOST
      value: "$N8N_SMTP_HOST"
    - name: N8N_SMTP_PORT
      value: "$N8N_SMTP_PORT"
    - name: N8N_SMTP_USER
      value: "$N8N_SMTP_USER"
    - name: N8N_SMTP_PASS
      value: "$N8N_SMTP_PASS"
    - name: N8N_SMTP_SENDER
      value: "$N8N_SMTP_SENDER"
    - name: N8N_SMTP_SSL
      value: "$([ "$N8N_SMTP_SSL" = "y" ] && echo "true" || echo "false")"
    - name: N8N_SMTP_STARTTLS
      value: "$([ "$N8N_SMTP_STARTTLS" = "y" ] && echo "true" || echo "false")"
    # Security Configuration
    - name: N8N_SECURE_COOKIE
      value: "$SECURE_COOKIE_VALUE"
EOF
  else
    # Add N8N_SECURE_COOKIE even when SMTP is disabled
    cat <<-EOF >> $CONFIG_FILE
  extraEnv:
    # Security Configuration
    - name: N8N_SECURE_COOKIE
      value: "$SECURE_COOKIE_VALUE"
EOF
  fi

  cat <<-EOF >> $CONFIG_FILE
  postgres:
    # Password is generated with openssl and stored in Secret n8n-postgres-secret.
    user: "n8n"
    database: "n8n"
    persistence:
      size: $PG_STORAGE_SIZE
    resources:
      limits:
        memory: ${MEM_POSTGRES}Mi
        cpu: ${CPU_POSTGRES}m
      requests:
        memory: ${MEM_POSTGRES_REQ}Mi
        cpu: ${CPU_POSTGRES_REQ}m
  persistence:
    enabled: true
    size: $N8N_STORAGE_SIZE
  resources:
    limits:
      memory: ${MEM_N8N}Mi
      cpu: ${CPU_N8N}m
    requests:
      memory: ${MEM_N8N_REQ}Mi
      cpu: ${CPU_N8N_REQ}m

redis:
  persistence:
    enabled: true
    size: $REDIS_STORAGE_SIZE
  master:
    resources:
      limits:
        memory: ${MEM_REDIS}Mi
        cpu: ${CPU_REDIS}m
      requests:
        memory: ${MEM_REDIS_REQ}Mi
        cpu: ${CPU_REDIS_REQ}m
EOF

  # Velero configuration (if enabled)
  if [[ "$ENABLE_VELERO" == "true" ]]; then
    cat <<-EOF >> $CONFIG_FILE

velero:
  enabled: true
  namespace: ${VELERO_NAMESPACE}
  clusterName: "${VELERO_CLUSTER_NAME}"  # Identifies this cluster in backup names
  # NOTE: Velero installation handled by cluster setup
  backup:
    schedule: "${VELERO_SCHEDULE}"
    ttl: "${VELERO_TTL}"
    includeNamespaces:
    - lair
EOF
  else
    cat <<-EOF >> $CONFIG_FILE

velero:
  enabled: false
EOF
  fi

  # MinIO configuration (conditional)
  if [[ "$ENABLE_MINIO" == "y" || "$ENABLE_MINIO" == "Y" ]]; then
    cat <<-EOF >> $CONFIG_FILE

minio:
  enabled: true
  image:
    repository: minio/minio
    tag: latest
  rootUser: $MINIO_ROOT_USER
  rootPassword: $MINIO_ROOT_PASSWORD
  storage:
    size: $MINIO_STORAGE_SIZE
EOF
  else
    cat <<-EOF >> $CONFIG_FILE

minio:
  enabled: false
EOF
  fi

  # ComfyUI configuration (conditional)
  if [[ "$ENABLE_COMFYUI" == "y" || "$ENABLE_COMFYUI" == "Y" ]]; then
    cat <<-EOF >> $CONFIG_FILE

comfyUI:
  enabled: true
  gpuEnabled: $OLLAMA_GPU_ENABLED
  persistence:
    enabled: true
    size: $COMFYUI_STORAGE_SIZE
  resources:
    limits:
      memory: ${MEM_COMFYUI}Mi
      cpu: ${CPU_COMFYUI}m
    requests:
      memory: ${MEM_COMFYUI_REQ}Mi
      cpu: ${CPU_COMFYUI_REQ}m
EOF
    
    # Add custom image configuration if specified
    if [ -n "$COMFYUI_IMAGE" ]; then
      cat <<-EOF >> $CONFIG_FILE
  image:
    repository: $(echo "$COMFYUI_IMAGE" | cut -d':' -f1)
    tag: $(echo "$COMFYUI_IMAGE" | cut -d':' -f2)
EOF
    else
      # Safety check: ensure IS_JETSON is defined
      IS_JETSON=${IS_JETSON:-"n"}
      
      if [ "$IS_JETSON" = "y" ]; then
        # Auto-set Jetson image if platform is Jetson but no image specified
        COMFYUI_IMAGE="dustynv/comfyui:r36.3.0"
        cat <<-EOF >> $CONFIG_FILE
  image:
    repository: $(echo "$COMFYUI_IMAGE" | cut -d':' -f1)
    tag: $(echo "$COMFYUI_IMAGE" | cut -d':' -f2)
EOF
      fi
    fi
    
    # Add special configuration for optimized images
    if [ -n "$COMFYUI_LOW_VRAM" ]; then
      cat <<-EOF >> $CONFIG_FILE
  lowVram: "$COMFYUI_LOW_VRAM"
EOF
    fi
    
    if [ -n "$COMFYUI_MODELS_DOWNLOAD" ]; then
      cat <<-EOF >> $CONFIG_FILE
  modelsDownload: "$COMFYUI_MODELS_DOWNLOAD"
EOF
    fi

  fi
} 