#!/bin/bash

# ============================================================================
# SYSTEM-DETECTION.SH - System Resource Detection Functions
# ============================================================================

# Function to determine which kubectl and helm to use
detect_jetson_platform() {
  IS_JETSON="n"

  for model_file in /proc/device-tree/model /sys/firmware/devicetree/base/model; do
    if [ -r "$model_file" ] && tr -d '\0' < "$model_file" | grep -Eiq "jetson|xavier|nano|orin|agx"; then
      IS_JETSON="y"
      break
    fi
  done

  if uname -r | grep -qi "tegra"; then
    IS_JETSON="y"
  fi
}

detect_commands() {
  echo "🔍 Debug: Starting detect_commands function"
  
  # ============================================================================
  # FIX: Handle kubeconfig access when running as root
  # ============================================================================
  if [ "$(id -u)" -eq 0 ]; then
    echo "🔍 Debug: Running as root, ensuring kubeconfig access for helm..."
    
    # Try to find the original user's kubeconfig
    ORIGINAL_USER="${SUDO_USER:-$(who am i | awk '{print $1}')}"
    if [ -n "$ORIGINAL_USER" ] && [ "$ORIGINAL_USER" != "root" ]; then
      ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
      ORIGINAL_KUBECONFIG="$ORIGINAL_HOME/.kube/config"
      
      echo "🔍 Debug: Original user: $ORIGINAL_USER"
      echo "🔍 Debug: Original home: $ORIGINAL_HOME"
      echo "🔍 Debug: Looking for kubeconfig: $ORIGINAL_KUBECONFIG"
      
      if [ -f "$ORIGINAL_KUBECONFIG" ]; then
        echo "🔍 Debug: Found user's kubeconfig, setting up access for root..."
        
        # Create /root/.kube directory if it doesn't exist
        mkdir -p /root/.kube
        
        # Copy the user's kubeconfig to root (safer than symlinking)
        cp "$ORIGINAL_KUBECONFIG" /root/.kube/config
        chmod 600 /root/.kube/config
        
        # Also set KUBECONFIG environment variable as backup
        export KUBECONFIG="/root/.kube/config"
        
        echo "✅ Kubeconfig copied for root access - helm should now work"
      else
        echo "⚠️  User's kubeconfig not found at $ORIGINAL_KUBECONFIG"
      fi
    else
      echo "⚠️  Could not determine original user - helm may not work"
    fi
  fi
  
  # Determine kubectl command
  if command -v microk8s &>/dev/null; then
    KUBECTL_CMD="microk8s kubectl"
    echo -e "${GREEN}Found microk8s kubectl${NC}"
  elif command -v kubectl &>/dev/null; then
    KUBECTL_CMD="kubectl"
    echo -e "${GREEN}Found standard kubectl${NC}"
  else
    echo -e "${RED}Error: No kubectl client found. Install kubectl or microk8s.${NC}"
    exit 1
  fi

  # Detect available helm commands (don't choose yet)
  HELM_STANDARD_AVAILABLE=false
  HELM_MICROK8S_AVAILABLE=false
  
  # Check for standard helm - TEST REAL CLUSTER CONNECTIVITY
  if command -v helm &>/dev/null; then
    echo "🔍 Testing standard helm cluster connectivity..."
    if helm list --all-namespaces &>/dev/null; then
      HELM_STANDARD_AVAILABLE=true
      echo -e "${GREEN}✅ Standard helm can connect to cluster${NC}"
    else
      echo -e "${YELLOW}⚠️  Standard helm found but cannot connect to cluster${NC}"
    fi
  else
    echo -e "${YELLOW}✗ Standard helm not installed${NC}"
  fi
  
  # Check for microk8s helm3 - TEST REAL CLUSTER CONNECTIVITY
  if command -v microk8s &>/dev/null; then
    echo "🔍 Testing microk8s helm3 cluster connectivity..."
    if microk8s helm3 list --all-namespaces &>/dev/null; then
      HELM_MICROK8S_AVAILABLE=true
      echo -e "${GREEN}✅ MicroK8s helm3 can connect to cluster${NC}"
    else
      echo -e "${YELLOW}⚠️  MicroK8s found but helm3 cannot connect to cluster${NC}"
    fi
  else
    echo -e "${YELLOW}✗ MicroK8s not installed${NC}"
  fi
  
  # Set default helm command (prefer standard helm if working)
  if [ "$HELM_STANDARD_AVAILABLE" = true ]; then
    HELM_CMD="helm"
    echo -e "${BLUE}🎯 Default helm: standard helm${NC}"
  elif [ "$HELM_MICROK8S_AVAILABLE" = true ]; then
    HELM_CMD="microk8s helm3"
    echo -e "${BLUE}🎯 Default helm: microk8s helm3${NC}"
  else
    echo -e "${RED}❌ Error: No working helm client found.${NC}"
    echo "Please install either:"
    echo "  • Standard helm: https://helm.sh/docs/intro/install/"
    echo "  • MicroK8s: microk8s enable helm3"
    exit 1
  fi

  echo "🔍 Helm detection complete - Default: $HELM_CMD"
  
  # Test cluster accessibility with timeout
  echo -e "${BLUE}Testing cluster accessibility...${NC}"
  
  # Use timeout to prevent hanging - handle different timeout commands
  cluster_test_result=false
  if command -v timeout &>/dev/null; then
    # Linux timeout command
    if timeout 5 $KUBECTL_CMD get nodes &>/dev/null; then
      cluster_test_result=true
    fi
  elif command -v gtimeout &>/dev/null; then
    # macOS timeout command (from coreutils)
    if gtimeout 5 $KUBECTL_CMD get nodes &>/dev/null; then
      cluster_test_result=true
    fi
  else
    # No timeout command available, test without timeout (might hang)
    echo -e "${YELLOW}No timeout command available, testing without timeout...${NC}"
    if $KUBECTL_CMD get nodes &>/dev/null; then
      cluster_test_result=true
    fi
  fi
  
  if [ "$cluster_test_result" = true ]; then
    K8S_CLUSTER_ACCESSIBLE=true
    echo -e "${GREEN}✅ Kubernetes cluster is accessible${NC}"
  else
    K8S_CLUSTER_ACCESSIBLE=false
    echo -e "${YELLOW}⚠️  Kubernetes cluster is not accessible${NC}"
    echo -e "${YELLOW}   - Resource detection from cluster will not be available${NC}"
    echo -e "${YELLOW}   - Only local resource detection will be possible${NC}"
  fi
  
  echo "Cluster accessibility test completed"
}

