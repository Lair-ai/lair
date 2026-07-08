#!/bin/bash

# ============================================================================
# DEPLOYMENT.SH - Helm Deployment Functions
# ============================================================================

# Function to let user choose helm command
choose_helm_command() {
  local interactive_mode=${1:-true}  # Default to interactive
  
  # Only ask if both are available and in interactive mode
  if [ "$HELM_STANDARD_AVAILABLE" = true ] && [ "$HELM_MICROK8S_AVAILABLE" = true ] && [ "$interactive_mode" = true ]; then
    echo ""
    echo -e "${BLUE}🛠️  Helm Command Selection${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Multiple Helm installations detected. Which would you like to use?"
    echo ""
    echo "  1) 🏗️  Standard Helm (helm) [RECOMMENDED]"
    echo "     • Better compatibility and performance"
    echo "     • Stable and well-tested"
    echo "     • Resolves most deployment issues"
    echo "     • Industry standard"
    echo ""
    echo "  2) 🔧 MicroK8s Helm3 (microk8s helm3)"
    echo "     • Integrated with MicroK8s"
    echo "     • May encounter snap/permission issues"
    echo "     • Can have timeouts with complex charts"
    echo "     • Use only if standard helm is unavailable"
    echo ""
    
    while true; do
      read -p "Select Helm command (1-2) [default: 1]: " helm_choice
      helm_choice=${helm_choice:-1}
      
      case $helm_choice in
        1)
          HELM_CMD="helm"
          echo -e "${GREEN}✅ Using standard helm${NC}"
          break
          ;;
        2)
          HELM_CMD="microk8s helm3"
          echo -e "${YELLOW}⚠️  Using microk8s helm3${NC}"
          echo -e "${YELLOW}   Note: If you encounter issues, try option 1 (standard helm)${NC}"
          break
          ;;
        *)
          echo -e "${RED}❌ Invalid choice. Please select 1 or 2.${NC}"
          ;;
      esac
    done
    
    echo ""
    echo -e "${BLUE}Selected Helm command: $HELM_CMD${NC}"
    echo ""
  else
    echo ""
    echo -e "${BLUE}🔍 Helm Command: $HELM_CMD${NC}"
    echo "(Only one helm installation available)"
    echo ""
  fi
}

