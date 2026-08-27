#!/bin/bash

# ============================================================================
# HELPERS.SH - Utility Functions and Helpers
# ============================================================================

# Function to show help
show_help() {
  echo "Lair Helm Chart - Configuration Generator"
  echo "Usage: $0 [--config CONFIG_FILE] [--update [CONFIG_FILE]] [--interactive] [--help]"
  echo ""
  echo "Options:"
  echo "  --config FILE    Use configuration from YAML file (fresh install)"
  echo "  --update [FILE]  Update existing configuration (auto-detects if no file specified)"
  echo "  --interactive    Skip config file import and go directly to interactive mode"
  echo "  --help, -h       Show this help message"
  echo ""
  echo "Examples:"
  echo "  $0                                    # Interactive mode with config file import option"
  echo "  $0 --interactive                     # Skip directly to interactive mode"
  echo "  $0 --config nexid-config.yaml    # Use pre-configured settings"
  echo "  $0 --update                          # Update existing configuration (auto-detect)"
  echo "  $0 --update nexid-config.yaml    # Update specific generated config file"
  echo ""
  echo "Configuration files:"
  echo "  See lair-config-template.yaml for template"
  echo "  See nexid-config.yaml and jetson-client-config.yaml for examples"
}

# Function to check for config file parameter
check_config_file_parameter() {
  # Save original arguments
  local original_args=("$@")
  
  # Check for --config and --update parameters
  local i=0
  while [ $i -lt $# ]; do
    case "${original_args[$i]}" in
      --config)
        if [ $((i+1)) -lt $# ]; then
          CONFIG_FILE_PATH="${original_args[$((i+1))]}"
          USE_CONFIG_FILE=true
          UPDATE_MODE=false
          echo "📋 Config file specified: $CONFIG_FILE_PATH"
          return 0
        else
          echo -e "${RED}Error: --config requires a filename argument${NC}"
          exit 1
        fi
        ;;
      --interactive)
        SKIP_CONFIG_IMPORT=true
        echo "🔧 Interactive mode: Skipping configuration file import"
        ;;
      --update)
        UPDATE_MODE=true
        USE_CONFIG_FILE=true
        # Check if next argument exists and is not another flag
        if [ $((i+1)) -lt $# ] && [[ ! "${original_args[$((i+1))]}" =~ ^-- ]]; then
          CONFIG_FILE_PATH="${original_args[$((i+1))]}"
          echo "📋 Update mode with specific file: $CONFIG_FILE_PATH"
        else
          # Auto-detect existing generated configuration files
          # Look for YAML files that are not the base values.yaml file
          local config_files=()
          
          # Find potential config files (exclude base files and templates)
          while IFS= read -r -d '' file; do
            local basename=$(basename "$file")
            # Skip base files and templates
            if [[ "$basename" != "values.yaml" && "$basename" != "Chart.yaml" && 
                  "$basename" != *"template"* && "$basename" != *"example"* ]]; then
              config_files+=("$file")
            fi
          done < <(find . -maxdepth 1 -name "*.yaml" -type f -print0 2>/dev/null)
          
          if [ ${#config_files[@]} -eq 0 ]; then
            echo -e "${RED}Error: No generated configuration files found for update mode${NC}"
            echo -e "${YELLOW}Expected files like: nexid-config.yaml, jetson-client-config.yaml, etc.${NC}"
            echo -e "${YELLOW}Run the script without --update first to generate a configuration${NC}"
            exit 1
          elif [ ${#config_files[@]} -eq 1 ]; then
            CONFIG_FILE_PATH="${config_files[0]}"
            echo "📋 Update mode: Auto-detected ${CONFIG_FILE_PATH}"
          else
            echo -e "${YELLOW}Multiple configuration files found:${NC}"
            for i in "${!config_files[@]}"; do
              echo "  $((i+1))) ${config_files[i]}"
            done
            echo ""
            read -p "Select configuration file to update (1-${#config_files[@]}): " file_choice
            
            if [[ "$file_choice" =~ ^[0-9]+$ ]] && [ "$file_choice" -ge 1 ] && [ "$file_choice" -le ${#config_files[@]} ]; then
              CONFIG_FILE_PATH="${config_files[$((file_choice-1))]}"
              echo "📋 Update mode: Selected ${CONFIG_FILE_PATH}"
            else
              echo -e "${RED}Error: Invalid selection${NC}"
              exit 1
            fi
          fi
        fi
        return 0
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
    esac
    i=$((i+1))
  done
  
  # Default values if no parameters specified
  UPDATE_MODE=false
  
  return 0
}

# Simplified storage input function with GB values and defaults
ask_storage_gb() {
  local component_name=$1
  local default_gb=$2
  local var_name=$3
  
  # Calculate a recommended value based on available storage and component type
  local recommended_gb
  case $component_name in
    "OpenWebUI") recommended_gb=10 ;;
    "Ollama models") recommended_gb=30 ;;
    "N8N workflows") recommended_gb=10 ;;
    "PostgreSQL"*) recommended_gb=5 ;;
    "Redis") recommended_gb=5 ;;
    "MinIO") recommended_gb=20 ;;
    *) recommended_gb=$default_gb ;;
  esac
  
  # Ensure recommended doesn't exceed available storage (with some buffer)
  local max_reasonable=$((CLUSTER_AVAILABLE_STORAGE_GB / 8))  # Don't use more than 1/8 of total for any component
  if [ "$recommended_gb" -gt "$max_reasonable" ]; then
    recommended_gb=$max_reasonable
  fi
  
  # Ensure minimum of 1GB
  if [ "$recommended_gb" -lt 1 ]; then
    recommended_gb=1
  fi
  
  read -p "${component_name} storage in GB (recommended: ${recommended_gb}GB, available: ${CLUSTER_AVAILABLE_STORAGE_GB}GB) [default: ${recommended_gb}]: " storage_input
  storage_input=${storage_input:-$recommended_gb}
  
  # Validate it's a number
  if ! [[ "$storage_input" =~ ^[0-9]+$ ]]; then
    echo "⚠️  Invalid input, using recommended: ${recommended_gb}GB"
    storage_input=$recommended_gb
  fi
  
  # Soft warning if exceeds available, but allow it
  if [ "$storage_input" -gt "$CLUSTER_AVAILABLE_STORAGE_GB" ]; then
    echo "⚠️  Warning: Requested ${storage_input}GB exceeds available ${CLUSTER_AVAILABLE_STORAGE_GB}GB"
  fi
  
  # Set the variable globally
  eval "$var_name=${storage_input}Gi"
  echo "✅ ${component_name}: ${storage_input}GB"
}