# Function to calculate optimal Longhorn replicas based on node count
calculate_longhorn_replicas() {
  # Default to 1 replica if NODES_COUNT is not set or empty
  if [ -z "$NODES_COUNT" ] || [ "$NODES_COUNT" -eq 0 ]; then
    LONGHORN_REPLICAS_COUNT=1
    echo -e "${YELLOW}⚠️  Unable to determine node count, using 1 Longhorn replica${NC}"
  else
    # Calculate optimal replicas: min(nodes_count, 3)
    if [ "$NODES_COUNT" -le 3 ]; then
      LONGHORN_REPLICAS_COUNT=$NODES_COUNT
    else
      LONGHORN_REPLICAS_COUNT=3
    fi
    
    echo -e "${GREEN}📦 Longhorn replicas calculated: $LONGHORN_REPLICAS_COUNT (based on $NODES_COUNT nodes)${NC}"
    
    # Show explanation
    if [ "$NODES_COUNT" -eq 1 ]; then
      echo -e "${BLUE}   → Single node cluster: 1 replica (no redundancy)${NC}"
    elif [ "$NODES_COUNT" -eq 2 ]; then
      echo -e "${BLUE}   → Two-node cluster: 2 replicas (basic redundancy)${NC}"
    elif [ "$NODES_COUNT" -eq 3 ]; then
      echo -e "${BLUE}   → Three-node cluster: 3 replicas (recommended redundancy)${NC}"
    else
      echo -e "${BLUE}   → Multi-node cluster (${NODES_COUNT} nodes): 3 replicas (maximum redundancy)${NC}"
    fi
  fi
  
  # Export for use in other scripts
  export LONGHORN_REPLICAS_COUNT
}

