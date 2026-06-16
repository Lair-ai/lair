#!/usr/bin/env bash

# Velero Backup & Disaster Recovery Component
# Handles interactive and non-interactive configuration for Velero

# Detect cluster name from various sources
detect_cluster_name() {
  local detected_name=""
  
  # Method 1: Try kubectl context name (most reliable)
  if command -v kubectl >/dev/null 2>&1; then
    local context_name
    context_name=$(kubectl config current-context 2>/dev/null || echo "")
    if [[ -n "$context_name" ]]; then
      # Extract first part before dot (e.g., "zeus" from "zeus.lair-ai.it")
      detected_name=$(echo "$context_name" | cut -d'.' -f1)
      # Clean up common prefixes/suffixes
      detected_name=$(echo "$detected_name" | sed -e 's/^microk8s-//' -e 's/-cluster$//' -e 's/-context$//')
    fi
  fi
  
  # Method 2: Try hostname if context didn't work
  if [[ -z "$detected_name" ]] || [[ "$detected_name" == "default" ]] || [[ "$detected_name" == "kubernetes" ]]; then
    detected_name=$(hostname 2>/dev/null | cut -d'.' -f1 | tr '[:upper:]' '[:lower:]' || echo "")
  fi
  
  # Method 3: Fallback to "lair"
  if [[ -z "$detected_name" ]]; then
    detected_name="lair"
  fi
  
  # Sanitize: lowercase, replace spaces/underscores with dashes, remove special chars
  detected_name=$(echo "$detected_name" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | sed 's/[^a-z0-9-]//g')
  
  echo "$detected_name"
}

# Configure Velero backups (interactive)
configure_velero() {
  echo ""
  echo -e "${GREEN}🛡️  Backup & Disaster Recovery (Velero)${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Velero performs scheduled backups of Kubernetes resources and PVCs."
  echo ""
  echo "⚠️  IMPORTANT: Velero must be already installed in the cluster"
  echo "   (via microk8s/setup.sh or k8s-managed/setup.sh)"
  echo ""
  
  read -p "Enable automatic backups with Velero? (y/n) [default: n]: " enable_velero
  enable_velero=${enable_velero:-n}
  
  if [[ "$enable_velero" =~ ^[Yy]$ ]]; then
    ENABLE_VELERO="true"
    VELERO_NAMESPACE="velero"
    VELERO_SCHEDULE=${VELERO_SCHEDULE:-"0 2 * * *"}
    VELERO_TTL=${VELERO_TTL:-"720h0m0s"}
    
    # Detect and ask for cluster name
    local detected_cluster
    detected_cluster=$(detect_cluster_name)
    echo ""
    echo "📛 Cluster Identification"
    echo "   Backup names will include the cluster name for easy identification"
    echo "   (useful when multiple clusters share the same S3 bucket)"
    echo ""
    read -p "Cluster name [default: ${detected_cluster}]: " cluster_name
    VELERO_CLUSTER_NAME=${cluster_name:-$detected_cluster}
    
    echo ""
    echo -e "${GREEN}✅ Velero: Schedule enabled${NC}"
    echo -e "   • Cluster name: ${VELERO_CLUSTER_NAME}"
    echo -e "   • Backup prefix: ${VELERO_CLUSTER_NAME}-backup-*"
    echo -e "   • Schedule: ${VELERO_SCHEDULE}"
    echo -e "   • Retention: ${VELERO_TTL}"
  else
    ENABLE_VELERO="false"
    VELERO_CLUSTER_NAME=""
    echo -e "${YELLOW}⏭️  Velero: disabled${NC}"
  fi
}

# Configure Velero (non-interactive, from config file)
configure_velero_non_interactive() {
  ENABLE_VELERO=$(read_yaml_value "$CONFIG_FILE_PATH" ".velero.enabled" "false")
  if [[ "$ENABLE_VELERO" == "true" ]]; then
    VELERO_NAMESPACE=$(read_yaml_value "$CONFIG_FILE_PATH" ".velero.namespace" "velero")
    VELERO_SCHEDULE=$(read_yaml_value "$CONFIG_FILE_PATH" ".velero.backup.schedule" "0 2 * * *")
    VELERO_TTL=$(read_yaml_value "$CONFIG_FILE_PATH" ".velero.backup.ttl" "720h0m0s")
    
    # Read cluster name from config, fallback to auto-detection
    VELERO_CLUSTER_NAME=$(read_yaml_value "$CONFIG_FILE_PATH" ".velero.clusterName" "")
    if [[ -z "$VELERO_CLUSTER_NAME" ]]; then
      VELERO_CLUSTER_NAME=$(detect_cluster_name)
    fi
    
    echo -e "${GREEN}🛡️  Velero: Schedule imported from configuration file${NC}"
    echo -e "   • Cluster: ${VELERO_CLUSTER_NAME}, Backup prefix: ${VELERO_CLUSTER_NAME}-backup-*"
  else
    VELERO_CLUSTER_NAME=""
    echo -e "${YELLOW}🛡️  Velero: disabled in configuration file${NC}"
  fi
}
