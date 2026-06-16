#!/bin/bash

# ============================================================================
# PHASES.SH - Main Execution Phases
# ============================================================================

# PHASE 1: System Detection and Resource Planning
execute_system_detection_phase() {
  echo ""
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo -e "${BLUE}🔍 PHASE 1: SYSTEM DETECTION & RESOURCE PLANNING${NC}"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""

  if [ "$USE_CONFIG_FILE" = "true" ]; then
    echo -e "${GREEN}📋 Using configuration from file - Detection method: $DETECTION_CHOICE${NC}"
    # Automatically execute detection based on config file
    if [ "$DETECTION_CHOICE" = "1" ]; then
      echo "Using local system detection..."
      DETECTION_CHOICE="1"
    else
      echo "Using Kubernetes cluster detection..."
      DETECTION_CHOICE="2"
    fi
  fi

  # Automatically detect system resources
  detect_system_resources
  detect_cluster_storage
  
  # Detect public IP address
  detect_public_ip

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${GREEN}📋 RESOURCE SUMMARY${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Guaranteed minimum resources (${K8S_RESOURCE_ALLOCATION_PERCENTAGE}% reserved for applications):"
  echo "  • CPU: $K8S_CPU cores (from $TOTAL_CPU total)"
  echo "  • RAM: $((K8S_MEMORY_MB/1024)) GB (from $(echo "scale=1; $TOTAL_MEMORY_MB/1024" | bc) GB total)"
  echo "  • Storage: $CLUSTER_AVAILABLE_STORAGE_GB GB (${STORAGE_SAFETY_PERCENTAGE}% of available)"
  echo "  • GPU: $(if [[ "$HAS_GPU" == "y" ]]; then echo "✅ Available"; else echo "❌ Not detected"; fi)"
  echo ""
  echo -e "${BLUE}💡 With overcommitment strategy: Apps can burst beyond these minimums using idle resources${NC}"

  if [ "$USE_CONFIG_FILE" = "true" ]; then
    if [ "$USE_DETECTED_RESOURCES" = "true" ]; then
      echo "✅ Using auto-detected resources (from config file)"
    else
      echo "⚙️  Using manual resource configuration (from config file)"
      # Load manual values from config if specified
      K8S_CPU=$(read_yaml_value "$CONFIG_FILE_PATH" ".manual_resources.cpu_cores" "$K8S_CPU")
      K8S_MEMORY_GB=$(read_yaml_value "$CONFIG_FILE_PATH" ".manual_resources.memory_gb" "$((K8S_MEMORY_MB/1024))")
      K8S_MEMORY_MB=$(echo "$K8S_MEMORY_GB * 1024" | bc | awk '{print int($1)}')
      CLUSTER_AVAILABLE_STORAGE_GB=$(read_yaml_value "$CONFIG_FILE_PATH" ".manual_resources.storage_gb" "$CLUSTER_AVAILABLE_STORAGE_GB")
      echo "Updated resources from config:"
      echo "  • CPU: $K8S_CPU cores"
      echo "  • RAM: $K8S_MEMORY_GB GB"
      echo "  • Storage: $CLUSTER_AVAILABLE_STORAGE_GB GB"
      echo "  • GPU: $(if [[ "$HAS_GPU" == "y" ]]; then echo "✅ Available"; else echo "❌ Not detected"; fi)"
    fi
  else
    read -p "Use these detected resources? (y/n) [default: y]: " USE_DETECTED_RESOURCES
    USE_DETECTED_RESOURCES=${USE_DETECTED_RESOURCES:-y}

    if [[ "$USE_DETECTED_RESOURCES" != "y" && "$USE_DETECTED_RESOURCES" != "Y" ]]; then
      echo "Manual resource configuration:"
      
      # Calculate reference values
      TOTAL_CPU_DETECTED=$TOTAL_CPU
      TOTAL_MEMORY_GB_DETECTED=$(echo "scale=1; $TOTAL_MEMORY_MB/1024" | bc)
      K8S_CPU_RECOMMENDED=$(echo "scale=1; $TOTAL_CPU * 0.8" | bc)
      K8S_MEMORY_GB_RECOMMENDED=$(echo "scale=1; $TOTAL_MEMORY_MB * 0.8 / 1024" | bc)
      STORAGE_GB_RECOMMENDED=$USABLE_STORAGE_GB
      STORAGE_GB_DETECTED=$AVAILABLE_STORAGE_GB
      
      # CPU input with validation
      read -p "CPU cores available for Kubernetes (max detected: ${TOTAL_CPU_DETECTED}, recommended max: ${K8S_CPU_RECOMMENDED}): " K8S_CPU_INPUT
      if [ -z "$K8S_CPU_INPUT" ] || ! [[ "$K8S_CPU_INPUT" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "⚠️  Using recommended CPU value: ${K8S_CPU_RECOMMENDED}"
        K8S_CPU="$K8S_CPU_RECOMMENDED"
      else
        K8S_CPU="$K8S_CPU_INPUT"
      fi
      
      # RAM input with validation
      read -p "RAM available for Kubernetes in GB (max detected: ${TOTAL_MEMORY_GB_DETECTED}, recommended max: ${K8S_MEMORY_GB_RECOMMENDED}): " K8S_MEMORY_GB_INPUT
      if [ -z "$K8S_MEMORY_GB_INPUT" ] || ! [[ "$K8S_MEMORY_GB_INPUT" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "⚠️  Using recommended RAM value: ${K8S_MEMORY_GB_RECOMMENDED}GB"
        K8S_MEMORY_GB_INPUT="$K8S_MEMORY_GB_RECOMMENDED"
      fi
      K8S_MEMORY_MB=$(echo "$K8S_MEMORY_GB_INPUT * 1024" | bc | awk '{print int($1)}')
      
      # Storage input with validation
      read -p "Storage available for Lair in GB (max detected: ${STORAGE_GB_DETECTED}, recommended max: ${STORAGE_GB_RECOMMENDED}): " CLUSTER_STORAGE_INPUT
      if [ -z "$CLUSTER_STORAGE_INPUT" ] || ! [[ "$CLUSTER_STORAGE_INPUT" =~ ^[0-9]+$ ]]; then
        echo "⚠️  Using recommended storage value: ${STORAGE_GB_RECOMMENDED}GB"
        CLUSTER_AVAILABLE_STORAGE_GB="$STORAGE_GB_RECOMMENDED"
      else
        CLUSTER_AVAILABLE_STORAGE_GB="$CLUSTER_STORAGE_INPUT"
      fi
      
      echo ""
      echo -e "${GREEN}✅ Updated Resource Configuration:${NC}"
      echo "  • CPU: $K8S_CPU cores"
      echo "  • RAM: $(echo "scale=1; $K8S_MEMORY_MB/1024" | bc) GB"
      echo "  • Storage: $CLUSTER_AVAILABLE_STORAGE_GB GB"
      echo "  • GPU: $(if [[ "$HAS_GPU" == "y" ]]; then echo "✅ Available"; else echo "❌ Not detected"; fi)"
    fi
  fi

  # Auto-calculate resource allocations based on detected/configured resources
  echo ""
  echo -e "${YELLOW}⚙️  Calculating optimal resource allocations...${NC}"
  prompt_and_calculate_resource_allocations
}

# PHASE 2: Platform and Application Configuration
execute_application_configuration_phase() {
  echo ""
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo -e "${BLUE}🏁 PHASE 2: PLATFORM & APPLICATION CONFIGURATION${NC}"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""

  # Configuration name and file setup
  echo -e "${GREEN}📁 Configuration Setup${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [ "$USE_CONFIG_FILE" = "true" ]; then
    echo "✅ Using configuration name from file: $CONFIG_NAME"
  else
    read -p "Configuration name (for filename): " CONFIG_NAME
  fi
  
  CONFIG_FILE="values-${CONFIG_NAME}.yaml"

  # Check if file already exists
  if [ -f "$CONFIG_FILE" ] && [ "$USE_CONFIG_FILE" = "false" ]; then
    read -p "File $CONFIG_FILE already exists. Overwrite? (y/n): " OVERWRITE
    if [[ "$OVERWRITE" != "y" && "$OVERWRITE" != "Y" ]]; then
      echo "Aborted."
      exit 1
    fi
  elif [ -f "$CONFIG_FILE" ] && [ "$USE_CONFIG_FILE" = "true" ]; then
    echo "⚠️  File $CONFIG_FILE already exists, will be overwritten"
  fi

  # Platform Detection (Jetson vs Standard)
  echo ""
  echo -e "${GREEN}🔧 Platform Detection${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  if [ "$USE_CONFIG_FILE" = "true" ]; then
    echo "✅ Platform from config: $PLATFORM_TYPE (Jetson: $IS_JETSON)"
  else
    read -p "Is this installation for NVIDIA Jetson? (y/n) [default: y]: " IS_JETSON
    IS_JETSON=${IS_JETSON:-y}
  fi

  if [[ "$IS_JETSON" == "y" || "$IS_JETSON" == "Y" ]]; then
    PLATFORM_TYPE="jetson"
    HAS_GPU="y"  # Jetson always has GPU
    echo "✅ Jetson platform detected - GPU enabled by default"
    echo "⚠️  Using microk8s hostpath provisioner (Longhorn not recommended for Jetson)"
  else
    PLATFORM_TYPE="standard"
    echo "✅ Standard platform detected"
    
    # Show GPU detection results from Phase 1
    echo ""
    echo -e "${YELLOW}🎮 GPU Configuration${NC}"
    echo "─────────────────────────────────────────────────────────────────────────────"
    
    if [ "$USE_CONFIG_FILE" = "true" ]; then
      echo "✅ GPU setting from config: $(if [[ "$HAS_GPU" == "y" ]]; then echo "Yes"; else echo "No"; fi)"
    else
      # GPU was already detected in Phase 1, just show the result
      echo "✅ GPU detection completed in Phase 1: $(if [[ "$HAS_GPU" == "y" ]]; then echo "Yes"; else echo "No"; fi)"
      
      # If no GPU was detected, simply accept it and proceed with CPU-only mode
      if [[ "$HAS_GPU" != "y" ]]; then
        echo "   No GPU detected - proceeding with CPU-only configuration"
      fi
    fi
    
    if [[ "$HAS_GPU" == "y" || "$HAS_GPU" == "Y" ]]; then
      echo "✅ GPU enabled for AI workloads"
    else
      echo "ℹ️  CPU-only configuration"
    fi
  fi

  # Platform Summary
  echo ""
  echo -e "${GREEN}📋 Platform Summary${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  • Platform: $PLATFORM_TYPE"
  echo "  • GPU: $(if [[ "$HAS_GPU" == "y" || "$HAS_GPU" == "Y" ]]; then echo "Yes"; else echo "No"; fi)"
  echo "  • Resources: $K8S_CPU cores, $((K8S_MEMORY_MB/1024)) GB RAM, $CLUSTER_AVAILABLE_STORAGE_GB GB storage"

  # Execute component configuration functions with new structure
  if [ "$USE_CONFIG_FILE" = "true" ]; then
    echo ""
    echo -e "${GREEN}⚡ Using automatic configuration from file${NC}"
    configure_access_mode_and_email_non_interactive
    configure_all_components_non_interactive
  else
    configure_access_mode_and_email
    configure_all_components
  fi
}

# PHASE 3: Infrastructure and Deployment Setup
execute_infrastructure_setup_phase() {
  echo ""
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo -e "${BLUE}📁 PHASE 3: INFRASTRUCTURE & DEPLOYMENT SETUP${NC}"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  
  # Fixed namespace - no question needed
  NAMESPACE="lair"
  echo -e "${GREEN}📁 Namespace Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✅ Using fixed namespace: $NAMESPACE"

  # Storage Class Configuration (automatic based on platform)
  echo ""
  echo -e "${GREEN}💾 Storage Class Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Safety check: ensure IS_JETSON is defined
  IS_JETSON=${IS_JETSON:-"n"}

  if [ "$IS_JETSON" = "y" ]; then
    echo "🔧 Jetson platform: Configuring hostpath storage automatically"
    echo "   ⚠️  Longhorn not recommended for Jetson - using microk8s hostpath provisioner"
    CREATE_STORAGE_CLASS_ENABLED=true
    STORAGE_CLASS_NAME="lair-hostpath"
    echo "✅ StorageClass: $STORAGE_CLASS_NAME (hostpath-based for Jetson)"
  else
    echo "🔧 Standard platform: Configuring Longhorn storage automatically"
    echo "   📦 Longhorn provides distributed block storage for high availability"
    CREATE_STORAGE_CLASS_ENABLED=true
    STORAGE_CLASS_NAME="lair-storage"
    echo "✅ StorageClass: $STORAGE_CLASS_NAME (Longhorn-based for standard platforms)"
  fi

  # Cert-Manager Configuration (automatic)
  echo ""
  echo -e "${GREEN}🔐 Certificate Management Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔧 Automatically configuring cert-manager with Let's Encrypt:"
  echo "   • ClusterIssuer: lair-letsencrypt (will be created)"
  echo "   • Email: $CERT_EMAIL"
  echo "   • TLS certificates will be automatically generated for all domains"
  echo "✅ Certificate management configured automatically"

  # Ingress Configuration (automatic)
  echo ""
  echo -e "${GREEN}🌐 Ingress Configuration${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔧 Automatically configuring NGINX Ingress with TLS:"
  echo "   • OpenWebUI: https://$OPENWEBUI_DOMAIN"
  echo "   • N8N: https://$N8N_DOMAIN" 
  
  # Show ComfyUI domain only if enabled
  if [[ "$COMFYUI_ENABLED" == true && "$ENABLE_COMFYUI" == "y" ]] && [ -n "$COMFYUI_DOMAIN" ] && [ "$COMFYUI_DOMAIN" != "" ]; then
    echo "   • ComfyUI: https://$COMFYUI_DOMAIN"
  fi
  
  # Show MinIO and Ollama domains if enabled
  if [[ "$MINIO_ENABLED" == true && "$ENABLE_MINIO" == "y" ]] && [ -n "$MINIO_DOMAIN" ] && [ "$MINIO_DOMAIN" != "" ]; then
    echo "   • MinIO Storage: https://$MINIO_DOMAIN"
  fi
  if [ -n "$OLLAMA_DOMAIN" ] && [ "$OLLAMA_DOMAIN" != "" ]; then
    echo "   • Ollama API: https://$OLLAMA_DOMAIN"
  fi
  echo ""
  
  # Show access mode and Let's Encrypt status
  echo "🔐 Access Mode: $ACCESS_MODE"
  if [ "$ACCESS_MODE" = "lan" ]; then
    echo "   ℹ️  Let's Encrypt: Disabled (suitable for .local domains)"
    echo "   📋 Use local DNS resolution or configure DNS server for .local domains"
  else
    echo "   ✅ Let's Encrypt: Enabled (automatic TLS certificates for public domains)"
    echo "   📋 Ensure domains point to your Kubernetes cluster's external IP"
  fi
  echo ""
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Start building config file with basic infrastructure
  echo "# values-${CONFIG_NAME}.yaml" > $CONFIG_FILE
  cat <<-EOF >> $CONFIG_FILE
namespace: $NAMESPACE

createStorageClass: $CREATE_STORAGE_CLASS_ENABLED
global:
  storageClass: "$STORAGE_CLASS_NAME"
  platform: "$PLATFORM_TYPE"

longhorn:
  kubeletRootDir: "/var/snap/microk8s/common/var/lib/kubelet"
  numberOfReplicas: $LONGHORN_REPLICAS_COUNT  # Auto-calculated based on cluster nodes ($NODES_COUNT nodes detected)

EOF
}

# PHASE 4: Configuration File Generation and Deployment
execute_configuration_generation_phase() {
  echo ""
  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo -e "${BLUE}📝 PHASE 4: CONFIGURATION FILE GENERATION${NC}"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  echo -e "${GREEN}📝 Generating configuration file...${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Generate the complete YAML configuration
  generate_complete_yaml_configuration

  echo ""
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo -e "${GREEN}🎉 CONFIGURATION COMPLETED SUCCESSFULLY!${NC}"
  echo "════════════════════════════════════════════════════════════════════════════════"
  echo ""
  echo "Configuration file $CONFIG_FILE has been created"
  echo ""
  echo "📊 Resource Allocation Summary:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Extract storage values from _SIZE variables if _GB variables are not set
  if [ -z "$OPENWEBUI_STORAGE_GB" ] && [ -n "$OPENWEBUI_STORAGE_SIZE" ]; then
    OPENWEBUI_STORAGE_GB=$(echo "$OPENWEBUI_STORAGE_SIZE" | sed 's/Gi//')
  fi
  if [ -z "$OLLAMA_STORAGE_GB" ] && [ -n "$OLLAMA_STORAGE_SIZE" ]; then
    OLLAMA_STORAGE_GB=$(echo "$OLLAMA_STORAGE_SIZE" | sed 's/Gi//')
  fi

  if [ -z "$N8N_STORAGE_GB" ] && [ -n "$N8N_STORAGE_SIZE" ]; then
    N8N_STORAGE_GB=$(echo "$N8N_STORAGE_SIZE" | sed 's/Gi//')
  fi
  if [ -z "$PG_STORAGE_GB" ] && [ -n "$PG_STORAGE_SIZE" ]; then
    PG_STORAGE_GB=$(echo "$PG_STORAGE_SIZE" | sed 's/Gi//')
  fi
  if [ -z "$REDIS_STORAGE_GB" ] && [ -n "$REDIS_STORAGE_SIZE" ]; then
    REDIS_STORAGE_GB=$(echo "$REDIS_STORAGE_SIZE" | sed 's/Gi//')
  fi
  if [ -z "$MINIO_STORAGE_GB" ] && [ -n "$MINIO_STORAGE_SIZE" ]; then
    MINIO_STORAGE_GB=$(echo "$MINIO_STORAGE_SIZE" | sed 's/Gi//')
  fi
  if [ -z "$COMFYUI_STORAGE_GB" ] && [ -n "$COMFYUI_STORAGE_SIZE" ]; then
    COMFYUI_STORAGE_GB=$(echo "$COMFYUI_STORAGE_SIZE" | sed 's/Gi//')
  fi
  
  # Set default values if still empty
  OPENWEBUI_STORAGE_GB=${OPENWEBUI_STORAGE_GB:-10}
  OLLAMA_STORAGE_GB=${OLLAMA_STORAGE_GB:-30}
  N8N_STORAGE_GB=${N8N_STORAGE_GB:-10}
  PG_STORAGE_GB=${PG_STORAGE_GB:-5}
  REDIS_STORAGE_GB=${REDIS_STORAGE_GB:-5}
  
  # Only set MinIO storage if it's enabled
  if [[ "$MINIO_ENABLED" == true && "$ENABLE_MINIO" == "y" ]]; then
    MINIO_STORAGE_GB=${MINIO_STORAGE_GB:-20}
  else
    MINIO_STORAGE_GB=0
  fi
  
  # Only set ComfyUI storage if it's enabled
  if [[ "$COMFYUI_ENABLED" == true && "$ENABLE_COMFYUI" == "y" ]]; then
    COMFYUI_STORAGE_GB=${COMFYUI_STORAGE_GB:-15}
  else
    COMFYUI_STORAGE_GB=0
  fi
  
  # Calculate total allocated resources (including N8N workers)
  # Build base resource calculations
  BASE_CPU=$((CPU_OPENWEBUI + CPU_OLLAMA + CPU_N8N + (CPU_N8N_WORKER * N8N_WORKER_REPLICAS) + CPU_POSTGRES + CPU_REDIS))
  BASE_MEMORY=$((MEM_OPENWEBUI + MEM_OLLAMA + MEM_N8N + (MEM_N8N_WORKER * N8N_WORKER_REPLICAS) + MEM_POSTGRES + MEM_REDIS))
  BASE_CPU_REQ=$((CPU_OPENWEBUI_REQ + CPU_OLLAMA_REQ + CPU_N8N_REQ + (CPU_N8N_WORKER_REQ * N8N_WORKER_REPLICAS) + CPU_POSTGRES_REQ + CPU_REDIS_REQ))
  BASE_MEMORY_REQ=$((MEM_OPENWEBUI_REQ + MEM_OLLAMA_REQ + MEM_N8N_REQ + (MEM_N8N_WORKER_REQ * N8N_WORKER_REPLICAS) + MEM_POSTGRES_REQ + MEM_REDIS_REQ))
  BASE_STORAGE=$((OPENWEBUI_STORAGE_GB + OLLAMA_STORAGE_GB + N8N_STORAGE_GB + PG_STORAGE_GB + REDIS_STORAGE_GB))
  
  # Add MinIO if enabled
  if [[ "$MINIO_ENABLED" == true && "$ENABLE_MINIO" == "y" ]]; then
    BASE_CPU=$((BASE_CPU + CPU_MINIO))
    BASE_MEMORY=$((BASE_MEMORY + MEM_MINIO))
    BASE_CPU_REQ=$((BASE_CPU_REQ + CPU_MINIO_REQ))
    BASE_MEMORY_REQ=$((BASE_MEMORY_REQ + MEM_MINIO_REQ))
    BASE_STORAGE=$((BASE_STORAGE + MINIO_STORAGE_GB))
  fi
  
  # Add ComfyUI if enabled
  if [[ "$COMFYUI_ENABLED" == true && "$ENABLE_COMFYUI" == "y" ]]; then
    TOTAL_ALLOCATED_CPU=$((BASE_CPU + CPU_COMFYUI))
    TOTAL_ALLOCATED_MEMORY=$((BASE_MEMORY + MEM_COMFYUI))
    TOTAL_ALLOCATED_CPU_REQ=$((BASE_CPU_REQ + CPU_COMFYUI_REQ))
    TOTAL_ALLOCATED_MEMORY_REQ=$((BASE_MEMORY_REQ + MEM_COMFYUI_REQ))
    TOTAL_ALLOCATED_STORAGE=$((BASE_STORAGE + COMFYUI_STORAGE_GB))
  else
    TOTAL_ALLOCATED_CPU=$BASE_CPU
    TOTAL_ALLOCATED_MEMORY=$BASE_MEMORY
    TOTAL_ALLOCATED_CPU_REQ=$BASE_CPU_REQ
    TOTAL_ALLOCATED_MEMORY_REQ=$BASE_MEMORY_REQ
    TOTAL_ALLOCATED_STORAGE=$BASE_STORAGE
  fi
  
  # Convert to readable units
  TOTAL_ALLOCATED_CPU_CORES=$(echo "scale=1; $TOTAL_ALLOCATED_CPU/1000" | bc)
  TOTAL_ALLOCATED_MEMORY_GB=$(echo "scale=1; $TOTAL_ALLOCATED_MEMORY/1024" | bc)
  TOTAL_ALLOCATED_CPU_REQ_CORES=$(echo "scale=1; $TOTAL_ALLOCATED_CPU_REQ/1000" | bc)
  TOTAL_ALLOCATED_MEMORY_REQ_GB=$(echo "scale=1; $TOTAL_ALLOCATED_MEMORY_REQ/1024" | bc)
  
  # Display resource table
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "Service" "CPU Req" "CPU Limit" "RAM Req" "RAM Limit" "Storage"
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "────────────────────" "────────────" "────────────" "────────────" "────────────" "────────────"
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "OpenWebUI" "$(echo "scale=1; $CPU_OPENWEBUI_REQ/1000" | bc)" "$(echo "scale=1; $CPU_OPENWEBUI/1000" | bc)" "$(echo "scale=1; $MEM_OPENWEBUI_REQ/1024" | bc)G" "$(echo "scale=1; $MEM_OPENWEBUI/1024" | bc)G" "${OPENWEBUI_STORAGE_GB}G"
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "Ollama" "$(echo "scale=1; $CPU_OLLAMA_REQ/1000" | bc)" "$(echo "scale=1; $CPU_OLLAMA/1000" | bc)" "$(echo "scale=1; $MEM_OLLAMA_REQ/1024" | bc)G" "$(echo "scale=1; $MEM_OLLAMA/1024" | bc)G" "${OLLAMA_STORAGE_GB}G"

  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "N8N" "$(echo "scale=1; $CPU_N8N_REQ/1000" | bc)" "$(echo "scale=1; $CPU_N8N/1000" | bc)" "$(echo "scale=1; $MEM_N8N_REQ/1024" | bc)G" "$(echo "scale=1; $MEM_N8N/1024" | bc)G" "${N8N_STORAGE_GB}G"
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "N8N Workers (x${N8N_WORKER_REPLICAS})" "$(echo "scale=1; $CPU_N8N_WORKER_REQ * $N8N_WORKER_REPLICAS/1000" | bc)" "$(echo "scale=1; $CPU_N8N_WORKER * $N8N_WORKER_REPLICAS/1000" | bc)" "$(echo "scale=1; $MEM_N8N_WORKER_REQ * $N8N_WORKER_REPLICAS/1024" | bc)G" "$(echo "scale=1; $MEM_N8N_WORKER * $N8N_WORKER_REPLICAS/1024" | bc)G" "-"
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "PostgreSQL" "$(echo "scale=1; $CPU_POSTGRES_REQ/1000" | bc)" "$(echo "scale=1; $CPU_POSTGRES/1000" | bc)" "$(echo "scale=1; $MEM_POSTGRES_REQ/1024" | bc)G" "$(echo "scale=1; $MEM_POSTGRES/1024" | bc)G" "${PG_STORAGE_GB}G"
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "Redis" "$(echo "scale=1; $CPU_REDIS_REQ/1000" | bc)" "$(echo "scale=1; $CPU_REDIS/1000" | bc)" "$(echo "scale=1; $MEM_REDIS_REQ/1024" | bc)G" "$(echo "scale=1; $MEM_REDIS/1024" | bc)G" "${REDIS_STORAGE_GB}G"
  # Only show MinIO if it's enabled
  if [[ "$MINIO_ENABLED" == true && "$ENABLE_MINIO" == "y" ]]; then
    printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "MinIO" "$(echo "scale=1; $CPU_MINIO_REQ/1000" | bc)" "$(echo "scale=1; $CPU_MINIO/1000" | bc)" "$(echo "scale=1; $MEM_MINIO_REQ/1024" | bc)G" "$(echo "scale=1; $MEM_MINIO/1024" | bc)G" "${MINIO_STORAGE_GB}G"
  fi
  # Only show ComfyUI if it's enabled
  if [[ "$COMFYUI_ENABLED" == true && "$ENABLE_COMFYUI" == "y" ]]; then
    printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "ComfyUI" "$(echo "scale=1; $CPU_COMFYUI_REQ/1000" | bc)" "$(echo "scale=1; $CPU_COMFYUI/1000" | bc)" "$(echo "scale=1; $MEM_COMFYUI_REQ/1024" | bc)G" "$(echo "scale=1; $MEM_COMFYUI/1024" | bc)G" "${COMFYUI_STORAGE_GB}G"
  fi
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "────────────────────" "────────────" "────────────" "────────────" "────────────" "────────────"
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "TOTAL ALLOCATED" "${TOTAL_ALLOCATED_CPU_REQ_CORES}" "${TOTAL_ALLOCATED_CPU_CORES}" "${TOTAL_ALLOCATED_MEMORY_REQ_GB}G" "${TOTAL_ALLOCATED_MEMORY_GB}G" "${TOTAL_ALLOCATED_STORAGE}G"
  # Calculate total available CPU requests (same as limits for simplicity)
  TOTAL_AVAILABLE_CPU_REQ=${K8S_CPU}
  TOTAL_AVAILABLE_MEMORY_REQ=${K8S_MEMORY_GB}
  
  printf "%-20s %-12s %-12s %-12s %-12s %-12s\n" "AVAILABLE SYSTEM" "${TOTAL_AVAILABLE_CPU_REQ}" "${K8S_CPU}" "${TOTAL_AVAILABLE_MEMORY_REQ}G" "${K8S_MEMORY_GB}G" "${USABLE_STORAGE_GB}G"
  
  echo ""
  echo "📍 Service Access Summary:"
  
  # Show Public IP information
  echo ""
  echo "   🌍 Network Information:"
  echo "      • Public IP: $PUBLIC_IP"
  echo ""
  
  # Show LAN access if enabled
  if [[ "$ENABLE_LAN_ACCESS" == "true" ]]; then
    echo "   🏠 LAN Access (.local domains):"
    echo "      • OpenWebUI: https://$OPENWEBUI_DOMAIN_LAN"
    echo "      • N8N: https://$N8N_DOMAIN_LAN"
    
    # Show LAN access for services with domains (only if enabled)
    if [[ "$COMFYUI_ENABLED" == true && "$ENABLE_COMFYUI" == "y" ]] && [ -n "$COMFYUI_DOMAIN_LAN" ] && [ "$COMFYUI_DOMAIN_LAN" != "" ]; then
      echo "      • ComfyUI: https://$COMFYUI_DOMAIN_LAN"
    fi
    if [[ "$MINIO_ENABLED" == true && "$ENABLE_MINIO" == "y" ]] && [ -n "$MINIO_DOMAIN_LAN" ] && [ "$MINIO_DOMAIN_LAN" != "" ]; then
      echo "      • MinIO Storage: https://$MINIO_DOMAIN_LAN"
    fi
    if [ -n "$OLLAMA_DOMAIN_LAN" ] && [ "$OLLAMA_DOMAIN_LAN" != "" ]; then
      echo "      • Ollama API: https://$OLLAMA_DOMAIN_LAN"
    fi
    echo ""
  fi
  
  # Show Public access if enabled
  if [[ "$ENABLE_PUBLIC_ACCESS" == "true" ]]; then
    echo "   🌍 Public Access (internet domains):"
    echo "      • OpenWebUI: https://$OPENWEBUI_DOMAIN_PUBLIC"
    echo "      • N8N: https://$N8N_DOMAIN_PUBLIC"
    
    # Show public access for services with domains (only if enabled)
    if [[ "$COMFYUI_ENABLED" == true && "$ENABLE_COMFYUI" == "y" ]] && [ -n "$COMFYUI_DOMAIN_PUBLIC" ] && [ "$COMFYUI_DOMAIN_PUBLIC" != "" ]; then
      echo "      • ComfyUI: https://$COMFYUI_DOMAIN_PUBLIC"
    fi
    if [[ "$MINIO_ENABLED" == true && "$ENABLE_MINIO" == "y" ]] && [ -n "$MINIO_DOMAIN_PUBLIC" ] && [ "$MINIO_DOMAIN_PUBLIC" != "" ]; then
      echo "      • MinIO Storage: https://$MINIO_DOMAIN_PUBLIC"
    fi
    if [ -n "$OLLAMA_DOMAIN_PUBLIC" ] && [ "$OLLAMA_DOMAIN_PUBLIC" != "" ]; then
      echo "      • Ollama API: https://$OLLAMA_DOMAIN_PUBLIC"
    fi
    echo ""
  fi
  
  # Show legacy external access for backward compatibility
  if [[ "$ENABLE_LAN_ACCESS" != "true" && "$ENABLE_PUBLIC_ACCESS" != "true" ]]; then
    echo "   🌐 External HTTPS Access:"
    echo "      • OpenWebUI: https://$OPENWEBUI_DOMAIN"
    echo "      • N8N: https://$N8N_DOMAIN"
    
    # Show external access for services with domains
    if [ -n "$COMFYUI_DOMAIN" ] && [ "$COMFYUI_DOMAIN" != "" ]; then
      echo "      • ComfyUI: https://$COMFYUI_DOMAIN"
    fi
    if [[ "$MINIO_ENABLED" == true && "$ENABLE_MINIO" == "y" ]] && [ -n "$MINIO_DOMAIN" ] && [ "$MINIO_DOMAIN" != "" ]; then
      echo "      • MinIO Storage: https://$MINIO_DOMAIN"
    fi
    if [ -n "$OLLAMA_DOMAIN" ] && [ "$OLLAMA_DOMAIN" != "" ]; then
      echo "      • Ollama API: https://$OLLAMA_DOMAIN"
    fi
    echo ""
  fi
  
  echo "   🔗 Internal Kubernetes Access:"
  
  # Show internal access for services without external domains
  if ([[ "$ENABLE_LAN_ACCESS" != "true" ]] || [[ -z "$COMFYUI_DOMAIN_LAN" || "$COMFYUI_DOMAIN_LAN" = "" ]]) && ([[ "$ENABLE_PUBLIC_ACCESS" != "true" ]] || [[ -z "$COMFYUI_DOMAIN_PUBLIC" || "$COMFYUI_DOMAIN_PUBLIC" = "" ]]) && ([[ -z "$COMFYUI_DOMAIN" || "$COMFYUI_DOMAIN" = "" ]]); then
    echo "      • ComfyUI: lair-comfyui.lair.svc.cluster.local:80"
  fi
  if [[ "$MINIO_ENABLED" == true && "$ENABLE_MINIO" == "y" ]] && ([[ "$ENABLE_LAN_ACCESS" != "true" ]] || [[ -z "$MINIO_DOMAIN_LAN" || "$MINIO_DOMAIN_LAN" = "" ]]) && ([[ "$ENABLE_PUBLIC_ACCESS" != "true" ]] || [[ -z "$MINIO_DOMAIN_PUBLIC" || "$MINIO_DOMAIN_PUBLIC" = "" ]]) && ([[ -z "$MINIO_DOMAIN" || "$MINIO_DOMAIN" = "" ]]); then
    echo "      • MinIO Console: lair-minio.lair.svc.cluster.local:80"
    echo "      • MinIO S3 API: lair-minio.lair.svc.cluster.local:9000"
  fi
  if ([[ "$ENABLE_LAN_ACCESS" != "true" ]] || [[ -z "$OLLAMA_DOMAIN_LAN" || "$OLLAMA_DOMAIN_LAN" = "" ]]) && ([[ "$ENABLE_PUBLIC_ACCESS" != "true" ]] || [[ -z "$OLLAMA_DOMAIN_PUBLIC" || "$OLLAMA_DOMAIN_PUBLIC" = "" ]]) && ([[ -z "$OLLAMA_DOMAIN" || "$OLLAMA_DOMAIN" = "" ]]); then
    echo "      • Ollama API: lair-ollama.lair.svc.cluster.local:11434"
  fi
  
  # Always show Tika (internal only)
  echo "      • Tika API: lair-tika.lair.svc.cluster.local:9998"
  
  echo ""
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "${BLUE}🚀 DEPLOYMENT OPTIONS${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Auto-apply configuration when cluster is accessible (no prompt)
  if [ "$K8S_CLUSTER_ACCESSIBLE" = "true" ]; then
    APPLY_CONFIG="y"
      execute_helm_deployment
  else
    echo -e "${YELLOW}⚠️  Kubernetes cluster not accessible - automatic deployment not available${NC}"
    echo ""
    echo "To apply this configuration when the cluster is accessible:"
    echo "   helm upgrade --install lair . --namespace $NAMESPACE --create-namespace -f $CONFIG_FILE"
    echo ""
    echo "Or, if you use microk8s:"
    echo "   microk8s helm3 upgrade --install lair . --namespace $NAMESPACE --create-namespace -f $CONFIG_FILE"
    echo ""
  fi

  # Make the script executable
  chmod +x "$0"

  # Auto-deployment if specified in config file
  if [ "$USE_CONFIG_FILE" = "true" ] && [ "$AUTO_DEPLOY" = "true" ]; then
    echo ""
    if [ "$K8S_CLUSTER_ACCESSIBLE" = "true" ]; then
      echo -e "${BLUE}🚀 Auto-deployment enabled in config file${NC}"
      APPLY_CONFIG="y"
      execute_helm_deployment
    else
      echo -e "${YELLOW}🚀 Auto-deployment enabled in config file but cluster not accessible${NC}"
      echo -e "${YELLOW}   Use the commands shown above when the cluster is available${NC}"
    fi
  fi
}