# Function to calculate resource allocations
prompt_and_calculate_resource_allocations() {
  echo ""
  echo "Percentage Resource Allocation Configuration"
  echo "==========================================="
  
  # Check if ComfyUI should be disabled due to low memory
  local comfyui_disabled=false
  if [ "$K8S_MEMORY_MB" -lt 8192 ]; then
    comfyui_disabled=true
    echo "⚠️  ComfyUI disabled due to insufficient memory (< 8GB)"
    echo "📊 Redistributing ComfyUI's 20% allocation to other components..."
  fi
  
  # Calculate redistributed percentages when ComfyUI is disabled
  if [ "$comfyui_disabled" = true ]; then
    # When ComfyUI is disabled, redistribute its 20% proportionally to other components
    # Original total without ComfyUI: 80% (25+35+5+5+7+3)
    # Redistribution factor: 100/80 = 1.25
    
    REDISTRIBUTED_PERCENTAGE_OPENWEBUI=$((PERCENTAGE_OPENWEBUI * 125 / 100))  # 25 * 1.25 = 31.25%
    REDISTRIBUTED_PERCENTAGE_OLLAMA=$((PERCENTAGE_OLLAMA * 125 / 100))        # 35 * 1.25 = 43.75%
    REDISTRIBUTED_PERCENTAGE_N8N=$((PERCENTAGE_N8N * 125 / 100))              # 5 * 1.25 = 6.25%
    REDISTRIBUTED_PERCENTAGE_POSTGRES=$((PERCENTAGE_POSTGRES * 125 / 100))    # 5 * 1.25 = 6.25%
    REDISTRIBUTED_PERCENTAGE_MINIO=$((PERCENTAGE_MINIO * 125 / 100))          # 7 * 1.25 = 8.75%
    REDISTRIBUTED_PERCENTAGE_REDIS=$((PERCENTAGE_REDIS * 125 / 100))          # 3 * 1.25 = 3.75%
    REDISTRIBUTED_PERCENTAGE_COMFYUI=0                                        # 0% when disabled
    
    # Use redistributed percentages
    EFFECTIVE_PERCENTAGE_OPENWEBUI=$REDISTRIBUTED_PERCENTAGE_OPENWEBUI
    EFFECTIVE_PERCENTAGE_OLLAMA=$REDISTRIBUTED_PERCENTAGE_OLLAMA
    EFFECTIVE_PERCENTAGE_N8N=$REDISTRIBUTED_PERCENTAGE_N8N
    EFFECTIVE_PERCENTAGE_POSTGRES=$REDISTRIBUTED_PERCENTAGE_POSTGRES
    EFFECTIVE_PERCENTAGE_MINIO=$REDISTRIBUTED_PERCENTAGE_MINIO
    EFFECTIVE_PERCENTAGE_REDIS=$REDISTRIBUTED_PERCENTAGE_REDIS
    EFFECTIVE_PERCENTAGE_COMFYUI=$REDISTRIBUTED_PERCENTAGE_COMFYUI
    
    echo "📊 Redistributed Resource Distribution (ComfyUI disabled):"
    echo "   • OpenWebUI: ${EFFECTIVE_PERCENTAGE_OPENWEBUI}% (was ${PERCENTAGE_OPENWEBUI}%)"
    echo "   • Ollama: ${EFFECTIVE_PERCENTAGE_OLLAMA}% (was ${PERCENTAGE_OLLAMA}%)"
    echo "   • N8N: ${EFFECTIVE_PERCENTAGE_N8N}% (was ${PERCENTAGE_N8N}%)"
    echo "   • PostgreSQL: ${EFFECTIVE_PERCENTAGE_POSTGRES}% (was ${PERCENTAGE_POSTGRES}%)"
    echo "   • MinIO: ${EFFECTIVE_PERCENTAGE_MINIO}% (was ${PERCENTAGE_MINIO}%)"
    echo "   • Redis: ${EFFECTIVE_PERCENTAGE_REDIS}% (was ${PERCENTAGE_REDIS}%)"
    echo "   • ComfyUI: ${EFFECTIVE_PERCENTAGE_COMFYUI}% (disabled)"
  else
    # Use original percentages when ComfyUI is enabled
    EFFECTIVE_PERCENTAGE_OPENWEBUI=$PERCENTAGE_OPENWEBUI
    EFFECTIVE_PERCENTAGE_OLLAMA=$PERCENTAGE_OLLAMA
    EFFECTIVE_PERCENTAGE_N8N=$PERCENTAGE_N8N
    EFFECTIVE_PERCENTAGE_POSTGRES=$PERCENTAGE_POSTGRES
    EFFECTIVE_PERCENTAGE_MINIO=$PERCENTAGE_MINIO
    EFFECTIVE_PERCENTAGE_REDIS=$PERCENTAGE_REDIS
    EFFECTIVE_PERCENTAGE_COMFYUI=$PERCENTAGE_COMFYUI
    
    echo "📊 Standard Resource Distribution (ComfyUI enabled):"
    echo "   • OpenWebUI: ${EFFECTIVE_PERCENTAGE_OPENWEBUI}%"
    echo "   • Ollama: ${EFFECTIVE_PERCENTAGE_OLLAMA}%"
    echo "   • ComfyUI: ${EFFECTIVE_PERCENTAGE_COMFYUI}%"
    echo "   • N8N: ${EFFECTIVE_PERCENTAGE_N8N}%"
    echo "   • PostgreSQL: ${EFFECTIVE_PERCENTAGE_POSTGRES}%"
    echo "   • MinIO: ${EFFECTIVE_PERCENTAGE_MINIO}%"
    echo "   • Redis: ${EFFECTIVE_PERCENTAGE_REDIS}%"
  fi
  
  # Calculate actual resources based on effective percentages
  # REQUESTS: CPU in millicore (1000m = 1 CPU), distributed as percentages of cluster resources
  # Use bc for decimal calculations for K8S_CPU
  CPU_OPENWEBUI_REQ=$(echo "$K8S_CPU * $EFFECTIVE_PERCENTAGE_OPENWEBUI * 10" | bc | awk '{print int($1)}')
  CPU_OLLAMA_REQ=$(echo "$K8S_CPU * $EFFECTIVE_PERCENTAGE_OLLAMA * 10" | bc | awk '{print int($1)}')
  CPU_N8N_REQ=$(echo "$K8S_CPU * $EFFECTIVE_PERCENTAGE_N8N * 10" | bc | awk '{print int($1)}')
  CPU_POSTGRES_REQ=$(echo "$K8S_CPU * $EFFECTIVE_PERCENTAGE_POSTGRES * 10" | bc | awk '{print int($1)}')
  CPU_REDIS_REQ=$(echo "$K8S_CPU * $EFFECTIVE_PERCENTAGE_REDIS * 10" | bc | awk '{print int($1)}')
  CPU_MINIO_REQ=$(echo "$K8S_CPU * $EFFECTIVE_PERCENTAGE_MINIO * 10" | bc | awk '{print int($1)}')
  CPU_COMFYUI_REQ=$(echo "$K8S_CPU * $EFFECTIVE_PERCENTAGE_COMFYUI * 10" | bc | awk '{print int($1)}')
  
  # REQUESTS: Memory in MB, distributed as percentages of cluster resources
  MEM_OPENWEBUI_REQ=$((K8S_MEMORY_MB * EFFECTIVE_PERCENTAGE_OPENWEBUI / 100))
  MEM_OLLAMA_REQ=$((K8S_MEMORY_MB * EFFECTIVE_PERCENTAGE_OLLAMA / 100))
  MEM_N8N_REQ=$((K8S_MEMORY_MB * EFFECTIVE_PERCENTAGE_N8N / 100))
  MEM_POSTGRES_REQ=$((K8S_MEMORY_MB * EFFECTIVE_PERCENTAGE_POSTGRES / 100))
  MEM_REDIS_REQ=$((K8S_MEMORY_MB * EFFECTIVE_PERCENTAGE_REDIS / 100))
  MEM_MINIO_REQ=$((K8S_MEMORY_MB * EFFECTIVE_PERCENTAGE_MINIO / 100))
  MEM_COMFYUI_REQ=$((K8S_MEMORY_MB * EFFECTIVE_PERCENTAGE_COMFYUI / 100))

  # Ensure component-specific minimums are respected for REQUESTS
  echo ""
  echo "🔧 Applying component-specific minimum requirements to requests..."
  
  # OpenWebUI minimums for requests
  [[ $CPU_OPENWEBUI_REQ -lt $MIN_CPU_OPENWEBUI ]] && CPU_OPENWEBUI_REQ=$MIN_CPU_OPENWEBUI
  [[ $MEM_OPENWEBUI_REQ -lt $MIN_MEM_OPENWEBUI ]] && MEM_OPENWEBUI_REQ=$MIN_MEM_OPENWEBUI
  
  # Ollama minimums for requests
  [[ $CPU_OLLAMA_REQ -lt $MIN_CPU_OLLAMA ]] && CPU_OLLAMA_REQ=$MIN_CPU_OLLAMA
  [[ $MEM_OLLAMA_REQ -lt $MIN_MEM_OLLAMA ]] && MEM_OLLAMA_REQ=$MIN_MEM_OLLAMA
  
  # ComfyUI minimums for requests (only if enabled)
  if [ "$comfyui_disabled" = false ]; then
    [[ $CPU_COMFYUI_REQ -lt $MIN_CPU_COMFYUI ]] && CPU_COMFYUI_REQ=$MIN_CPU_COMFYUI
    [[ $MEM_COMFYUI_REQ -lt $MIN_MEM_COMFYUI ]] && MEM_COMFYUI_REQ=$MIN_MEM_COMFYUI
  fi
  
  # N8N minimums for requests
  [[ $CPU_N8N_REQ -lt $MIN_CPU_N8N ]] && CPU_N8N_REQ=$MIN_CPU_N8N
  [[ $MEM_N8N_REQ -lt $MIN_MEM_N8N ]] && MEM_N8N_REQ=$MIN_MEM_N8N
  
  # PostgreSQL minimums for requests
  [[ $CPU_POSTGRES_REQ -lt $MIN_CPU_POSTGRES ]] && CPU_POSTGRES_REQ=$MIN_CPU_POSTGRES
  [[ $MEM_POSTGRES_REQ -lt $MIN_MEM_POSTGRES ]] && MEM_POSTGRES_REQ=$MIN_MEM_POSTGRES
  
  # Redis minimums for requests
  [[ $CPU_REDIS_REQ -lt $MIN_CPU_REDIS ]] && CPU_REDIS_REQ=$MIN_CPU_REDIS
  [[ $MEM_REDIS_REQ -lt $MIN_MEM_REDIS ]] && MEM_REDIS_REQ=$MIN_MEM_REDIS
  
  # MinIO minimums for requests
  [[ $CPU_MINIO_REQ -lt $MIN_CPU_MINIO ]] && CPU_MINIO_REQ=$MIN_CPU_MINIO
  [[ $MEM_MINIO_REQ -lt $MIN_MEM_MINIO ]] && MEM_MINIO_REQ=$MIN_MEM_MINIO

  # LIMITS: Calculate as multiplier of requests for intelligent overcommit
  echo ""
  echo "🚀 Calculating resource limits (requests * multiplier for intelligent overcommit)..."
  
  # CPU Limits (use bc for decimal multiplication)
  CPU_OPENWEBUI=$(echo "$CPU_OPENWEBUI_REQ * $LIMIT_MULTIPLIER_OPENWEBUI" | bc | awk '{print int($1)}')
  CPU_OLLAMA=$(echo "$CPU_OLLAMA_REQ * $LIMIT_MULTIPLIER_OLLAMA" | bc | awk '{print int($1)}')
  CPU_N8N=$(echo "$CPU_N8N_REQ * $LIMIT_MULTIPLIER_N8N" | bc | awk '{print int($1)}')
  CPU_POSTGRES=$(echo "$CPU_POSTGRES_REQ * $LIMIT_MULTIPLIER_POSTGRES" | bc | awk '{print int($1)}')
  CPU_REDIS=$(echo "$CPU_REDIS_REQ * $LIMIT_MULTIPLIER_REDIS" | bc | awk '{print int($1)}')
  CPU_MINIO=$(echo "$CPU_MINIO_REQ * $LIMIT_MULTIPLIER_MINIO" | bc | awk '{print int($1)}')
  CPU_COMFYUI=$(echo "$CPU_COMFYUI_REQ * $LIMIT_MULTIPLIER_COMFYUI" | bc | awk '{print int($1)}')
  
  # Memory Limits (use bc for decimal multiplication)  
  MEM_OPENWEBUI=$(echo "$MEM_OPENWEBUI_REQ * $LIMIT_MULTIPLIER_OPENWEBUI" | bc | awk '{print int($1)}')
  MEM_OLLAMA=$(echo "$MEM_OLLAMA_REQ * $LIMIT_MULTIPLIER_OLLAMA" | bc | awk '{print int($1)}')
  MEM_N8N=$(echo "$MEM_N8N_REQ * $LIMIT_MULTIPLIER_N8N" | bc | awk '{print int($1)}')
  MEM_POSTGRES=$(echo "$MEM_POSTGRES_REQ * $LIMIT_MULTIPLIER_POSTGRES" | bc | awk '{print int($1)}')
  MEM_REDIS=$(echo "$MEM_REDIS_REQ * $LIMIT_MULTIPLIER_REDIS" | bc | awk '{print int($1)}')
  MEM_MINIO=$(echo "$MEM_MINIO_REQ * $LIMIT_MULTIPLIER_MINIO" | bc | awk '{print int($1)}')
  MEM_COMFYUI=$(echo "$MEM_COMFYUI_REQ * $LIMIT_MULTIPLIER_COMFYUI" | bc | awk '{print int($1)}')
  
  # Determine N8N worker replicas based on available memory and nodes
  if [ "$K8S_MEMORY_MB" -lt 8192 ]; then
    N8N_WORKER_REPLICAS=1
    echo "   🔄 N8N Workers: $N8N_WORKER_REPLICAS replica (memory limited: $(echo "scale=1; $K8S_MEMORY_MB/1024" | bc)GB < 8GB)"
  else
    # Memory is sufficient for multiple replicas - check nodes count
    if [ -z "$NODES_COUNT" ] || [ "$NODES_COUNT" -eq 0 ]; then
      # Cannot determine nodes count, use default
      N8N_WORKER_REPLICAS=2
      echo "   🔄 N8N Workers: $N8N_WORKER_REPLICAS replicas (sufficient memory, nodes unknown)"
    else
      # Use min(nodes_count, 3) replicas
      if [ "$NODES_COUNT" -le 3 ]; then
        N8N_WORKER_REPLICAS=$NODES_COUNT
        echo "   🔄 N8N Workers: $N8N_WORKER_REPLICAS replicas (matching $NODES_COUNT nodes)"
      else
        N8N_WORKER_REPLICAS=3
        echo "   🔄 N8N Workers: $N8N_WORKER_REPLICAS replicas (max limit, $NODES_COUNT nodes available)"
      fi
    fi
  fi
  
  # N8N Workers - use 50% of N8N main allocation per worker
  CPU_N8N_WORKER_REQ=$((CPU_N8N_REQ / 2))
  MEM_N8N_WORKER_REQ=$((MEM_N8N_REQ / 2))
  CPU_N8N_WORKER=$(echo "$CPU_N8N_WORKER_REQ * $LIMIT_MULTIPLIER_N8N" | bc | awk '{print int($1)}')
  MEM_N8N_WORKER=$(echo "$MEM_N8N_WORKER_REQ * $LIMIT_MULTIPLIER_N8N" | bc | awk '{print int($1)}')

  # Apply minimum values for N8N Workers
  [[ $CPU_N8N_WORKER_REQ -lt $MIN_CPU_REQ ]] && CPU_N8N_WORKER_REQ=$MIN_CPU_REQ
  [[ $MEM_N8N_WORKER_REQ -lt $MIN_MEM_REQ ]] && MEM_N8N_WORKER_REQ=$MIN_MEM_REQ

  echo ""
  echo "✅ Resource calculation completed with intelligent overcommit strategy:"
  echo "   📊 Requests: Distributed based on component percentages (guaranteed resources)"
  echo "   🚀 Limits: Calculated as multiplier of requests (burst capacity)"

  echo -e "${GREEN}✅ Resource calculation for components completed.${NC}"
  echo ""
  echo "📋 Final Resource Allocation:"
  echo "   • OpenWebUI: ${CPU_OPENWEBUI}m CPU / ${MEM_OPENWEBUI}MB RAM"
  echo "   • Ollama: ${CPU_OLLAMA}m CPU / ${MEM_OLLAMA}MB RAM"
  if [ "$comfyui_disabled" = false ]; then
    echo "   • ComfyUI: ${CPU_COMFYUI}m CPU / ${MEM_COMFYUI}MB RAM"
  else
    echo "   • ComfyUI: DISABLED (insufficient memory)"
  fi
  echo "   • N8N: ${CPU_N8N}m CPU / ${MEM_N8N}MB RAM"
  echo "   • N8N Workers (x${N8N_WORKER_REPLICAS}): ${CPU_N8N_WORKER}m CPU / ${MEM_N8N_WORKER}MB RAM each"
  echo "   • PostgreSQL: ${CPU_POSTGRES}m CPU / ${MEM_POSTGRES}MB RAM"
  echo "   • MinIO: ${CPU_MINIO}m CPU / ${MEM_MINIO}MB RAM"
  echo "   • Redis: ${CPU_REDIS}m CPU / ${MEM_REDIS}MB RAM"
  
  # Ensure K8S_CPU_FORMATTED exists for resource calculations
  K8S_CPU_FORMATTED=$K8S_CPU
}