# Function to detect available system resources
detect_system_resources() {
  echo -e "${BLUE}Detecting available system resources...${NC}"
  
  # Use DETECTION_CHOICE if already set (from config file), otherwise ask user
  if [ -z "$DETECTION_CHOICE" ] || [ "$USE_CONFIG_FILE" = "false" ]; then
    # Ask the user if they want to detect resources from local system or Kubernetes cluster
    echo ""
    echo "How do you prefer to detect available resources?"
    echo "1) From local operating system (where this script is executed)"
    
    if [ "$K8S_CLUSTER_ACCESSIBLE" = "true" ]; then
      echo "2) From connected Kubernetes cluster (actually available resources)"
      echo ""
      read -p "Enter your choice [1-2] (default: 1): " DETECTION_CHOICE
      DETECTION_CHOICE=${DETECTION_CHOICE:-1}
    else
      echo "2) From connected Kubernetes cluster (❌ NOT AVAILABLE - cluster not accessible)"
      echo ""
      echo -e "${YELLOW}⚠️  Cluster not accessible, automatically using local detection${NC}"
      DETECTION_CHOICE=1
    fi
  else
    echo "Using detection method from configuration: $DETECTION_CHOICE"
    
    # Override detection choice if cluster is not accessible
    if [ "$DETECTION_CHOICE" = "2" ] && [ "$K8S_CLUSTER_ACCESSIBLE" = "false" ]; then
      echo -e "${YELLOW}⚠️  Cluster not accessible, switching to local detection (option 1)${NC}"
      DETECTION_CHOICE=1
    fi
  fi
  
  # Initialize variables for CPU and memory
  TOTAL_CPU=0
  TOTAL_MEMORY_MB=0
  
  if [ "$DETECTION_CHOICE" = "1" ]; then
    echo -e "${BLUE}Detecting resources from local system...${NC}"
    
    # Determine operating system
    OS=$(uname -s)
  
    if [[ "$OS" == "Linux" ]]; then
      # On Linux, use /proc/cpuinfo for CPU
      if [ -f /proc/cpuinfo ]; then
        TOTAL_CPU=$(grep -c "processor" /proc/cpuinfo)
      fi
      
      # Use /proc/meminfo for memory
      if [ -f /proc/meminfo ]; then
        TOTAL_MEMORY_KB=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
        TOTAL_MEMORY_MB=$((TOTAL_MEMORY_KB / 1024))
      fi
    elif [[ "$OS" == "Darwin" ]]; then
      # On macOS, use sysctl
      TOTAL_CPU=$(sysctl -n hw.ncpu)
      TOTAL_MEMORY_BYTES=$(sysctl -n hw.memsize)
      TOTAL_MEMORY_MB=$((TOTAL_MEMORY_BYTES / 1024 / 1024))
    fi
    
    # Check if it was possible to detect resources
    if (( $(echo "$TOTAL_CPU < 0.1" | bc -l) )) || [ "$TOTAL_MEMORY_MB" -lt 100 ]; then
      echo -e "${YELLOW}Unable to automatically detect system resources or values too low.${NC}"
      read -p "Enter the total number of available CPU/cores: " TOTAL_CPU
      read -p "Enter the total available memory in GB: " TOTAL_MEMORY_GB
      # Convert to MB for internal calculations
      TOTAL_MEMORY_MB=$(echo "$TOTAL_MEMORY_GB * 1024" | bc | awk '{print int($1)}')
    fi
    
    # Show detected resources with decimals
    TOTAL_MEMORY_GB=$(echo "scale=1; $TOTAL_MEMORY_MB/1024" | bc)
    echo -e "${GREEN}Detected resources: $TOTAL_CPU CPU, $TOTAL_MEMORY_GB GB RAM${NC}"
    
    # Estimate available resources for Kubernetes (based on K8S_RESOURCE_ALLOCATION_PERCENTAGE)
    K8S_CPU=$(echo "scale=1; $TOTAL_CPU * $K8S_RESOURCE_ALLOCATION_PERCENTAGE / 100" | bc)
    K8S_MEMORY_MB=$(echo "scale=0; $TOTAL_MEMORY_MB * $K8S_RESOURCE_ALLOCATION_PERCENTAGE / 100" | bc | awk '{print int($1)}')
    K8S_MEMORY_GB=$(echo "scale=1; $K8S_MEMORY_MB/1024" | bc)
    echo -e "${BLUE}Guaranteed minimum resources for applications (${K8S_RESOURCE_ALLOCATION_PERCENTAGE}% of total): $K8S_CPU CPU, $K8S_MEMORY_GB GB RAM${NC}"
    echo -e "${BLUE}📈 Apps can burst beyond these minimums using unused resources from other services${NC}"

    # Check for minimum resource requirements for Kubernetes
    if (( $(echo "$K8S_CPU < 4" | bc -l) )) || [ "$K8S_MEMORY_MB" -lt 7000 ]; then
      echo -e "${YELLOW}⚠️  Guaranteed minimum resources are below recommended thresholds.${NC}"
      echo -e "${YELLOW}   - Guaranteed CPU: $K8S_CPU (recommended minimum: 4 cores)${NC}"
      echo -e "${YELLOW}   - Guaranteed Memory: $K8S_MEMORY_GB GB (recommended minimum: 8GB)${NC}"
      echo -e "${YELLOW}${NC}"
      echo -e "${YELLOW}💡 Note: These are GUARANTEED minimums. Apps can use much more when available:${NC}"
      echo -e "${YELLOW}   - Total system resources: $TOTAL_CPU CPU, $TOTAL_MEMORY_GB GB RAM${NC}"
      echo -e "${YELLOW}   - Apps will automatically burst to use idle resources from other services${NC}"
      echo -e "${YELLOW}   - This overcommitment strategy maximizes hardware utilization${NC}"
      echo -e "${YELLOW}${NC}"
      read -p "Do you want to continue with this resource allocation? (y/n) [default: y]: " CONTINUE_LOW_RESOURCES
      CONTINUE_LOW_RESOURCES=${CONTINUE_LOW_RESOURCES:-y}
      if [[ "$CONTINUE_LOW_RESOURCES" == "y" || "$CONTINUE_LOW_RESOURCES" == "Y" ]]; then
        echo -e "${GREEN}✅ Proceeding with overcommitment strategy for optimal resource utilization.${NC}"
      else
        echo -e "${RED}❌ Exiting. Consider increasing K8S_RESOURCE_ALLOCATION_PERCENTAGE in globals.sh if needed.${NC}"
        exit 1
      fi
    fi
    
    # Calculate Longhorn replicas with default value for local detection
    NODES_COUNT=""  # Cannot determine nodes in local detection mode
    calculate_longhorn_replicas
    
  elif [ "$DETECTION_CHOICE" = "2" ]; then
    # Detection from Kubernetes cluster (actually available resources)
    echo -e "${BLUE}Detecting resources from Kubernetes cluster...${NC}"
    
    # Check if we can access the cluster (double check)
    if [ "$K8S_CLUSTER_ACCESSIBLE" = "false" ] || ! $KUBECTL_CMD get nodes &>/dev/null; then
      echo -e "${RED}Unable to access Kubernetes cluster. Check the configuration.${NC}"
      echo -e "${YELLOW}Switching to local system detection.${NC}"
      
      # Fallback to local system detection
      OS=$(uname -s)
      
      if [[ "$OS" == "Linux" ]]; then
        # On Linux, use /proc/cpuinfo for CPU
        if [ -f /proc/cpuinfo ]; then
          TOTAL_CPU=$(grep -c "processor" /proc/cpuinfo)
        fi
        
        # Use /proc/meminfo for memory
        if [ -f /proc/meminfo ]; then
          TOTAL_MEMORY_KB=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
          TOTAL_MEMORY_MB=$((TOTAL_MEMORY_KB / 1024))
        fi
      elif [[ "$OS" == "Darwin" ]]; then
        # On macOS, use sysctl
        TOTAL_CPU=$(sysctl -n hw.ncpu)
        TOTAL_MEMORY_BYTES=$(sysctl -n hw.memsize)
        TOTAL_MEMORY_MB=$((TOTAL_MEMORY_BYTES / 1024 / 1024))
      fi
      
      # Use local values with 80% factor
      TOTAL_MEMORY_GB=$(echo "scale=1; $TOTAL_MEMORY_MB/1024" | bc)
      echo -e "${GREEN}Detected resources (local fallback): $TOTAL_CPU CPU, $TOTAL_MEMORY_GB GB RAM${NC}"
      K8S_CPU=$(echo "scale=1; $TOTAL_CPU * 0.8" | bc)
      K8S_MEMORY_MB=$(echo "scale=0; $TOTAL_MEMORY_MB * 0.8" | bc | awk '{print int($1)}')
      K8S_MEMORY_GB=$(echo "scale=1; $K8S_MEMORY_MB/1024" | bc)
      echo -e "${BLUE}Available resources for Kubernetes (80% of total): $K8S_CPU CPU, $K8S_MEMORY_GB GB RAM${NC}"
      
      # Calculate Longhorn replicas with default value for cluster fallback
      NODES_COUNT=""  # Cannot determine nodes in cluster fallback mode
      calculate_longhorn_replicas
    else
      # Get the number of nodes in the cluster
      NODES_COUNT=$($KUBECTL_CMD get nodes --no-headers | wc -l | tr -d ' ')
      echo -e "${GREEN}Nodes in cluster: $NODES_COUNT${NC}"
      
      # Calculate optimal Longhorn replicas based on node count
      calculate_longhorn_replicas
      
      echo -e "${BLUE}Calculating actually available resources in the cluster...${NC}"
      
      # Get total allocatable resources
      ALLOCATABLE_CPU=0
      ALLOCATABLE_MEMORY_KI=0
      
      # Use a loop to process each node and handle units correctly
      for node in $($KUBECTL_CMD get nodes -o name); do
        # Get allocatable CPU for this node
        node_cpu=$($KUBECTL_CMD get ${node} -o jsonpath='{.status.allocatable.cpu}')
        # Handle format (can be in millicores)
        if [[ ${node_cpu} == *m ]]; then
          node_cpu=$(echo ${node_cpu} | sed 's/m//')
          node_cpu_decimal=$(echo "scale=3; ${node_cpu}/1000" | bc)
        else
          node_cpu_decimal=${node_cpu}
        fi
        ALLOCATABLE_CPU=$(echo "${ALLOCATABLE_CPU} + ${node_cpu_decimal}" | bc)
        
        # Get allocatable memory for this node
        node_memory=$($KUBECTL_CMD get ${node} -o jsonpath='{.status.allocatable.memory}')
        # Extract numeric value and unit
        node_memory_value=$(echo ${node_memory} | sed 's/[^0-9]*//g')
        node_memory_unit=$(echo ${node_memory} | sed 's/[0-9]*//g')
        
        # Convert to Ki
        case ${node_memory_unit} in
          Ki) node_memory_ki=${node_memory_value} ;;
          Mi) node_memory_ki=$((node_memory_value * 1024)) ;;
          Gi) node_memory_ki=$((node_memory_value * 1024 * 1024)) ;;
          Ti) node_memory_ki=$((node_memory_value * 1024 * 1024 * 1024)) ;;
          *)  node_memory_ki=$((node_memory_value / 1024)) ;; # Assume bytes if no unit
        esac
        
        ALLOCATABLE_MEMORY_KI=$((ALLOCATABLE_MEMORY_KI + node_memory_ki))
      done
      
      # Store total allocatable values
      TOTAL_ALLOCATABLE_CPU=${ALLOCATABLE_CPU}
      TOTAL_ALLOCATABLE_MEMORY_KI=${ALLOCATABLE_MEMORY_KI}
      
      # Get resources already used by all running pods (simplified version)
      echo -e "${BLUE}Calculating resources currently used by running pods...${NC}"
      
      # Simplified version of used resources calculation
      USED_CPU_MILLICORES=0
      USED_MEMORY_KI=0
      
      # Try to use kubectl top if available, otherwise use an approximate calculation
      if $KUBECTL_CMD top pods --all-namespaces &>/dev/null; then
        # Use kubectl top to get actual usage
        kubectl_top_output=$($KUBECTL_CMD top pods --all-namespaces --no-headers 2>/dev/null)
        if [ -n "$kubectl_top_output" ]; then
          USED_CPU=$(echo "$kubectl_top_output" | awk '{cpu+=$3} END {print cpu}' | sed 's/m//')
          USED_MEMORY_MI=$(echo "$kubectl_top_output" | awk '{mem+=$4} END {print mem}' | sed 's/Mi//')
          USED_MEMORY_KI=$((USED_MEMORY_MI * 1024))
          USED_CPU_DECIMAL=$(echo "scale=1; $USED_CPU/1000" | bc)
        fi
      else
        # Fallback: conservative estimate (use 30% of allocatable resources)
        USED_CPU_DECIMAL=$(echo "scale=1; $ALLOCATABLE_CPU * 0.3" | bc)
        USED_MEMORY_KI=$((ALLOCATABLE_MEMORY_KI * 30 / 100))
      fi
      
      # Convert to readable units
      USED_MEMORY_MB=$((USED_MEMORY_KI / 1024))
      USED_MEMORY_GB=$(echo "scale=1; $USED_MEMORY_MB/1024" | bc)
      
      echo -e "${YELLOW}Currently used resources: $USED_CPU_DECIMAL CPU, $USED_MEMORY_GB GB RAM${NC}"
      
      # Calculate available resources (allocatable - used)
      AVAILABLE_CPU=$(echo "$ALLOCATABLE_CPU - $USED_CPU_DECIMAL" | bc)
      AVAILABLE_MEMORY_MB=$((ALLOCATABLE_MEMORY_KI / 1024 - USED_MEMORY_MB))
      
      # Keep decimal value for TOTAL_CPU without rounding
      TOTAL_CPU=$AVAILABLE_CPU
      TOTAL_MEMORY_MB=$AVAILABLE_MEMORY_MB
      
      # Show complete info with decimals
      ALLOC_MEMORY_GB=$(echo "scale=1; $ALLOCATABLE_MEMORY_KI/1024/1024" | bc)
      AVAIL_MEMORY_GB=$(echo "scale=1; $AVAILABLE_MEMORY_MB/1024" | bc)
      
      echo -e "${GREEN}Total allocatable resources in cluster: ${ALLOCATABLE_CPU} CPU, ${ALLOC_MEMORY_GB} GB RAM${NC}"
      echo -e "${GREEN}Actually available resources: ${AVAILABLE_CPU} CPU, ${AVAIL_MEMORY_GB} GB RAM${NC}"
      
      # Use 80% of available resources for the application
      K8S_CPU=$(echo "scale=1; $TOTAL_CPU * 0.8" | bc) 
      K8S_MEMORY_MB=$(echo "scale=0; $TOTAL_MEMORY_MB * 0.8" | bc | awk '{print int($1)}')
      K8S_MEMORY_GB=$(echo "scale=1; $K8S_MEMORY_MB/1024" | bc)
      echo -e "${BLUE}Available resources for application (80% of cluster available): $K8S_CPU CPU, $K8S_MEMORY_GB GB RAM${NC}"
    fi
  fi
  
  # Detect GPU resources (both local and cluster detection)
  detect_gpu_resources
  
  # Ensure K8S_CPU_FORMATTED exists for resource calculations
  K8S_CPU_FORMATTED=$K8S_CPU
}