# Function to handle problematic upgrades by removing conflicting resources
handle_upgrade_conflicts() {
  local namespace=$1
  local release_name=$2
  
  echo -e "${YELLOW}🔧 Detecting and resolving upgrade conflicts...${NC}"
  
  # Check if this is an existing release
  if ! $HELM_CMD ls -n "$namespace" 2>/dev/null | grep -q "$release_name"; then
    echo "✅ No existing release found, no conflicts to resolve"
    return 0
  fi
  
  local conflicts_found=false
  
  # Check for StatefulSet conflicts (Ollama and Postgres)
  echo "🔍 Checking for StatefulSet conflicts..."
  for sts in "ollama" "n8n-postgres"; do
    if $KUBECTL_CMD get statefulset "$sts" -n "$namespace" &>/dev/null; then
      echo "⚠️  Found StatefulSet: $sts"
      conflicts_found=true
    fi
  done
  
  # Check for PVC size conflicts
  echo "🔍 Checking for PVC size conflicts..."
  local pvc_conflicts=()
  for pvc_name in "n8n-pvc" "openwebui-pvc" "ollama-pvc-0" "postgres-data-n8n-postgres-0"; do
    if $KUBECTL_CMD get pvc "$pvc_name" -n "$namespace" &>/dev/null 2>&1; then
      echo "⚠️  Found PVC: $pvc_name"
      pvc_conflicts+=("$pvc_name")
      conflicts_found=true
    fi
  done
  
  if [ "$conflicts_found" = "false" ]; then
    echo "✅ No upgrade conflicts detected"
    return 0
  fi
  
  echo ""
  echo -e "${YELLOW}🚨 UPGRADE CONFLICTS DETECTED${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "The following Kubernetes resources need to be recreated for the upgrade:"
  echo ""
  echo -e "${RED}StatefulSets (cannot modify certain fields):${NC}"
  echo "  • ollama (if exists)"
  echo "  • n8n-postgres (if exists)"
  echo ""
  echo -e "${YELLOW}PersistentVolumeClaims (potential storage conflicts):${NC}"
  for pvc in "${pvc_conflicts[@]}"; do
    echo "  • $pvc"
  done
  echo ""
  echo -e "${BLUE}📊 What this means:${NC}"
  echo "  • StatefulSets will be recreated (pods will restart)"
  echo "  • PVCs will be left UNTOUCHED (data preserved)"
  echo "  • If storage size conflicts exist, you may need to manually resolve them"
  echo "  • Services will experience brief downtime during StatefulSet recreation"
  echo ""
  echo -e "${GREEN}✅ This is a safe operation - NO DATA WILL BE LOST${NC}"
  echo ""
  
  read -p "Do you want to automatically resolve StatefulSet conflicts? (y/n) [default: y]: " resolve_conflicts
  resolve_conflicts=${resolve_conflicts:-y}
  
  if [[ "$resolve_conflicts" != "y" && "$resolve_conflicts" != "Y" ]]; then
    echo "❌ Upgrade cancelled by user"
    return 1
  fi
  
  echo ""
  echo -e "${BLUE}🔧 Resolving StatefulSet conflicts (preserving all data)...${NC}"
  
  # Delete StatefulSets (this will not delete their PVCs)
  echo "🗑️  Deleting StatefulSets (PVCs will be preserved)..."
  for sts in "ollama" "n8n-postgres"; do
    if $KUBECTL_CMD get statefulset "$sts" -n "$namespace" &>/dev/null; then
      echo "  • Deleting StatefulSet: $sts"
      $KUBECTL_CMD delete statefulset "$sts" -n "$namespace" --cascade=orphan
    fi
  done
  
  # NEVER DELETE PVCs - they contain user data!
  echo ""
  echo -e "${GREEN}💾 All PVCs preserved - no data loss${NC}"
  if [ ${#pvc_conflicts[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  Note: Some PVCs may have storage size conflicts:${NC}"
    for pvc_name in "${pvc_conflicts[@]}"; do
      current_size=$($KUBECTL_CMD get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.status.capacity.storage}' 2>/dev/null || echo "unknown")
      echo "    • $pvc_name (current: $current_size)"
    done
    echo ""
    echo -e "${BLUE}📋 If the upgrade fails due to storage size:${NC}"
    echo "  • Increase storage size in your configuration"
    echo "  • Or manually edit PVC if supported by your storage class"
    echo "  • Kubernetes prevents reducing PVC size for data safety"
  fi
  
  # Wait a moment for resources to be fully deleted
  echo ""
  echo "⏳ Waiting for StatefulSets to be fully cleaned up..."
  sleep 5
  
  echo ""
  echo -e "${GREEN}✅ StatefulSet conflicts resolved safely${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  return 0
}

# Proper implementation of run_helm_with_fallback
run_helm_with_fallback() { 
  local cmd=$1
  local release=$2
  local namespace=$3
  local config_file=$4
  local use_create_namespace=${5:-true}  # Default to true
  
  # Always use `upgrade --install` so the same command works for both new installs and upgrades.
  # NOTE: Do NOT pass `-f values.yaml` explicitly: Helm already loads the chart's `values.yaml` by default.
  local helm_cmd="$HELM_CMD upgrade --install $release . -n $namespace -f $config_file"
  
  # `upgrade --install` supports --create-namespace (Helm v3)
  if [[ "$use_create_namespace" == "true" ]]; then
    helm_cmd="$helm_cmd --create-namespace"
  fi
  
  # Handle upgrade conflicts automatically (only does something if the release already exists)
  if ! handle_upgrade_conflicts "$namespace" "$release"; then
    echo -e "${RED}❌ Could not resolve upgrade conflicts${NC}"
    return 1
  fi
  
  echo "Executing: $helm_cmd"
  
  # Execute the command
  if $helm_cmd; then
    echo -e "${GREEN}✅ Helm deployment completed successfully${NC}"
    return 0
  else
    echo -e "${RED}❌ Helm deployment failed${NC}"
    
    # If upgrade failed, offer additional recovery options
    if [[ "$cmd" == "upgrade" ]]; then
      echo ""
      echo -e "${YELLOW}🔧 Upgrade failed. Additional recovery options:${NC}"
      echo ""
      read -p "Do you want to try a full reinstall? (y/n) [default: n]: " try_reinstall
      try_reinstall=${try_reinstall:-n}
      
      if [[ "$try_reinstall" == "y" || "$try_reinstall" == "Y" ]]; then
        echo ""
        echo -e "${BLUE}🔄 Attempting full reinstall...${NC}"
        
        # Uninstall the release
        echo "🗑️  Uninstalling existing release..."
        $HELM_CMD uninstall "$release" -n "$namespace" || true
        
        # Wait for cleanup
        echo "⏳ Waiting for cleanup..."
        sleep 10
        
        # Delete any remaining PVCs if user wants
        echo ""
        read -p "Do you want to delete all PVCs (THIS WILL DELETE ALL DATA)? (y/n) [default: n]: " delete_pvcs
        delete_pvcs=${delete_pvcs:-n}
        
        if [[ "$delete_pvcs" == "y" || "$delete_pvcs" == "Y" ]]; then
          echo "🗑️  Deleting all PVCs..."
          $KUBECTL_CMD delete pvc --all -n "$namespace" || true
          sleep 5
        fi
        
        # Attempt reinstall
        echo "🚀 Attempting fresh installation..."
        local install_cmd="$HELM_CMD upgrade --install $release . -n $namespace -f $config_file --create-namespace"
        echo "Executing: $install_cmd"
        
        if $install_cmd; then
          echo -e "${GREEN}✅ Fresh installation completed successfully${NC}"
          return 0
        else
          echo -e "${RED}❌ Fresh installation also failed${NC}"
          return 1
        fi
      fi
    fi
    
    return 1
  fi
}

# Proper implementation of verify_and_prepare_namespace
verify_and_prepare_namespace() {
  local namespace=$1
  local release_name=$2
  echo -e "${BLUE}Thoroughly verifying namespace '$namespace'...${NC}"
  
  # Rigorous verification: check if namespace already exists
  if $KUBECTL_CMD get namespace "$namespace" &>/dev/null; then
    echo -e "${YELLOW}Namespace '$namespace' already exists.${NC}"
    
    # Check if it's already labeled for Helm
    local has_helm_label=$($KUBECTL_CMD get namespace "$namespace" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null)
    
    # If it doesn't have Helm label, add it
    if [ "$has_helm_label" != "Helm" ]; then
      echo -e "${YELLOW}Namespace exists but doesn't have Helm labels. Adding necessary labels...${NC}"
      
      # Create a temporary file with JSON patch
      cat > temp_ns_patch.json <<-EOF
{
  "metadata": {
    "labels": {
      "app.kubernetes.io/managed-by": "Helm"
    },
    "annotations": {
      "meta.helm.sh/release-name": "$release_name",
      "meta.helm.sh/release-namespace": "$namespace"
    }
  }
}
EOF
      
      # Apply the patch
      if ! $KUBECTL_CMD patch namespace "$namespace" --patch-file temp_ns_patch.json; then
        echo -e "${RED}Unable to add Helm labels to namespace.${NC}"
        rm temp_ns_patch.json
        return 1
      fi
      
      # Remove temporary file
      rm temp_ns_patch.json
      echo -e "${GREEN}Helm labels added to namespace successfully.${NC}"
    else
      echo -e "${GREEN}Namespace already has Helm labels.${NC}"
    fi
    
    return 0
  fi
  
  # Namespace doesn't exist, let's see if it's in termination or creation state
  echo -e "${BLUE}Namespace '$namespace' doesn't exist, checking if it's being created or terminated...${NC}"
  
  # Check that there are no namespaces with the same name in termination
  if $KUBECTL_CMD get namespace "$namespace" -o json 2>/dev/null | grep -q "Terminating"; then
    echo -e "${RED}Namespace '$namespace' exists but is being terminated.${NC}"
    echo "Wait for the namespace to be completely removed before proceeding."
    
    # Option to force removal
    read -p "Do you want to try to force removal of the terminating namespace? (y/n): " FORCE_DELETE
    if [[ "$FORCE_DELETE" == "y" || "$FORCE_DELETE" == "Y" ]]; then
      echo -e "${YELLOW}Attempting to force namespace removal...${NC}"
      $KUBECTL_CMD get namespace "$namespace" -o json | sed 's/"kubernetes"//' | jq '.spec.finalizers = []' > temp_ns.json
      $KUBECTL_CMD replace --raw "/api/v1/namespaces/$namespace/finalize" -f temp_ns.json || true
      rm temp_ns.json
      
      # Wait up to 30 seconds for removal
      echo "Waiting for namespace removal..."
      for i in {1..30}; do
        if ! $KUBECTL_CMD get namespace "$namespace" &>/dev/null; then
          echo -e "${GREEN}Namespace removed successfully.${NC}"
          break
        fi
        echo -n "."
        sleep 1
      done
      
      # Final verification
      if $KUBECTL_CMD get namespace "$namespace" &>/dev/null; then
        echo -e "${RED}Unable to remove namespace. Consider using another name.${NC}"
        return 1
      fi
    else
      return 1
    fi
  fi
  
  # At this point, we're sure the namespace doesn't exist, let's create it explicitly with Helm labels
  echo -e "${BLUE}Explicitly creating namespace '$namespace' with Helm labels...${NC}"
  
  # Create a temporary YAML file for the namespace with Helm labels
  cat > temp_namespace.yaml <<-EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: $release_name
    meta.helm.sh/release-namespace: $namespace
EOF
  
  # Create the namespace with Helm labels
  if ! $KUBECTL_CMD apply -f temp_namespace.yaml; then
    # If creation fails, it might be because another process created it in the meantime
    if $KUBECTL_CMD get namespace "$namespace" &>/dev/null; then
      echo -e "${YELLOW}Namespace was created by another process in the meantime.${NC}"
      
      # Let's check if it has Helm labels
      local has_helm_label=$($KUBECTL_CMD get namespace "$namespace" -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null)
      
      # If it doesn't have Helm label, add it
      if [ "$has_helm_label" != "Helm" ]; then
        echo -e "${YELLOW}Namespace doesn't have Helm labels. Adding necessary labels...${NC}"
        
        # Apply the patch
        $KUBECTL_CMD patch namespace "$namespace" --patch-file temp_namespace.yaml || true
      fi
      
      rm temp_namespace.yaml
      return 0
    else
      echo -e "${RED}Error creating namespace '$namespace'.${NC}"
      rm temp_namespace.yaml
      return 1
    fi
  fi
  
  rm temp_namespace.yaml
  echo -e "${GREEN}Namespace '$namespace' created successfully with Helm labels.${NC}"
  sleep 2  # Brief pause to ensure namespace is fully registered
  return 0
}

# Helper function for Helm deployment
execute_helm_deployment() {
  echo "Proceeding with installation"
  
  # Let user choose which helm to use
  choose_helm_command false
  
  # Use fixed release name without prompting
  RELEASE_NAME=${RELEASE_NAME:-lair}
  echo "Using release name: $RELEASE_NAME"
  
  # Auto-detect install vs upgrade (no prompt)
  if $HELM_CMD ls -n "$NAMESPACE" 2>/dev/null | grep -q "^$RELEASE_NAME\b"; then
    NEW_INSTALL="n"
  else
    NEW_INSTALL="y"
  fi
  
  if [[ "$NEW_INSTALL" == "y" || "$NEW_INSTALL" == "Y" ]]; then
    echo "Installing Lair with Helm..."
    
    # Verify namespace and release status
    if ! verify_and_prepare_namespace "$NAMESPACE" "$RELEASE_NAME"; then
      echo "Installation cancelled due to namespace issues."
      exit 1
    fi
    
      # At this point the namespace should already exist (created by verify_and_prepare_namespace)
      echo -e "${GREEN}Proceeding with installation in prepared namespace${NC}"
      if ! ensure_n8n_postgres_secret "$NAMESPACE" "$RELEASE_NAME"; then
        echo "Unable to prepare PostgreSQL Secret."
        exit 1
      fi
      run_helm_with_fallback "install" "$RELEASE_NAME" "$NAMESPACE" "$CONFIG_FILE" false || {
        echo "Installation failed."
        exit 1
      }
  else
    echo "Upgrading Lair with Helm..."
    if ! ensure_n8n_postgres_secret "$NAMESPACE" "$RELEASE_NAME"; then
      echo "Unable to prepare PostgreSQL Secret."
      exit 1
    fi
    run_helm_with_fallback "upgrade" "$RELEASE_NAME" "$NAMESPACE" "$CONFIG_FILE" false || {
      echo "Upgrade failed."
      exit 1
    }
  fi
  
  # Add monitoring suggestion after successful deployment
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${GREEN}🎉 Deployment completed! Services are starting up...${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo -e "${BLUE}📊 Monitor the startup process with:${NC}"
  echo ""
  echo -e "${YELLOW}   watch -n 10 kubectl get all -n $NAMESPACE${NC}"
  echo ""
  echo "This command will:"
  echo "  • Refresh every 10 seconds"
  echo "  • Show all pods, services, and deployments"
  echo "  • Help you track when everything is 'Running' and 'Ready'"
  echo ""
  echo -e "${BLUE}Quick status checks:${NC}"
  echo -e "  • Check pods: ${YELLOW}$KUBECTL_CMD get pods -n $NAMESPACE${NC}"
  echo -e "  • Check ingress: ${YELLOW}$KUBECTL_CMD get ingress -n $NAMESPACE${NC}"
  echo -e "  • Check certificates: ${YELLOW}$KUBECTL_CMD get certificates -n $NAMESPACE${NC}"
  echo ""
  echo -e "${GREEN}Expected startup time: 2-5 minutes for all services to be ready${NC}"
  echo ""
  echo "Press Ctrl+C to exit the watch command when all pods show 'Running' status."
}