# Calculate totals from the same values used by the generated resources report.
calculate_total_allocated_resources() {
  BASE_CPU=$((CPU_OPENWEBUI + CPU_OLLAMA + CPU_N8N + (CPU_N8N_WORKER * N8N_WORKER_REPLICAS) + CPU_POSTGRES + CPU_REDIS + CPU_TIKA))
  BASE_MEMORY=$((MEM_OPENWEBUI + MEM_OLLAMA + MEM_N8N + (MEM_N8N_WORKER * N8N_WORKER_REPLICAS) + MEM_POSTGRES + MEM_REDIS + MEM_TIKA))
  BASE_CPU_REQ=$((CPU_OPENWEBUI_REQ + CPU_OLLAMA_REQ + CPU_N8N_REQ + (CPU_N8N_WORKER_REQ * N8N_WORKER_REPLICAS) + CPU_POSTGRES_REQ + CPU_REDIS_REQ + CPU_TIKA_REQ))
  BASE_MEMORY_REQ=$((MEM_OPENWEBUI_REQ + MEM_OLLAMA_REQ + MEM_N8N_REQ + (MEM_N8N_WORKER_REQ * N8N_WORKER_REPLICAS) + MEM_POSTGRES_REQ + MEM_REDIS_REQ + MEM_TIKA_REQ))
  BASE_STORAGE=$((OPENWEBUI_STORAGE_GB + OLLAMA_STORAGE_GB + N8N_STORAGE_GB + PG_STORAGE_GB + REDIS_STORAGE_GB))

  if [[ "$MINIO_ENABLED" == true && "$ENABLE_MINIO" == "y" ]]; then
    BASE_CPU=$((BASE_CPU + CPU_MINIO))
    BASE_MEMORY=$((BASE_MEMORY + MEM_MINIO))
    BASE_CPU_REQ=$((BASE_CPU_REQ + CPU_MINIO_REQ))
    BASE_MEMORY_REQ=$((BASE_MEMORY_REQ + MEM_MINIO_REQ))
    BASE_STORAGE=$((BASE_STORAGE + MINIO_STORAGE_GB))
  fi

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
}