# Function to detect available storage in the cluster
detect_cluster_storage() {
  echo -e "${BLUE}Detecting available storage...${NC}"
  AVAILABLE_STORAGE_GB=0
  STORAGE_DETECTION_METHOD="unknown"

  # Use the user's choice for resource detection
  if [ "$DETECTION_CHOICE" = "1" ]; then
    # Local detection - detect storage from the system where the script is running
    echo -e "${BLUE}Detecting storage from local system...${NC}"
    
    # Automatically detect available storage
    OS=$(uname -s)
    
    if [[ "$OS" == "Linux" ]]; then
      # On Linux, use df to detect available space in root partition
      AVAILABLE_STORAGE_KB=$(df / | awk 'NR==2 {print $4}')
      AVAILABLE_STORAGE_GB=$((AVAILABLE_STORAGE_KB / 1024 / 1024))
      STORAGE_DETECTION_METHOD="df Linux (root partition)"
    elif [[ "$OS" == "Darwin" ]]; then
      # On macOS, use df to detect available space
      AVAILABLE_STORAGE_BYTES=$(df -k / | awk 'NR==2 {print $4}')
      AVAILABLE_STORAGE_GB=$((AVAILABLE_STORAGE_BYTES / 1024 / 1024))
      STORAGE_DETECTION_METHOD="df macOS (root partition)"
    else
      echo -e "${YELLOW}Operating system not recognized. Requesting manual input.${NC}"
      read -p "Enter total storage available for Lair in GB (e.g. 50, 100): " USER_STORAGE_GB
      if [[ "$USER_STORAGE_GB" =~ ^[0-9]+$ ]] && [ "$USER_STORAGE_GB" -gt 0 ]; then
        AVAILABLE_STORAGE_GB=$USER_STORAGE_GB
        STORAGE_DETECTION_METHOD="User input"
      else
        echo -e "${RED}Invalid input. Setting to 50GB as emergency default.${NC}"
        AVAILABLE_STORAGE_GB=50 # Emergency default
        STORAGE_DETECTION_METHOD="Emergency default"
      fi
    fi
    
  elif [ "$DETECTION_CHOICE" = "2" ]; then
    # Cluster detection - detect storage from remote Kubernetes cluster
    echo -e "${BLUE}Detecting storage from Kubernetes cluster...${NC}"
    
    # Check if we can access the cluster
    if [ "$K8S_CLUSTER_ACCESSIBLE" = "false" ] || ! $KUBECTL_CMD get nodes &>/dev/null; then
      echo -e "${RED}Unable to access Kubernetes cluster to detect storage.${NC}"
      echo -e "${YELLOW}Requesting manual input for storage.${NC}"
      read -p "Enter total storage available in cluster in GB (e.g. 50, 100): " USER_STORAGE_GB
      if [[ "$USER_STORAGE_GB" =~ ^[0-9]+$ ]] && [ "$USER_STORAGE_GB" -gt 0 ]; then
        AVAILABLE_STORAGE_GB=$USER_STORAGE_GB
        STORAGE_DETECTION_METHOD="User input (cluster inaccessible)"
      else
        echo -e "${RED}Invalid input. Setting to 50GB as emergency default.${NC}"
        AVAILABLE_STORAGE_GB=50
        STORAGE_DETECTION_METHOD="Emergency default"
      fi
    else
      # Try different methods to detect storage from cluster
      
      # Method 1: Try to get storage from Longhorn (if installed)
      if $KUBECTL_CMD get sc longhorn &>/dev/null; then
        echo -e "${BLUE}Found Longhorn StorageClass, attempting storage detection...${NC}"
        # Try to get available storage from Longhorn nodes
        longhorn_available_bytes=$($KUBECTL_CMD get nodes.longhorn.io -n longhorn-system -o jsonpath='{.items[*].status.diskStatus.*.storageAvailable}' 2>/dev/null)
        if [ -n "$longhorn_available_bytes" ]; then
          total_longhorn_storage=0
          for storage_val in $longhorn_available_bytes; do
            total_longhorn_storage=$((total_longhorn_storage + storage_val))
          done
          AVAILABLE_STORAGE_GB=$(echo "scale=0; $total_longhorn_storage / 1024 / 1024 / 1024" | bc)
          STORAGE_DETECTION_METHOD="Longhorn (available storage)"
        fi
      fi
      
      # Method 2: Fallback - estimate based on node capacity
      if [ "$AVAILABLE_STORAGE_GB" -eq 0 ]; then
        echo -e "${BLUE}Attempting storage estimation based on cluster nodes...${NC}"
        # Try to estimate storage from nodes (approximate method)
        # This is a fallback that might not be accurate
        node_count=$($KUBECTL_CMD get nodes --no-headers | wc -l | tr -d ' ')
        if [ "$node_count" -gt 0 ]; then
          # Conservative estimate: 50GB per node as default
          estimated_storage=$((node_count * 50))
          echo -e "${YELLOW}Storage estimate based on $node_count nodes: ${estimated_storage}GB${NC}"
          read -p "Confirm this estimate or enter a manual value? (y to confirm, n to enter manually): " CONFIRM_ESTIMATE
          if [[ "$CONFIRM_ESTIMATE" == "y" || "$CONFIRM_ESTIMATE" == "Y" ]]; then
            AVAILABLE_STORAGE_GB=$estimated_storage
            STORAGE_DETECTION_METHOD="Node-based estimate ($node_count x 50GB)"
          else
            read -p "Enter total storage available in cluster in GB: " USER_STORAGE_GB
            if [[ "$USER_STORAGE_GB" =~ ^[0-9]+$ ]] && [ "$USER_STORAGE_GB" -gt 0 ]; then
              AVAILABLE_STORAGE_GB=$USER_STORAGE_GB
              STORAGE_DETECTION_METHOD="User input"
            else
              AVAILABLE_STORAGE_GB=$estimated_storage
              STORAGE_DETECTION_METHOD="Fallback estimate"
            fi
          fi
        fi
      fi
      
      # Method 3: Last fallback - ask the user
      if [ "$AVAILABLE_STORAGE_GB" -eq 0 ]; then
        echo -e "${YELLOW}Could not automatically detect cluster storage.${NC}"
        read -p "Enter total storage available in cluster in GB: " USER_STORAGE_GB
        if [[ "$USER_STORAGE_GB" =~ ^[0-9]+$ ]] && [ "$USER_STORAGE_GB" -gt 0 ]; then
          AVAILABLE_STORAGE_GB=$USER_STORAGE_GB
          STORAGE_DETECTION_METHOD="User input"
        else
          echo -e "${RED}Invalid input. Setting to 100GB as default.${NC}"
          AVAILABLE_STORAGE_GB=100
          STORAGE_DETECTION_METHOD="Default cluster"
        fi
      fi
    fi
  fi
  
  # Verify that detection is reasonable
  if [ "$AVAILABLE_STORAGE_GB" -lt 5 ]; then
    echo -e "${YELLOW}Detected storage very low (${AVAILABLE_STORAGE_GB}GB). There might be detection issues.${NC}"
    read -p "Do you want to enter the value manually? (y/n) [default: n]: " MANUAL_INPUT
    MANUAL_INPUT=${MANUAL_INPUT:-n}
    if [[ "$MANUAL_INPUT" == "y" || "$MANUAL_INPUT" == "Y" ]]; then
      read -p "Enter available storage in GB: " USER_STORAGE_GB
      if [[ "$USER_STORAGE_GB" =~ ^[0-9]+$ ]] && [ "$USER_STORAGE_GB" -gt 0 ]; then
        AVAILABLE_STORAGE_GB=$USER_STORAGE_GB
        STORAGE_DETECTION_METHOD="User input (correction)"
      fi
    fi
  fi
  
  # Apply configurable safety factor to available storage
  USABLE_STORAGE_GB=$(echo "$AVAILABLE_STORAGE_GB * $STORAGE_SAFETY_PERCENTAGE / 100" | bc | awk '{print int($1)}')
  
  if [ "$DETECTION_CHOICE" = "1" ]; then
    echo -e "${GREEN}Available storage detected from local system (method: $STORAGE_DETECTION_METHOD): $AVAILABLE_STORAGE_GB GB${NC}"
  else
    echo -e "${GREEN}Available storage detected from cluster (method: $STORAGE_DETECTION_METHOD): $AVAILABLE_STORAGE_GB GB${NC}"
  fi
  echo -e "${GREEN}Actually usable storage for Lair (${STORAGE_SAFETY_PERCENTAGE}% of available): $USABLE_STORAGE_GB GB${NC}"
  
  # Export the variable to use it globally
  export CLUSTER_AVAILABLE_STORAGE_GB=$USABLE_STORAGE_GB
}

