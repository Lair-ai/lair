#!/bin/bash

# ============================================================================
# CONFIG-MANAGEMENT.SH - Configuration File Management Functions
# ============================================================================

# Function to install YAML dependencies if missing
install_yaml_dependencies_if_missing() {
  echo "🔍 Debug: Checking and installing YAML dependencies if missing..."
  
  # Check if user has privileges to install packages
  if [ "$(id -u)" -ne 0 ]; then
    echo "🔍 Debug: Not running as root, skipping automatic dependency installation"
    return 0
  fi
  
  local needs_install=false
  
  # Check if yq is available
  if ! command -v yq &>/dev/null; then
    echo "🔍 Debug: yq not found, marking for installation"
    needs_install=true
  fi
  
  # Check if python3 with yaml module is available
  if ! (command -v python3 &>/dev/null && python3 -c "import yaml" &>/dev/null 2>&1); then
    echo "🔍 Debug: python3 with yaml module not found, marking for installation"
    needs_install=true
  fi
  
  # Only install if we need to and we're running as root
  if [ "$needs_install" = "true" ]; then
    echo "🔄 Installing YAML parsing dependencies..."
    
    # Update package lists
    if ! apt update -y &>/dev/null; then
      echo "🔍 Debug: apt update failed, continuing with installation attempt"
    fi
    
    # Try to install both yq and python3-yaml
    if apt install -y python3-yaml yq &>/dev/null; then
      echo "✅ YAML dependencies installed successfully"
      return 0
    else
      echo "🔍 Debug: Package installation failed, trying individual installations"
      
      # Try python3-yaml first
      if apt install -y python3-yaml &>/dev/null; then
        echo "✅ python3-yaml installed successfully"
      else
        echo "🔍 Debug: python3-yaml installation failed, trying pip3"
        if command -v pip3 &>/dev/null; then
          if pip3 install --break-system-packages PyYAML &>/dev/null; then
            echo "✅ PyYAML installed via pip3"
          else
            echo "🔍 Debug: pip3 installation also failed"
          fi
        fi
      fi
      
      # Try yq installation
      if apt install -y yq &>/dev/null; then
        echo "✅ yq installed successfully"
      else
        echo "🔍 Debug: yq installation failed, trying snap"
        if command -v snap &>/dev/null; then
          if snap install yq &>/dev/null; then
            echo "✅ yq installed via snap"
          else
            echo "🔍 Debug: yq snap installation failed"
          fi
        fi
      fi
    fi
  else
    echo "🔍 Debug: YAML dependencies already available"
  fi
  
  return 0
}

# Function to check if yq is available for YAML parsing
check_yaml_parser() {
  if command -v yq &>/dev/null; then
    YAML_PARSER="yq"
    echo "🔍 Debug: Found yq parser"
    return 0
  elif command -v python3 &>/dev/null; then
    echo "🔍 Debug: Found python3, testing yaml module..."
    # Use timeout to prevent hanging (if available)
    if command -v timeout &>/dev/null; then
      if timeout 5 python3 -c "import yaml; print('yaml available')" &>/dev/null 2>&1; then
        YAML_PARSER="python3"
        echo "🔍 Debug: Python3 with yaml module available"
        return 0
      else
        echo "🔍 Debug: Python3 yaml module not available or timeout"
        return 1
      fi
    else
      # Fallback without timeout - skip python3 yaml test to avoid hanging
      echo "🔍 Debug: No timeout command, skipping python3 yaml test to avoid hanging"
      echo "🔍 Debug: Python3 yaml module test skipped"
      return 1
    fi
  else
    echo "🔍 Debug: No YAML parser available"
    return 1
  fi
}