# Function to detect public IP address
detect_public_ip() {
  echo -e "${BLUE}🌍 Detecting public IP address...${NC}"
  
  # Check if curl is available
  if ! command -v curl >/dev/null 2>&1; then
    PUBLIC_IP="Unable to detect"
    echo -e "${RED}❌ curl is not installed${NC}"
    echo -e "${YELLOW}   Please install curl: sudo apt install curl${NC}"
    echo -e "${YELLOW}   Or use snap: sudo snap install curl${NC}"
    export PUBLIC_IP
    return 1
  fi
  
  local public_ip=""
  local timeout_cmd=""
  
  # Set timeout command based on availability
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout 5"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout 5"
  fi
  
  # Try multiple IP detection services with timeout
  local ip_services=(
    "https://api.ipify.org"
    "https://icanhazip.com"
    "https://ifconfig.me"
    "https://ipecho.net/plain"
  )
  
  for service in "${ip_services[@]}"; do
    if [ -n "$timeout_cmd" ]; then
      public_ip=$(${timeout_cmd} curl -s --max-time 3 --retry 1 "$service" 2>/dev/null | tr -d '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    else
      public_ip=$(curl -s --max-time 3 --retry 1 "$service" 2>/dev/null | tr -d '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    fi
    
    # If we got a valid IP, break the loop
    if [ -n "$public_ip" ]; then
      break
    fi
  done
  
  # Store the result globally
  if [ -n "$public_ip" ]; then
    PUBLIC_IP="$public_ip"
    echo -e "${GREEN}✅ Public IP detected: $PUBLIC_IP${NC}"
  else
    PUBLIC_IP="Unable to detect"
    echo -e "${YELLOW}⚠️  Could not detect public IP address${NC}"
    echo -e "${YELLOW}   This may be due to network restrictions or firewall settings${NC}"
  fi
  
  # Export for use in other scripts
  export PUBLIC_IP
}