# Function to detect GPU from Kubernetes cluster
detect_gpu_from_cluster() {
  echo -e "${BLUE}Detecting GPU resources from Kubernetes cluster...${NC}"
  HAS_GPU="n"

  if [ "$K8S_CLUSTER_ACCESSIBLE" = "true" ]; then
    # Check for nodes with GPU resources
    gpu_nodes=$($KUBECTL_CMD get nodes -o jsonpath='{.items[?(@.status.capacity."nvidia.com/gpu")].metadata.name}' 2>/dev/null)
    
    # Get total GPU count
    total_gpus=$($KUBECTL_CMD get nodes -o jsonpath='{.items[*].status.capacity."nvidia\.com/gpu"}' 2>/dev/null | tr ' ' '\n' | awk '{sum += $1} END {print sum}')

    if [ -n "$gpu_nodes" ] && [ "$total_gpus" -gt 0 ]; then
      HAS_GPU="y"
      echo -e "${GREEN}🎮 GPU Resources Detected in Cluster${NC}"
      echo -e "${GREEN}   ✅ Nodes with GPU: $gpu_nodes${NC}"
      echo -e "${GREEN}   ✅ Total GPUs available: $total_gpus${NC}"
      echo -e "${GREEN}   ✅ AI workloads can use GPU acceleration${NC}"
    else
      echo -e "${YELLOW}ℹ️  No GPU resources detected in the cluster${NC}"
      echo -e "${YELLOW}   CPU-only mode will be used for AI workloads${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️  Cannot detect GPU resources - cluster is not accessible${NC}"
    echo -e "${YELLOW}   Assuming CPU-only mode${NC}"
  fi

  # Export for other scripts
  export HAS_GPU
}

