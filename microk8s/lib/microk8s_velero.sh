#!/usr/bin/env bash

# region Velero Backup & DR Configuration and Installation
# This module handles Velero configuration prompts and installation for MicroK8s

# Function to ask Velero configuration settings
ask_velero_settings() {
  echo ""
  info "🔄 Backup & Disaster Recovery Configuration"
  echo "Velero automatically backs up your applications and data to cloud storage."
  echo "This protects against data loss and enables disaster recovery."
  echo ""
  
  read -p "Enable Velero backups? (y/n) [default: y]: " _enable_velero
  _enable_velero=${_enable_velero:-y}
  
  if [[ "$_enable_velero" =~ ^[Yy]$ ]]; then
    export LAIR_VELERO_ENABLE=true
    ok "Velero backup enabled"
    
    echo ""
    info "📋 Backup Storage Configuration:"
    
    # Namespace (simplified for most users)
    LAIR_VELERO_NAMESPACE="velero"
    export LAIR_VELERO_NAMESPACE
    echo "✅ Using namespace: velero (standard location for backups)"
    
    # Provider (fixed to aws for all S3-compatible providers like OVH)
    LAIR_VELERO_PROVIDER="aws"
    export LAIR_VELERO_PROVIDER
    echo "✅ Using provider: aws (compatible with OVH, AWS, MinIO, and other S3 storage)"
    
    # S3 Configuration
    echo ""
    info "☁️  Cloud Storage Details:"
    echo "Please provide your cloud storage bucket information."
    read -p "📦 Bucket name or URL (where backups will be stored): " LAIR_VELERO_BUCKET
    # Normalize bucket input (support full URL like https://backup-lair.s3.gra.io.cloud.ovh.net/)
    _bucket_input="$LAIR_VELERO_BUCKET"
    if [[ "$_bucket_input" == http*://* ]]; then
      _bucket_input="${_bucket_input#*://}"
    fi
    _bucket_input="${_bucket_input%/}"
    if [[ "$_bucket_input" == *.s3.* ]]; then
      LAIR_VELERO_BUCKET="${_bucket_input%%.s3.*}"
    else
      LAIR_VELERO_BUCKET="$_bucket_input"
    fi
    export LAIR_VELERO_BUCKET
    
    read -p "🌐 Storage endpoint URL [default: https://s3.gra.io.cloud.ovh.net]: " LAIR_VELERO_S3URL
    LAIR_VELERO_S3URL=${LAIR_VELERO_S3URL:-https://s3.gra.io.cloud.ovh.net}
    LAIR_VELERO_S3URL="${LAIR_VELERO_S3URL%/}"
    export LAIR_VELERO_S3URL
    
    # Derive default region from endpoint (OVH pattern: s3.<region>.io.cloud.ovh.net)
    _default_region="gra"
    if [[ "$LAIR_VELERO_S3URL" =~ s3\.([a-z0-9-]+)\.io\.cloud\.ovh\.net ]]; then
      _default_region="${BASH_REMATCH[1]}"
    fi
    read -p "🗺️  Region code (gra=France, sbg=France, bhs=Canada) [default: ${_default_region}]: " LAIR_VELERO_REGION
    LAIR_VELERO_REGION=${LAIR_VELERO_REGION:-${_default_region}}
    export LAIR_VELERO_REGION
    
    # Credentials
    echo ""
    info "🔐 Storage Access Credentials:"
    echo "To access your cloud storage, we need your access credentials."
    echo ""
    echo "How would you like to provide them?"
    echo "  1) 🆕 Enter credentials now (recommended for new setups)"
    echo "  2) 🔄 Use existing credentials stored in cluster (advanced)"
    echo ""
    
    read -p "Choose option (1/2) [default: 1]: " _cred_option
    _cred_option=${_cred_option:-1}
    
    if [[ "$_cred_option" == "2" ]]; then
      echo ""
      info "Using existing stored credentials..."
      read -p "Name of existing credential store [default: velero-credentials]: " LAIR_VELERO_EXISTING_SECRET
      LAIR_VELERO_EXISTING_SECRET=${LAIR_VELERO_EXISTING_SECRET:-velero-credentials}
      export LAIR_VELERO_EXISTING_SECRET
      export LAIR_VELERO_ACCESS_KEY=""
      export LAIR_VELERO_SECRET_KEY=""
    else
      echo ""
      info "Please provide your cloud storage access keys:"
      echo "(These are provided by your cloud storage provider)"
      read -p "🔑 Access Key: " LAIR_VELERO_ACCESS_KEY
      read -s -p "🔒 Secret Key (hidden): " LAIR_VELERO_SECRET_KEY
      echo ""  # New line after hidden input
      export LAIR_VELERO_ACCESS_KEY
      export LAIR_VELERO_SECRET_KEY
      export LAIR_VELERO_EXISTING_SECRET=""
    fi
    
    echo ""
    ok "✅ Backup configuration completed successfully!"
    echo ""
    echo "📋 Configuration Summary:"
    echo "  • 📁 Backup location: $LAIR_VELERO_NAMESPACE namespace"
    echo "  • ☁️  Storage provider: $LAIR_VELERO_PROVIDER (S3-compatible)"
    echo "  • 📦 Backup bucket: $LAIR_VELERO_BUCKET"
    echo "  • 🗺️  Storage region: $LAIR_VELERO_REGION"
    echo "  • 🌐 Storage endpoint: $LAIR_VELERO_S3URL"
    if [[ -n "$LAIR_VELERO_EXISTING_SECRET" ]]; then
      echo "  • 🔐 Using existing credentials: $LAIR_VELERO_EXISTING_SECRET"
    else
      echo "  • 🔐 Credentials will be stored securely in the cluster"
    fi
    echo ""
    echo "🔄 Velero will be installed during the next setup phase."
    
    # Persist Velero configuration to a temporary file for later use
  local velero_config_file="/etc/lair_velero_config.env"
  cat > "$velero_config_file" <<-EOF
export LAIR_VELERO_ENABLE="$LAIR_VELERO_ENABLE"
export LAIR_VELERO_NAMESPACE="$LAIR_VELERO_NAMESPACE"
export LAIR_VELERO_PROVIDER="$LAIR_VELERO_PROVIDER"
export LAIR_VELERO_BUCKET="$LAIR_VELERO_BUCKET"
export LAIR_VELERO_REGION="$LAIR_VELERO_REGION"
export LAIR_VELERO_S3URL="$LAIR_VELERO_S3URL"
export LAIR_VELERO_ACCESS_KEY="$LAIR_VELERO_ACCESS_KEY"
export LAIR_VELERO_SECRET_KEY="$LAIR_VELERO_SECRET_KEY"
export LAIR_VELERO_EXISTING_SECRET="$LAIR_VELERO_EXISTING_SECRET"
EOF
  chmod 600 "$velero_config_file"  # Secure the credentials file
  debug "Velero configuration saved to $velero_config_file"
    
  else
    export LAIR_VELERO_ENABLE=false
    info "Velero backup disabled - skipping configuration"
    
    # Create empty config file to indicate Velero is disabled
    local velero_config_file="/etc/lair_velero_config.env"
    echo 'export LAIR_VELERO_ENABLE="false"' > "$velero_config_file"
    chmod 600 "$velero_config_file"
  fi
}

# Function to install Velero via Helm
install_velero() {
  # Load Velero configuration from persistent file
  local velero_config_file="/etc/lair_velero_config.env"
  if [[ -f "$velero_config_file" ]]; then
    debug "Loading Velero configuration from $velero_config_file"
    source "$velero_config_file"
  else
    warn "Velero configuration file not found at $velero_config_file"
  fi
  
  # Debug: Show current Velero environment variables
  debug "LAIR_VELERO_ENABLE=${LAIR_VELERO_ENABLE:-<not set>}"
  debug "LAIR_VELERO_NAMESPACE=${LAIR_VELERO_NAMESPACE:-<not set>}"
  debug "LAIR_VELERO_PROVIDER=${LAIR_VELERO_PROVIDER:-<not set>}"
  
  if [[ "$LAIR_VELERO_ENABLE" != "true" ]]; then
    info "Velero installation skipped (not enabled) - LAIR_VELERO_ENABLE='${LAIR_VELERO_ENABLE:-<not set>}'"
    return 0
  fi
  
  info "📦 Install Velero: starting installation phase"
  
  # Verify MicroK8s Helm is available
  if ! microk8s helm3 version >/dev/null 2>&1; then
    err "📦 Install Velero: MicroK8s Helm3 not available - cannot install Velero"
    return 1
  fi
  debug "📦 Install Velero: MicroK8s Helm3 is available"
  
  # Ensure MicroK8s is ready before proceeding
  info "📦 Install Velero: verifying MicroK8s cluster readiness"
  local max_wait=60
  local wait_count=0
  while ! microk8s kubectl cluster-info >/dev/null 2>&1; do
    if [[ $wait_count -ge $max_wait ]]; then
      err "📦 Install Velero: MicroK8s cluster not ready after ${max_wait}s - aborting"
      return 1
    fi
    info "📦 Install Velero: waiting for MicroK8s cluster... (${wait_count}/${max_wait}s)"
    sleep 1
    ((wait_count++))
  done
  ok "📦 Install Velero: MicroK8s cluster is ready"
  
  # Add Velero Helm repository
  if ! run_cmd "microk8s helm3 repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts" "Add Velero Helm repository"; then
    err "Failed to add Velero Helm repository"
    return 1
  fi
  
  if ! run_cmd "microk8s helm3 repo update" "Update Helm repositories"; then
    warn "Helm repo update failed, continuing with installation"
  fi
  
  # Create Velero namespace
  run_cmd "microk8s kubectl create namespace ${LAIR_VELERO_NAMESPACE}" "Create Velero namespace" || true
  
  # Create credentials secret if access keys are provided
  if [[ -n "$LAIR_VELERO_ACCESS_KEY" && -n "$LAIR_VELERO_SECRET_KEY" ]]; then
    info "Creating Velero credentials secret..."
    
    # Delete existing secret if present
    run_cmd "microk8s kubectl -n ${LAIR_VELERO_NAMESPACE} delete secret velero-credentials" "Delete existing credentials secret" || true
    
    # Create new credentials secret
    if ! run_cmd "microk8s kubectl -n ${LAIR_VELERO_NAMESPACE} create secret generic velero-credentials --from-literal=cloud='[default]
aws_access_key_id=${LAIR_VELERO_ACCESS_KEY}
aws_secret_access_key=${LAIR_VELERO_SECRET_KEY}'" "Create Velero credentials secret"; then
      err "Failed to create Velero credentials secret"
      return 1
    fi
    
    ok "Velero credentials secret created"
  fi
  
  # Install Velero via Helm using a temp values file (robust, includes CRDs)
  info "📦 Install Velero: preparing Helm values and chart install"
  
  local VELERO_TMP_VALUES
  VELERO_TMP_VALUES=$(mktemp /tmp/velero-values-XXXXXXXX.yaml)
  
  # Determine secret name to reference in chart
  local SECRET_NAME="velero-credentials"
  if [[ -n "$LAIR_VELERO_EXISTING_SECRET" ]]; then
    SECRET_NAME="$LAIR_VELERO_EXISTING_SECRET"
  fi
  
  info "📦 Install Velero: creating values file at $VELERO_TMP_VALUES"
  cat > "$VELERO_TMP_VALUES" <<-EOF
installCRDs: true
configuration:
  # Enable file-system backup for PVCs (Restic/Kopia)
  defaultVolumesToFsBackup: true
  backupStorageLocation:
  - name: default
    provider: ${LAIR_VELERO_PROVIDER}
    bucket: ${LAIR_VELERO_BUCKET}
    default: true
    credential:
      name: ${SECRET_NAME}
      key: cloud
    config:
      region: ${LAIR_VELERO_REGION}
      s3ForcePathStyle: true
      s3Url: ${LAIR_VELERO_S3URL}
  volumeSnapshotLocation:
  - name: default
    provider: ${LAIR_VELERO_PROVIDER}
    config:
      region: ${LAIR_VELERO_REGION}
credentials:
  existingSecret: ${SECRET_NAME}
# Enable node-agent for file-system backup (replaces deprecated restic)
deployNodeAgent: true
initContainers:
  - name: velero-plugin-for-aws
    image: velero/velero-plugin-for-aws:v1.9.2
    volumeMounts:
      - mountPath: /target
        name: plugins
EOF
  
  # Verify values file was created correctly
  if [[ ! -f "$VELERO_TMP_VALUES" ]]; then
    err "Failed to create Velero values file"
    return 1
  fi
  
  info "📦 Install Velero: values file created; contents below"
  info "$(cat "$VELERO_TMP_VALUES")"
  
  local helm_cmd="microk8s helm3 upgrade --install velero vmware-tanzu/velero \
    --namespace ${LAIR_VELERO_NAMESPACE} \
    --create-namespace \
    -f $VELERO_TMP_VALUES \
    --wait --timeout=10m"
  
  info "📦 Install Velero: executing Helm command"
  info "$helm_cmd"
  if run_cmd "$helm_cmd" "Install Velero"; then
    ok "📦 Install Velero: helm upgrade/install completed"
    
    # Wait for Velero deployment to be ready
    info "📦 Install Velero: waiting for Velero deployment readiness"
    if run_cmd "microk8s kubectl -n ${LAIR_VELERO_NAMESPACE} rollout status deployment/velero --timeout=300s" "Wait for Velero deployment"; then
      ok "📦 Install Velero: deployment is Ready"
    else
      warn "📦 Install Velero: readiness wait timed out; installation may still be OK"
    fi
    
    # Show Velero status
    info "📦 Install Velero: installation summary"
    echo "  • Namespace: ${LAIR_VELERO_NAMESPACE}"
    echo "  • Provider: ${LAIR_VELERO_PROVIDER}"
    echo "  • Bucket: ${LAIR_VELERO_BUCKET}"
    echo "  • Region: ${LAIR_VELERO_REGION}"
    echo "  • S3 URL: ${LAIR_VELERO_S3URL}"
    echo ""
    echo "Next steps:"
    echo "  • Deploy Lair applications with Velero enabled in values.yaml"
    echo "  • Velero will automatically create backup schedules for the 'lair' namespace"
    echo "  • Check backup status: microk8s kubectl get backups -n ${LAIR_VELERO_NAMESPACE}"
    
    # Cleanup temp values file
    rm -f "$VELERO_TMP_VALUES" || true
    
    # Cleanup Velero config file (keep it for troubleshooting)
    rm -f "/etc/lair_velero_config.env" || true
  else
    err "📦 Install Velero: helm upgrade/install failed"
    err "Command that failed: $helm_cmd"
    err "Values file was: $VELERO_TMP_VALUES"
    if [[ -f "$VELERO_TMP_VALUES" ]]; then
      err "Values file contents:"
      err "$(cat "$VELERO_TMP_VALUES")"
    fi
    err "Checking Helm status..."
    run_cmd "microk8s helm3 list -A" "List all Helm releases" || true
    run_cmd "microk8s kubectl get pods -n ${LAIR_VELERO_NAMESPACE}" "Check Velero namespace pods" || true
    rm -f "$VELERO_TMP_VALUES" || true
    # Keep config file for troubleshooting
    rm -f "/etc/lair_velero_config.env" || true
    return 1
  fi
}

# endregion Velero Backup & DR Configuration and Installation