# Function to read YAML values using available parser
read_yaml_value() {
  local yaml_file=$1
  local yaml_path=$2
  local default_value=$3
  
  if [ ! -f "$yaml_file" ]; then
    echo "$default_value"
    return 1
  fi
  
  local value=""
  if [ "$YAML_PARSER" = "yq" ]; then
    value=$(yq eval "$yaml_path" "$yaml_file" 2>/dev/null)
    if [ "$value" = "null" ] || [ -z "$value" ]; then
      value="$default_value"
    fi
  elif [ "$YAML_PARSER" = "python3" ]; then
    value=$(python3 -c "
import yaml
import sys
try:
    with open('$yaml_file', 'r') as f:
        data = yaml.safe_load(f)
    
    # Navigate through nested keys
    path_parts = '$yaml_path'.strip('.').split('.')
    current = data
    for part in path_parts:
        if isinstance(current, dict) and part in current:
            current = current[part]
        else:
            current = None
            break
    
    if current is not None:
        print(current)
    else:
        print('$default_value')
except:
    print('$default_value')
" 2>/dev/null)
  fi
  
  echo "$value"
}

# Function to detect system hostname for LAN domain generation
detect_system_hostname_for_config() {
  SYSTEM_HOSTNAME=$(hostname | sed 's/\.local$//')  # Remove .local if present
  if [ -z "$SYSTEM_HOSTNAME" ]; then
    SYSTEM_HOSTNAME="lair"  # Fallback hostname
  fi
  echo "🏠 System hostname detected for configuration: $SYSTEM_HOSTNAME"
}



# Function to load configuration from YAML file
load_configuration_from_file() {
  local config_file=$1
  
  if [ ! -f "$config_file" ]; then
    echo -e "${RED}Configuration file $config_file not found!${NC}"
    return 1
  fi
  
  echo -e "${GREEN}📁 Loading configuration from: $config_file${NC}"
  
  # Detect system hostname for LAN domain generation
  detect_system_hostname_for_config
  
  # Load basic configuration
  CONFIG_NAME=$(read_yaml_value "$config_file" ".config_name" "default")
  DETECTION_CHOICE=$(read_yaml_value "$config_file" ".detection_choice" "1")
  USE_DETECTED_RESOURCES=$(read_yaml_value "$config_file" ".use_detected_resources" "true")
  
  # Load platform configuration
  IS_JETSON=$(read_yaml_value "$config_file" ".platform.is_jetson" "false")
  HAS_GPU=$(read_yaml_value "$config_file" ".platform.has_gpu" "false")
  VRAM_PERCENTAGE=$(read_yaml_value "$config_file" ".platform.vram_percentage" "80")
  
  # Load access mode configuration
  ACCESS_MODE=$(read_yaml_value "$config_file" ".platform.access_mode" "lan")
  SYSTEM_HOSTNAME=$(read_yaml_value "$config_file" ".platform.system_hostname" "")
  
  # Convert boolean strings
  if [ "$IS_JETSON" = "true" ] || [ "$IS_JETSON" = "True" ]; then
    IS_JETSON="y"
    PLATFORM_TYPE="jetson"
  else
    IS_JETSON="n"
    PLATFORM_TYPE="standard"
  fi
  
  if [ "$HAS_GPU" = "true" ] || [ "$HAS_GPU" = "True" ]; then
    HAS_GPU="y"
  else
    HAS_GPU="n"
  fi
  
  # Load email and access mode configurations
  CERT_EMAIL=$(read_yaml_value "$config_file" ".email.cert_email" "admin@example.com")
  
  # Load access mode configuration (new dual access structure)
  ENABLE_LAN_ACCESS=$(read_yaml_value "$config_file" ".access.lan.enabled" "")
  ENABLE_LAN_TLS=$(read_yaml_value "$config_file" ".access.lan.tls" "false")
  ENABLE_PUBLIC_ACCESS=$(read_yaml_value "$config_file" ".access.public.enabled" "")
  
  # Fallback to legacy access mode if new structure is not available
  if [ -z "$ENABLE_LAN_ACCESS" ] && [ -z "$ENABLE_PUBLIC_ACCESS" ]; then
    legacy_access_mode=$(read_yaml_value "$config_file" ".platform.access_mode" "lan")
    if [ "$legacy_access_mode" = "public" ]; then
      ENABLE_LAN_ACCESS="false"
      ENABLE_PUBLIC_ACCESS="true"
    else
      ENABLE_LAN_ACCESS="true"
      ENABLE_PUBLIC_ACCESS="false"
    fi
    echo "🔄 Using legacy access mode: $legacy_access_mode"
  fi
  
  # Convert boolean strings to lowercase
  if [ "$ENABLE_LAN_ACCESS" = "True" ] || [ "$ENABLE_LAN_ACCESS" = "TRUE" ]; then
    ENABLE_LAN_ACCESS="true"
  elif [ "$ENABLE_LAN_ACCESS" = "False" ] || [ "$ENABLE_LAN_ACCESS" = "FALSE" ]; then
    ENABLE_LAN_ACCESS="false"
  fi
  
  if [ "$ENABLE_LAN_TLS" = "True" ] || [ "$ENABLE_LAN_TLS" = "TRUE" ]; then
    ENABLE_LAN_TLS="true"
  elif [ "$ENABLE_LAN_TLS" = "False" ] || [ "$ENABLE_LAN_TLS" = "FALSE" ]; then
    ENABLE_LAN_TLS="false"
  fi
  
  if [ "$ENABLE_PUBLIC_ACCESS" = "True" ] || [ "$ENABLE_PUBLIC_ACCESS" = "TRUE" ]; then
    ENABLE_PUBLIC_ACCESS="true"
  elif [ "$ENABLE_PUBLIC_ACCESS" = "False" ] || [ "$ENABLE_PUBLIC_ACCESS" = "FALSE" ]; then
    ENABLE_PUBLIC_ACCESS="false"
  fi
  
  # Load LAN domain configurations and auto-convert to current hostname
  OPENWEBUI_DOMAIN_LAN_RAW=$(read_yaml_value "$config_file" ".domains.lan.openwebui" "ai.lair.local")
  N8N_DOMAIN_LAN_RAW=$(read_yaml_value "$config_file" ".domains.lan.n8n" "n8n.lair.local")
  COMFYUI_DOMAIN_LAN_RAW=$(read_yaml_value "$config_file" ".domains.lan.comfyui" "")
  MINIO_DOMAIN_LAN_RAW=$(read_yaml_value "$config_file" ".domains.lan.minio" "")
  OLLAMA_DOMAIN_LAN_RAW=$(read_yaml_value "$config_file" ".domains.lan.ollama" "")
  
  # Extract subdomain from raw domain and rebuild with current hostname
  OPENWEBUI_SUBDOMAIN_LAN=$(echo "$OPENWEBUI_DOMAIN_LAN_RAW" | cut -d'.' -f1)
  N8N_SUBDOMAIN_LAN=$(echo "$N8N_DOMAIN_LAN_RAW" | cut -d'.' -f1)
  COMFYUI_SUBDOMAIN_LAN=$(echo "$COMFYUI_DOMAIN_LAN_RAW" | cut -d'.' -f1)
  MINIO_SUBDOMAIN_LAN=$(echo "$MINIO_DOMAIN_LAN_RAW" | cut -d'.' -f1)
  OLLAMA_SUBDOMAIN_LAN=$(echo "$OLLAMA_DOMAIN_LAN_RAW" | cut -d'.' -f1)
  
  # Build final LAN domains with current hostname
  if [ -n "$OPENWEBUI_DOMAIN_LAN_RAW" ]; then
    OPENWEBUI_DOMAIN_LAN="$OPENWEBUI_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
  else
    OPENWEBUI_DOMAIN_LAN=""
  fi
  
  if [ -n "$N8N_DOMAIN_LAN_RAW" ]; then
    N8N_DOMAIN_LAN="$N8N_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
  else
    N8N_DOMAIN_LAN=""
  fi
  
  if [ -n "$COMFYUI_DOMAIN_LAN_RAW" ]; then
    COMFYUI_DOMAIN_LAN="$COMFYUI_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
  else
    COMFYUI_DOMAIN_LAN=""
  fi
  
  if [ -n "$MINIO_DOMAIN_LAN_RAW" ]; then
    MINIO_DOMAIN_LAN="$MINIO_SUBDOMAIN_LAN.$SYSTEM_HOSTNAME.local"
  else
    MINIO_DOMAIN_LAN=""
  fi
  
  # SECURITY: Force Ollama LAN domain to be empty for security reasons
  OLLAMA_DOMAIN_LAN=""  # Always internal-only for security
  
  # Load public domain configurations
  OPENWEBUI_DOMAIN_PUBLIC=$(read_yaml_value "$config_file" ".domains.public.openwebui" "ai.example.com")
  N8N_DOMAIN_PUBLIC=$(read_yaml_value "$config_file" ".domains.public.n8n" "n8n.example.com")
  COMFYUI_DOMAIN_PUBLIC=$(read_yaml_value "$config_file" ".domains.public.comfyui" "")
  MINIO_DOMAIN_PUBLIC=$(read_yaml_value "$config_file" ".domains.public.minio" "")
  # SECURITY: Force Ollama public domain to be empty for security reasons
  OLLAMA_DOMAIN_PUBLIC=""  # Always internal-only for security
  
  # Load legacy domain configurations (for backward compatibility)
  OPENWEBUI_DOMAIN=$(read_yaml_value "$config_file" ".domains.openwebui" "ai.example.com")
  N8N_DOMAIN=$(read_yaml_value "$config_file" ".domains.n8n" "n8n.example.com")
  COMFYUI_DOMAIN=$(read_yaml_value "$config_file" ".domains.comfyui" "comfyui.example.com")
  MINIO_DOMAIN=$(read_yaml_value "$config_file" ".domains.minio" "")
  # SECURITY: Force Ollama legacy domain to be empty for security reasons
  OLLAMA_DOMAIN=""  # Always internal-only for security
  
  # Set legacy domains from new ones if not specified
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    OPENWEBUI_DOMAIN=${OPENWEBUI_DOMAIN:-$OPENWEBUI_DOMAIN_PUBLIC}
    N8N_DOMAIN=${N8N_DOMAIN:-$N8N_DOMAIN_PUBLIC}
    COMFYUI_DOMAIN=${COMFYUI_DOMAIN:-$COMFYUI_DOMAIN_PUBLIC}
    MINIO_DOMAIN=${MINIO_DOMAIN:-$MINIO_DOMAIN_PUBLIC}
    # SECURITY: Ollama domain forced to empty for security
    OLLAMA_DOMAIN=""
  elif [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    OPENWEBUI_DOMAIN=${OPENWEBUI_DOMAIN:-$OPENWEBUI_DOMAIN_LAN}
    N8N_DOMAIN=${N8N_DOMAIN:-$N8N_DOMAIN_LAN}
    COMFYUI_DOMAIN=${COMFYUI_DOMAIN:-$COMFYUI_DOMAIN_LAN}
    MINIO_DOMAIN=${MINIO_DOMAIN:-$MINIO_DOMAIN_LAN}
    # SECURITY: Ollama domain can use LAN but only if explicitly set
    OLLAMA_DOMAIN=${OLLAMA_DOMAIN:-$OLLAMA_DOMAIN_LAN}
  fi
  
  # Load storage configuration
  OPENWEBUI_STORAGE_GB=$(read_yaml_value "$config_file" ".storage.openwebui" "10")
  OLLAMA_STORAGE_GB=$(read_yaml_value "$config_file" ".storage.ollama_models" "30")
  N8N_STORAGE_GB=$(read_yaml_value "$config_file" ".storage.n8n_workflows" "10")
  PG_STORAGE_GB=$(read_yaml_value "$config_file" ".storage.postgresql" "5")
  REDIS_STORAGE_GB=$(read_yaml_value "$config_file" ".storage.redis" "5")
  MINIO_STORAGE_GB=$(read_yaml_value "$config_file" ".storage.minio" "20")
  COMFYUI_STORAGE_GB=$(read_yaml_value "$config_file" ".storage.comfyui" "15")
  
  # Convert to Gi format
  OPENWEBUI_STORAGE_SIZE="${OPENWEBUI_STORAGE_GB}Gi"
  OLLAMA_STORAGE_SIZE="${OLLAMA_STORAGE_GB}Gi"
  N8N_STORAGE_SIZE="${N8N_STORAGE_GB}Gi"
  PG_STORAGE_SIZE="${PG_STORAGE_GB}Gi"
  REDIS_STORAGE_SIZE="${REDIS_STORAGE_GB}Gi"
  MINIO_STORAGE_SIZE="${MINIO_STORAGE_GB}Gi"
  COMFYUI_STORAGE_SIZE="${COMFYUI_STORAGE_GB}Gi"
  
  # Load component configuration
  ENABLE_MINIO=$(read_yaml_value "$config_file" ".components.minio.enabled" "true")
  MINIO_ROOT_USER=$(read_yaml_value "$config_file" ".components.minio.root_user" "minioadmin")
  MINIO_ROOT_PASSWORD=$(read_yaml_value "$config_file" ".components.minio.root_password" "minioadmin")
  
  ENABLE_COMFYUI=$(read_yaml_value "$config_file" ".components.comfyui.enabled" "true")
  COMFYUI_IMAGE=$(read_yaml_value "$config_file" ".components.comfyui.image" "")
  COMFYUI_LOW_VRAM=$(read_yaml_value "$config_file" ".components.comfyui.low_vram" "")
  COMFYUI_MODELS_DOWNLOAD=$(read_yaml_value "$config_file" ".components.comfyui.models_download" "")
  
  # Load Ollama configuration
  OLLAMA_IMAGE=$(read_yaml_value "$config_file" ".components.ollama.image" "")
  
  # Load N8N configuration
  N8N_KEY=$(read_yaml_value "$config_file" ".n8n.encryption_key" "")
  
  # Load N8N SMTP configuration
  ENABLE_N8N_SMTP=$(read_yaml_value "$config_file" ".n8n.smtp.enabled" "false")
  N8N_SMTP_HOST=$(read_yaml_value "$config_file" ".n8n.smtp.host" "")
  N8N_SMTP_PORT=$(read_yaml_value "$config_file" ".n8n.smtp.port" "587")
  N8N_SMTP_USER=$(read_yaml_value "$config_file" ".n8n.smtp.user" "")
  N8N_SMTP_PASS=$(read_yaml_value "$config_file" ".n8n.smtp.password" "")
  N8N_SMTP_SENDER=$(read_yaml_value "$config_file" ".n8n.smtp.sender" "")
  N8N_SMTP_SSL=$(read_yaml_value "$config_file" ".n8n.smtp.ssl" "true")
  N8N_SMTP_STARTTLS=$(read_yaml_value "$config_file" ".n8n.smtp.starttls" "true")
  
  # Convert SMTP boolean strings
  if [ "$ENABLE_N8N_SMTP" = "true" ] || [ "$ENABLE_N8N_SMTP" = "True" ]; then
    ENABLE_N8N_SMTP="y"
  else
    ENABLE_N8N_SMTP="n"
  fi
  
  if [ "$N8N_SMTP_SSL" = "true" ] || [ "$N8N_SMTP_SSL" = "True" ]; then
    N8N_SMTP_SSL="y"
  else
    N8N_SMTP_SSL="n"
  fi
  
  if [ "$N8N_SMTP_STARTTLS" = "true" ] || [ "$N8N_SMTP_STARTTLS" = "True" ]; then
    N8N_SMTP_STARTTLS="y"
  else
    N8N_SMTP_STARTTLS="n"
  fi
  
  # N8N Admin User configuration (try both admin and adminUser for compatibility)
  N8N_ADMIN_EMAIL=$(read_yaml_value "$config_file" ".n8n.adminUser.email" "")
  if [ -z "$N8N_ADMIN_EMAIL" ]; then
    N8N_ADMIN_EMAIL=$(read_yaml_value "$config_file" ".n8n.admin.email" "admin@n8n.local")
  fi
  
  N8N_ADMIN_PASSWORD=$(read_yaml_value "$config_file" ".n8n.adminUser.password" "")
  if [ -z "$N8N_ADMIN_PASSWORD" ]; then
    N8N_ADMIN_PASSWORD=$(read_yaml_value "$config_file" ".n8n.admin.password" "n8n123")
  fi
  
  N8N_ADMIN_FIRST_NAME=$(read_yaml_value "$config_file" ".n8n.adminUser.firstName" "")
  if [ -z "$N8N_ADMIN_FIRST_NAME" ]; then
    N8N_ADMIN_FIRST_NAME=$(read_yaml_value "$config_file" ".n8n.admin.firstName" "Admin")
  fi
  
  N8N_ADMIN_LAST_NAME=$(read_yaml_value "$config_file" ".n8n.adminUser.lastName" "")
  if [ -z "$N8N_ADMIN_LAST_NAME" ]; then
    N8N_ADMIN_LAST_NAME=$(read_yaml_value "$config_file" ".n8n.admin.lastName" "User")
  fi
  
  # OpenWebUI SSO configuration
  ENABLE_OPENWEBUI_SSO=$(read_yaml_value "$config_file" ".openwebui.sso.enabled" "false")
  OPENWEBUI_SSO_PROVIDER=$(read_yaml_value "$config_file" ".openwebui.sso.provider" "")
  OPENWEBUI_OAUTH_CLIENT_ID=$(read_yaml_value "$config_file" ".openwebui.sso.oauth.client_id" "")
  OPENWEBUI_OAUTH_CLIENT_SECRET=$(read_yaml_value "$config_file" ".openwebui.sso.oauth.client_secret" "")
  OPENWEBUI_OAUTH_PROVIDER_NAME=$(read_yaml_value "$config_file" ".openwebui.sso.oauth.provider_name" "SSO")
  OPENWEBUI_OAUTH_SCOPES=$(read_yaml_value "$config_file" ".openwebui.sso.oauth.scopes" "openid email profile")
  OPENWEBUI_OPENID_PROVIDER_URL=$(read_yaml_value "$config_file" ".openwebui.sso.oauth.provider_url" "")
  OPENWEBUI_OPENID_REDIRECT_URI=$(read_yaml_value "$config_file" ".openwebui.sso.oauth.redirect_uri" "")
  OPENWEBUI_GOOGLE_CLIENT_ID=$(read_yaml_value "$config_file" ".openwebui.sso.google.client_id" "")
  OPENWEBUI_GOOGLE_CLIENT_SECRET=$(read_yaml_value "$config_file" ".openwebui.sso.google.client_secret" "")
  OPENWEBUI_GOOGLE_REDIRECT_URI=$(read_yaml_value "$config_file" ".openwebui.sso.google.redirect_uri" "")
  OPENWEBUI_MICROSOFT_CLIENT_ID=$(read_yaml_value "$config_file" ".openwebui.sso.microsoft.client_id" "")
  OPENWEBUI_MICROSOFT_CLIENT_SECRET=$(read_yaml_value "$config_file" ".openwebui.sso.microsoft.client_secret" "")
  OPENWEBUI_MICROSOFT_CLIENT_TENANT_ID=$(read_yaml_value "$config_file" ".openwebui.sso.microsoft.tenant_id" "")
  OPENWEBUI_MICROSOFT_REDIRECT_URI=$(read_yaml_value "$config_file" ".openwebui.sso.microsoft.redirect_uri" "")
  OPENWEBUI_GITHUB_CLIENT_ID=$(read_yaml_value "$config_file" ".openwebui.sso.github.client_id" "")
  OPENWEBUI_GITHUB_CLIENT_SECRET=$(read_yaml_value "$config_file" ".openwebui.sso.github.client_secret" "")
  OPENWEBUI_TRUSTED_EMAIL_HEADER=$(read_yaml_value "$config_file" ".openwebui.sso.trusted_header.email_header" "")
  OPENWEBUI_TRUSTED_NAME_HEADER=$(read_yaml_value "$config_file" ".openwebui.sso.trusted_header.name_header" "")
  ENABLE_OPENWEBUI_OAUTH_SIGNUP=$(read_yaml_value "$config_file" ".openwebui.sso.oauth.enable_signup" "true")
  ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS=$(read_yaml_value "$config_file" ".openwebui.sso.oauth.merge_accounts_by_email" "false")
  ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE=$(read_yaml_value "$config_file" ".openwebui.sso.oauth.update_picture_on_login" "true")
  
  # Convert OpenWebUI SSO boolean strings
  if [ "$ENABLE_OPENWEBUI_SSO" = "true" ] || [ "$ENABLE_OPENWEBUI_SSO" = "True" ]; then
    ENABLE_OPENWEBUI_SSO="y"
  else
    ENABLE_OPENWEBUI_SSO="n"
  fi
  
  if [ "$ENABLE_OPENWEBUI_OAUTH_SIGNUP" = "true" ] || [ "$ENABLE_OPENWEBUI_OAUTH_SIGNUP" = "True" ]; then
    ENABLE_OPENWEBUI_OAUTH_SIGNUP="y"
  else
    ENABLE_OPENWEBUI_OAUTH_SIGNUP="n"
  fi
  
  if [ "$ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS" = "true" ] || [ "$ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS" = "True" ]; then
    ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS="y"
  else
    ENABLE_OPENWEBUI_OAUTH_MERGE_ACCOUNTS="n"
  fi
  
  if [ "$ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE" = "true" ] || [ "$ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE" = "True" ]; then
    ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE="y"
  else
    ENABLE_OPENWEBUI_OAUTH_UPDATE_PICTURE="n"
  fi
  
  # Load deployment configuration
  AUTO_DEPLOY=$(read_yaml_value "$config_file" ".deployment.auto_deploy" "false")
  # Force default release name to 'lair' and ignore config overrides
  RELEASE_NAME="lair"
  NEW_INSTALL=$(read_yaml_value "$config_file" ".deployment.new_install" "true")
  
  # Convert boolean strings for components
  if [ "$ENABLE_MINIO" = "true" ] || [ "$ENABLE_MINIO" = "True" ]; then
    ENABLE_MINIO="y"
  else
    ENABLE_MINIO="n"
  fi
  
  if [ "$ENABLE_COMFYUI" = "true" ] || [ "$ENABLE_COMFYUI" = "True" ]; then
    ENABLE_COMFYUI="y"
  else
    ENABLE_COMFYUI="n"
  fi
  
  echo -e "${GREEN}✅ Configuration loaded successfully from $config_file${NC}"
  echo -e "${BLUE}Client: $(read_yaml_value "$config_file" ".client_name" "Unknown")${NC}"
  echo -e "${BLUE}Platform: $PLATFORM_TYPE, GPU: $(if [[ "$HAS_GPU" == "y" ]]; then echo "Yes"; else echo "No"; fi)${NC}"
  
  if ! validate_configuration_placeholders "$config_file"; then
    return 1
  fi

  USE_CONFIG_FILE=true
  return 0
}

# Function to validate that active placeholders (CHANGE_ME) are modified
validate_configuration_placeholders() {
  local has_errors=false
  local config_file=$1

  echo -e "${BLUE}🔍 Validating configuration placeholders in $config_file...${NC}"

  # Helper function to check a single path
  check_placeholder() {
    local path=$1
    local name=$2
    local value
    value=$(read_yaml_value "$config_file" "$path" "")

    if [[ "$value" == *CHANGE_ME* ]]; then
      echo -e "${RED}❌ Validation Error: Field '$name' ($path) contains an unmodified placeholder: '$value'${NC}"
      has_errors=true
    fi
  }

  # 1. Base Configuration Check (Always required)
  check_placeholder ".client_name" "Client Name"
  check_placeholder ".config_name" "Configuration Name"

  # 2. Public Access Check
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    check_placeholder ".email.cert_email" "Certificate Email"

    # Check public domains only if the overall public access is enabled
    check_placeholder ".domains.public.openwebui" "OpenWebUI Public Domain"
    check_placeholder ".domains.public.n8n" "N8N Public Domain"

    if [[ "$ENABLE_MINIO" == "y" || "$ENABLE_MINIO" == "Y" ]]; then
      check_placeholder ".domains.public.minio" "MinIO Public Domain"
    fi
    if [[ "$ENABLE_COMFYUI" == "y" || "$ENABLE_COMFYUI" == "Y" ]]; then
      # Only validate if not empty (it's optional)
      local comfyui_pub
      comfyui_pub=$(read_yaml_value "$config_file" ".domains.public.comfyui" "")
      if [[ "$comfyui_pub" == *CHANGE_ME* ]]; then
        check_placeholder ".domains.public.comfyui" "ComfyUI Public Domain"
      fi
    fi
  fi

  # 3. LAN Access Check
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    check_placeholder ".domains.lan.openwebui" "OpenWebUI LAN Domain"
    check_placeholder ".domains.lan.n8n" "N8N LAN Domain"

    if [[ "$ENABLE_MINIO" == "y" || "$ENABLE_MINIO" == "Y" ]]; then
      check_placeholder ".domains.lan.minio" "MinIO LAN Domain"
    fi
  fi

  # 4. MinIO Credentials Check (only if MinIO is active)
  if [[ "$ENABLE_MINIO" == "y" || "$ENABLE_MINIO" == "Y" ]]; then
    check_placeholder ".components.minio.root_user" "MinIO Root User"
    check_placeholder ".components.minio.root_password" "MinIO Root Password"
  fi

  # 5. SMTP Check (only if SMTP is enabled)
  local smtp_enabled
  smtp_enabled=$(read_yaml_value "$config_file" ".n8n.smtp.enabled" "false")
  if [[ "$smtp_enabled" == "true" || "$smtp_enabled" == "True" ]]; then
    check_placeholder ".n8n.smtp.host" "SMTP Host"
    check_placeholder ".n8n.smtp.user" "SMTP User"
    check_placeholder ".n8n.smtp.password" "SMTP Password"
    check_placeholder ".n8n.smtp.sender" "SMTP Sender"
  fi

  # 6. N8N Encryption Key
  check_placeholder ".n8n.encryption_key" "N8N Encryption Key"

  # 7. N8N Admin User (Always check since N8N configuration reads it)
  check_placeholder ".n8n.adminUser.email" "N8N Admin Email"
  check_placeholder ".n8n.adminUser.password" "N8N Admin Password"
  check_placeholder ".n8n.adminUser.firstName" "N8N Admin First Name"
  check_placeholder ".n8n.adminUser.lastName" "N8N Admin Last Name"

  if [ "$has_errors" = "true" ]; then
    echo ""
    echo -e "${RED}🚨 DEPLOYMENT BLOCKED: Please edit '$config_file' and replace all active CHANGE_ME placeholders with valid, secure values before running setup again.${NC}"
    echo ""
    return 1
  fi

  echo -e "${GREEN}✅ Configuration validation passed! No active placeholders found.${NC}"
  return 0
}

# Function to ask if user wants to import from config file
ask_for_config_file_import() {
  echo "🔍 Debug: Starting ask_for_config_file_import function"
  
  echo ""
  echo -e "${YELLOW}📋 Configuration Import Options${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  echo "🔍 Debug: Checking for config files"
  
  # Check if there are any config files available
  config_files=(*.yaml *.yml)
  available_configs=()
  for file in "${config_files[@]}"; do
    if [[ -f "$file" && "$file" != "values-"* && "$file" != "Chart.yaml" && "$file" != "lair-config-template.yaml" && "$file" != "values.yaml" ]]; then
      available_configs+=("$file")
    fi
  done
  
  echo "🔍 Debug: Found ${#available_configs[@]} config files"
  
  if [ ${#available_configs[@]} -eq 0 ]; then
    echo "No configuration files found. Proceeding with interactive mode."
    echo "🔍 Debug: ask_for_config_file_import returning 1 (no files)"
    return 1
  fi
  
  echo "Available configuration files:"
  for i in "${!available_configs[@]}"; do
    local file="${available_configs[$i]}"
    # Temporarily skip YAML parsing to avoid blocking
    # local client_name=$(read_yaml_value "$file" ".client_name" "Unknown")
    echo "  $((i+1))) $file (Client: )"
  done
  echo "  0) Skip - use interactive mode"
  echo ""
  echo -e "${YELLOW}⚠️  Please select an option and press ENTER:${NC}"
  echo "   • Press 0 and ENTER for interactive mode"
  echo "   • Press 1 and ENTER for first config file"
  echo "   • Press 2 and ENTER for second config file"
  echo ""
  
  echo "🔍 Debug: About to read user choice"
  
  # Simple read without timeout - clear instructions should be enough
  read -p "Select configuration file to import [0-${#available_configs[@]}] (default: 0): " choice
  
  choice=${choice:-0}
  echo "🔍 Debug: User selected choice: $choice"
  
  if [[ "$choice" -gt 0 ]] && [[ "$choice" -le "${#available_configs[@]}" ]]; then
    local selected_file="${available_configs[$((choice-1))]}"
    CONFIG_FILE_PATH="$selected_file"
    echo "🔍 Debug: ask_for_config_file_import returning 0 (file selected: $selected_file)"
    return 0
  else
    echo "Proceeding with interactive mode."
    echo "🔍 Debug: ask_for_config_file_import returning 1 (interactive mode)"
    return 1
  fi
} 