# Function to detect GPU from local system
detect_gpu_from_local() {
  echo -e "${BLUE}Detecting GPU resources from local system...${NC}"
  HAS_GPU="n"
  
  # Check if timeout command is available
  if command -v timeout &>/dev/null; then
    TIMEOUT_CMD="timeout 5"
    TIMEOUT_LONG="timeout 10"
  else
    TIMEOUT_CMD=""
    TIMEOUT_LONG=""
    echo -e "${YELLOW}   Warning: timeout command not available, commands may hang${NC}"
  fi
  
  # Check for NVIDIA GPUs using nvidia-smi
  if command -v nvidia-smi &>/dev/null; then
    if [ -n "$TIMEOUT_CMD" ]; then
      nvidia_test=$(${TIMEOUT_CMD} nvidia-smi &>/dev/null 2>&1 && echo "ok" || echo "fail")
    else
      nvidia_test=$(nvidia-smi &>/dev/null 2>&1 && echo "ok" || echo "fail")
    fi
    
    if [ "$nvidia_test" = "ok" ]; then
      if [ -n "$TIMEOUT_CMD" ]; then
        gpu_count=$(${TIMEOUT_CMD} nvidia-smi --query-gpu=count --format=csv,noheader,nounits 2>/dev/null | head -1)
        gpu_names=$(${TIMEOUT_CMD} nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
      else
        gpu_count=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits 2>/dev/null | head -1)
        gpu_names=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | tr '\n' ', ' | sed 's/, $//')
      fi
      
      if [ -n "$gpu_count" ] && [ "$gpu_count" -gt 0 ]; then
        HAS_GPU="y"
        echo -e "${GREEN}🎮 NVIDIA GPU Detected on Local System${NC}"
        echo -e "${GREEN}   ✅ GPU Count: $gpu_count${NC}"
        echo -e "${GREEN}   ✅ GPU Models: $gpu_names${NC}"
        echo -e "${GREEN}   ✅ AI workloads can use GPU acceleration${NC}"
      else
        echo -e "${YELLOW}ℹ️  nvidia-smi found but no GPUs detected${NC}"
      fi
    else
      echo -e "${YELLOW}ℹ️  nvidia-smi found but not working (driver issues or timeout)${NC}"
    fi
  else
    echo -e "${YELLOW}ℹ️  nvidia-smi not found - checking for other GPU indicators${NC}"
    
    # Check for GPU-related files/devices on Linux
    if [[ "$(uname -s)" == "Linux" ]]; then
      if [ -d "/proc/driver/nvidia" ]; then
        echo -e "${YELLOW}   Found NVIDIA driver files, but nvidia-smi unavailable${NC}"
        echo -e "${YELLOW}   GPU might be present but not properly configured${NC}"
      elif ls /dev/nvidia* &>/dev/null 2>&1; then
        echo -e "${YELLOW}   Found NVIDIA device files${NC}"
        echo -e "${YELLOW}   GPU might be present but drivers may need installation${NC}"
      elif command -v lspci &>/dev/null; then
        if [ -n "$TIMEOUT_LONG" ]; then
          echo -e "${YELLOW}   Checking PCI devices for NVIDIA GPU...${NC}"
          gpu_pci=$(${TIMEOUT_LONG} lspci 2>/dev/null | grep -i "vga\|3d\|display" | grep -i "nvidia" 2>/dev/null || true)
          if [ -n "$gpu_pci" ]; then
            echo -e "${YELLOW}   Found NVIDIA GPU in PCI devices:${NC}"
            echo -e "${YELLOW}   $gpu_pci${NC}"
            echo -e "${YELLOW}   Drivers may need to be installed${NC}"
          else
            echo -e "${YELLOW}   No NVIDIA GPU found in PCI devices${NC}"
          fi
        else
          echo -e "${YELLOW}   Skipping PCI device scan (no timeout available, could hang)${NC}"
        fi
      else
        echo -e "${YELLOW}   lspci command not available${NC}"
      fi
    elif [[ "$(uname -s)" == "Darwin" ]]; then
      # On macOS, check for Apple Silicon GPUs or discrete GPUs
      echo -e "${YELLOW}   Checking macOS GPU information...${NC}"
      if [ -n "$TIMEOUT_LONG" ]; then
        gpu_check=$(${TIMEOUT_LONG} system_profiler SPDisplaysDataType 2>/dev/null | grep -q "Apple\|AMD\|NVIDIA" 2>/dev/null && echo "found" || echo "not_found")
        if [ "$gpu_check" = "found" ]; then
          gpu_info=$(${TIMEOUT_LONG} system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | head -1 | awk -F: '{print $2}' | xargs 2>/dev/null || echo "Unknown")
          echo -e "${YELLOW}   Found GPU on macOS: $gpu_info${NC}"
          echo -e "${YELLOW}   Note: AI workloads typically require NVIDIA CUDA support${NC}"
        else
          echo -e "${YELLOW}   Could not detect GPU information on macOS${NC}"
        fi
      else
        echo -e "${YELLOW}   Skipping macOS GPU detection (no timeout available)${NC}"
      fi
    fi
    
    echo -e "${YELLOW}   CPU-only mode will be used for AI workloads${NC}"
  fi
  
  # Export for other scripts
  export HAS_GPU
}

# Unified function to detect GPU resources
detect_gpu_resources() {
  echo -e "${BLUE}🎮 GPU Detection${NC}"
  echo "─────────────────────────────────────────────────────────────────────────────"
  
  if [ "$DETECTION_CHOICE" = "1" ]; then
    # Local system detection
    detect_gpu_from_local
  elif [ "$DETECTION_CHOICE" = "2" ]; then
    # Cluster detection
    detect_gpu_from_cluster
  else
    echo -e "${YELLOW}⚠️  Unknown detection choice, assuming CPU-only${NC}"
    HAS_GPU="n"
    export HAS_GPU
  fi
  
  echo ""
}
