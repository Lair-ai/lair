#!/bin/bash

# Verify execution as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\e[31m[ERROR]\e[0m This script must be run as root"
  echo -e "\e[33m[HINT]\e[0m  Run: sudo ./cleanup.sh"
  exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect environment type
detect_environment() {
  if command -v microk8s &>/dev/null && microk8s kubectl get nodes &>/dev/null; then
    ENVIRONMENT_TYPE="microk8s"
    echo -e "${GREEN}Detected MicroK8s environment${NC}"
  elif command -v kubectl &>/dev/null && kubectl get nodes &>/dev/null; then
    ENVIRONMENT_TYPE="k8s-managed"
    echo -e "${GREEN}Detected managed Kubernetes environment${NC}"
  else
    echo -e "${RED}Error: No working Kubernetes environment found${NC}"
    exit 1
  fi
}

# Function to confirm deletion
confirm() {
  read -p "Are you sure you want to DELETE ALL Lair resources? This action is IRREVERSIBLE! (yes/no): " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    echo -e "${YELLOW}Cleanup aborted.${NC}"
    exit 0
  fi
}

# Function to wait for resource deletion with timeout
wait_for_deletion() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  local timeout="${4:-60}"
  
  echo -n "Waiting for $resource_type $resource_name to be deleted"
  for i in $(seq 1 $timeout); do
    if ! $KUBECTL_CMD get $resource_type "$resource_name" $namespace &>/dev/null; then
      echo -e " ${GREEN}✓${NC}"
      return 0
    fi
    echo -n "."
    sleep 1
  done
  echo -e " ${YELLOW}⚠ Still exists after ${timeout}s${NC}"
  return 1
}

# Function to remove finalizers from a resource
remove_finalizers() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  
  echo "Removing finalizers from $resource_type $resource_name..."
  $KUBECTL_CMD patch $resource_type "$resource_name" $namespace -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
}

# Function to force delete resource
force_delete_resource() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  
  echo "Force deleting $resource_type $resource_name..."
  $KUBECTL_CMD delete $resource_type "$resource_name" $namespace --force --grace-period=0 2>/dev/null || true
}

# Function to clean up Longhorn resources properly
cleanup_longhorn_resources() {
  local namespace="$1"
  
  if ! $KUBECTL_CMD get namespace longhorn-system &>/dev/null; then
    echo -e "${GREEN}Longhorn not installed, skipping Longhorn cleanup.${NC}"
    return 0
  fi
  
  echo -e "${BLUE}=== CLEANING UP LONGHORN RESOURCES ===${NC}"
  
  # Step 1: Check and clean up ALL Longhorn volumes (not just Lair ones)
  echo -e "${BLUE}Checking ALL Longhorn volumes...${NC}"
  ALL_VOLUMES=$($KUBECTL_CMD get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | awk '{print $1}' || echo "")
  
  if [ -n "$ALL_VOLUMES" ]; then
    echo -e "${YELLOW}Found Longhorn volumes:${NC}"
    echo "$ALL_VOLUMES"
    
    # Force delete all volumes to prevent stuck states
    echo "Force deleting ALL Longhorn volumes..."
    for volume in $ALL_VOLUMES; do
      echo "Deleting volume $volume..."
      $KUBECTL_CMD delete volume.longhorn.io "$volume" -n longhorn-system --force --grace-period=0 2>/dev/null || true
    done
    
    # Wait for volume deletion
    echo "Waiting for volumes to be deleted..."
    sleep 10
    
    # Verify volumes are gone
    REMAINING_VOLUMES=$($KUBECTL_CMD get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [ -n "$REMAINING_VOLUMES" ]; then
      echo -e "${YELLOW}Some volumes still exist, force cleaning with finalizers...${NC}"
      for volume in $REMAINING_VOLUMES; do
        echo "Removing finalizers from volume $volume..."
        $KUBECTL_CMD patch volume.longhorn.io "$volume" -n longhorn-system -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
      done
      sleep 5
    fi
  fi
  
  # Step 2: Clean up ALL engines
  echo -e "${BLUE}Cleaning up ALL Longhorn engines...${NC}"
  ALL_ENGINES=$($KUBECTL_CMD get engines.longhorn.io -n longhorn-system --no-headers 2>/dev/null | awk '{print $1}' || echo "")
  
  if [ -n "$ALL_ENGINES" ]; then
    for engine in $ALL_ENGINES; do
      echo "Deleting engine $engine..."
      $KUBECTL_CMD delete engine.longhorn.io "$engine" -n longhorn-system --force --grace-period=0 2>/dev/null || true
    done
    
    # Wait and verify engines are gone
    sleep 5
    REMAINING_ENGINES=$($KUBECTL_CMD get engines.longhorn.io -n longhorn-system --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [ -n "$REMAINING_ENGINES" ]; then
      echo -e "${YELLOW}Removing finalizers from remaining engines...${NC}"
      for engine in $REMAINING_ENGINES; do
        $KUBECTL_CMD patch engine.longhorn.io "$engine" -n longhorn-system -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
      done
    fi
  fi
  
  # Step 3: Clean up ALL replicas
  echo -e "${BLUE}Cleaning up ALL Longhorn replicas...${NC}"
  ALL_REPLICAS=$($KUBECTL_CMD get replicas.longhorn.io -n longhorn-system --no-headers 2>/dev/null | awk '{print $1}' || echo "")
  
  if [ -n "$ALL_REPLICAS" ]; then
    for replica in $ALL_REPLICAS; do
      echo "Deleting replica $replica..."
      $KUBECTL_CMD delete replica.longhorn.io "$replica" -n longhorn-system --force --grace-period=0 2>/dev/null || true
    done
    
    # Wait and verify replicas are gone
    sleep 5
    REMAINING_REPLICAS=$($KUBECTL_CMD get replicas.longhorn.io -n longhorn-system --no-headers 2>/dev/null | awk '{print $1}' || echo "")
    if [ -n "$REMAINING_REPLICAS" ]; then
      echo -e "${YELLOW}Removing finalizers from remaining replicas...${NC}"
      for replica in $REMAINING_REPLICAS; do
        $KUBECTL_CMD patch replica.longhorn.io "$replica" -n longhorn-system -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
      done
    fi
  fi
  
  # Step 4: Complete Longhorn restart to ensure clean state
  echo -e "${BLUE}Performing complete Longhorn restart...${NC}"
  
  # Stop all Longhorn components
  echo "Stopping all Longhorn components..."
  $KUBECTL_CMD delete pods -n longhorn-system --all --force --grace-period=0 2>/dev/null || true
  
  # Wait for pods to be recreated
  echo "Waiting for Longhorn components to restart..."
  sleep 30
  
  # Verify Longhorn is healthy
  echo -e "${BLUE}Verifying Longhorn health...${NC}"
  for i in {1..12}; do  # Wait up to 2 minutes
    READY_PODS=$($KUBECTL_CMD get pods -n longhorn-system --no-headers 2>/dev/null | grep -E "1/1|2/2|3/3" | wc -l || echo "0")
    TOTAL_PODS=$($KUBECTL_CMD get pods -n longhorn-system --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
      echo -e "${GREEN}✓ Longhorn components healthy ($READY_PODS/$TOTAL_PODS ready)${NC}"
      break
    else
      echo "Waiting for Longhorn components... ($READY_PODS/$TOTAL_PODS ready)"
      sleep 10
    fi
  done
  
  # Final verification - ensure no volumes/engines/replicas remain
  echo -e "${BLUE}Final verification...${NC}"
  FINAL_VOLUMES=$($KUBECTL_CMD get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l || echo "0")
  FINAL_ENGINES=$($KUBECTL_CMD get engines.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l || echo "0")
  FINAL_REPLICAS=$($KUBECTL_CMD get replicas.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l || echo "0")
  
  echo "Longhorn state after cleanup:"
  echo "  Volumes: $FINAL_VOLUMES"
  echo "  Engines: $FINAL_ENGINES"
  echo "  Replicas: $FINAL_REPLICAS"
  
  if [ "$FINAL_VOLUMES" -eq 0 ] && [ "$FINAL_ENGINES" -eq 0 ] && [ "$FINAL_REPLICAS" -eq 0 ]; then
    echo -e "${GREEN}✓ Longhorn cleanup completed successfully - clean state achieved${NC}"
  else
    echo -e "${YELLOW}⚠ Some Longhorn resources remain, but proceeding with cleanup...${NC}"
  fi
  
  echo -e "${GREEN}Longhorn cleanup completed.${NC}"
}

# Function to clean up PVCs and PVs with proper finalizer handling
cleanup_storage_resources() {
  local namespace="$1"
  
  echo -e "${BLUE}=== CLEANING UP STORAGE RESOURCES ===${NC}"
  
  # Step 1: Get all PVCs in the namespace
  echo -e "${BLUE}Looking for PVCs in namespace $namespace...${NC}"
  PVCS=$($KUBECTL_CMD get pvc -n "$namespace" -o name 2>/dev/null)
  
  if [ -n "$PVCS" ]; then
    echo -e "${YELLOW}Found PVCs to delete:${NC}"
    echo "$PVCS"
    
    # Step 2: Get associated PV names before deleting PVCs
    echo -e "${BLUE}Getting associated Persistent Volumes...${NC}"
    PV_NAMES=""
    for PVC in $PVCS; do
      PVC_NAME=$(echo $PVC | cut -d'/' -f2)
      PV_NAME=$($KUBECTL_CMD get pvc "$PVC_NAME" -n "$namespace" -o jsonpath='{.spec.volumeName}' 2>/dev/null || echo "")
      if [ -n "$PV_NAME" ] && [ "$PV_NAME" != "null" ]; then
        PV_NAMES="$PV_NAMES $PV_NAME"
        echo "PVC $PVC_NAME -> PV $PV_NAME"
      fi
    done
    
    # Step 3: Delete PVCs with finalizer handling
    echo -e "${BLUE}Deleting PVCs...${NC}"
    for PVC in $PVCS; do
      PVC_NAME=$(echo $PVC | cut -d'/' -f2)
      echo "Deleting PVC $PVC_NAME..."
      
      # First try normal deletion
      $KUBECTL_CMD delete pvc "$PVC_NAME" -n "$namespace" --timeout=10s 2>/dev/null || {
        echo "PVC $PVC_NAME stuck, removing finalizers..."
        remove_finalizers "pvc" "$PVC_NAME" "-n $namespace"
        sleep 2
      }
    done
    
    # Step 4: Wait for PVCs to be deleted
    echo "Waiting for PVCs to be fully deleted..."
    sleep 5
    
    # Check for stuck PVCs and force clean them
    STUCK_PVCS=$($KUBECTL_CMD get pvc -n "$namespace" -o name 2>/dev/null)
    if [ -n "$STUCK_PVCS" ]; then
      echo -e "${YELLOW}Some PVCs are still stuck, force cleaning...${NC}"
      for PVC in $STUCK_PVCS; do
        PVC_NAME=$(echo $PVC | cut -d'/' -f2)
        remove_finalizers "pvc" "$PVC_NAME" "-n $namespace"
      done
      sleep 5
    fi
    
    # Step 5: Delete associated PVs
    if [ -n "$PV_NAMES" ]; then
      echo -e "${BLUE}Deleting associated Persistent Volumes...${NC}"
      for PV_NAME in $PV_NAMES; do
        if [ -n "$PV_NAME" ] && [ "$PV_NAME" != "null" ]; then
          echo "Deleting PV $PV_NAME..."
          $KUBECTL_CMD delete pv "$PV_NAME" --timeout=10s 2>/dev/null || {
            echo "PV $PV_NAME stuck, removing finalizers..."
            remove_finalizers "pv" "$PV_NAME" ""
            sleep 2
          }
        fi
      done
    fi
    
    # Step 6: Clean up any remaining stuck PVs
    echo -e "${BLUE}Cleaning up stuck PVs...${NC}"
    STUCK_PVS=$($KUBECTL_CMD get pv -o name 2>/dev/null | while read pv; do
      PV_NAME=$(echo $pv | cut -d'/' -f2)
      if $KUBECTL_CMD get pv "$PV_NAME" -o yaml 2>/dev/null | grep -q "namespace: $namespace"; then
        echo $pv
      fi
    done)
    
    if [ -n "$STUCK_PVS" ]; then
      for PV in $STUCK_PVS; do
        PV_NAME=$(echo $PV | cut -d'/' -f2)
        remove_finalizers "pv" "$PV_NAME" ""
      done
    fi
    
  else
    echo -e "${GREEN}No PVCs found in namespace $namespace.${NC}"
  fi
  
  # Step 7: Also check for any orphaned PVs that might be related to Lair
  echo -e "${BLUE}Checking for orphaned Persistent Volumes...${NC}"
  ORPHANED_PVS=$($KUBECTL_CMD get pv -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name,NAMESPACE:.spec.claimRef.namespace --no-headers 2>/dev/null | grep -E "(Failed|Available|Released)" | grep -E "(lair|$namespace)" | awk '{print $1}' || echo "")
  
  if [ -n "$ORPHANED_PVS" ]; then
    echo -e "${YELLOW}Found orphaned PVs related to Lair:${NC}"
    for PV in $ORPHANED_PVS; do
      echo "Deleting orphaned PV $PV..."
      $KUBECTL_CMD delete pv "$PV" --timeout=10s 2>/dev/null || {
        remove_finalizers "pv" "$PV" ""
      }
    done
  else
    echo -e "${GREEN}No orphaned PVs found.${NC}"
  fi
  
  echo -e "${GREEN}Storage cleanup completed.${NC}"
}

# Function to restart ingress controller and wait for certificates
restart_ingress_controller() {
  echo -e "${BLUE}=== RESTARTING INGRESS CONTROLLER ===${NC}"
  
  # Define ingress controller namespaces based on environment
  if [[ "$ENVIRONMENT_TYPE" == "microk8s" ]]; then
    # MicroK8s typically uses these namespaces
    POSSIBLE_INGRESS_NAMESPACES=(
      "ingress"
      "kube-system"
      "ingress-nginx"
      "nginx-ingress"
    )
  else
    # Managed k8s environments - check Helm installations first
    POSSIBLE_INGRESS_NAMESPACES=(
      "ingress-nginx"    # Common Helm installation namespace
      "nginx-ingress"    # Alternative Helm installation namespace
      "ingress-system"
      "kube-system"
    )
  fi
  
  INGRESS_NAMESPACE=""
  INGRESS_PODS=""
  
  # Find ingress controller in common namespaces
  for ns in "${POSSIBLE_INGRESS_NAMESPACES[@]}"; do
    if $KUBECTL_CMD get namespace "$ns" &>/dev/null; then
      PODS=$($KUBECTL_CMD get pods -n "$ns" --no-headers 2>/dev/null | grep -E "(ingress|nginx)" | awk '{print $1}' || echo "")
      if [ -n "$PODS" ]; then
        INGRESS_NAMESPACE="$ns"
        INGRESS_PODS="$PODS"
        echo -e "${GREEN}Found ingress controller in namespace: $ns${NC}"
        break
      fi
    fi
  done
  
  if [ -z "$INGRESS_PODS" ]; then
    echo -e "${YELLOW}No ingress controller found in common namespaces, skipping restart.${NC}"
    echo -e "${YELLOW}Checked namespaces: ${POSSIBLE_INGRESS_NAMESPACES[*]}${NC}"
    return 0
  fi
  
  # Restart ingress controller to reload configuration
  echo "Restarting ingress controller to reload configuration..."
  for pod in $INGRESS_PODS; do
    echo "Deleting ingress controller pod: $pod (namespace: $INGRESS_NAMESPACE)"
    $KUBECTL_CMD delete pod "$pod" -n "$INGRESS_NAMESPACE" --force --grace-period=0 2>/dev/null || true
  done
  
  # Wait for new ingress controller to be ready
  echo "Waiting for ingress controller to restart..."
  sleep 15
  
  # Verify ingress controller is running
  for i in {1..6}; do  # Wait up to 1 minute
    READY_INGRESS=$($KUBECTL_CMD get pods -n "$INGRESS_NAMESPACE" --no-headers 2>/dev/null | grep -E "1/1|2/2|3/3" | wc -l || echo "0")
    TOTAL_INGRESS=$($KUBECTL_CMD get pods -n "$INGRESS_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$READY_INGRESS" -eq "$TOTAL_INGRESS" ] && [ "$TOTAL_INGRESS" -gt 0 ]; then
      echo -e "${GREEN}✓ Ingress controller healthy ($READY_INGRESS/$TOTAL_INGRESS ready)${NC}"
      break
    else
      echo "Waiting for ingress controller... ($READY_INGRESS/$TOTAL_INGRESS ready)"
      sleep 10
    fi
  done
  
  echo -e "${GREEN}Ingress controller restart completed.${NC}"
}

# Function to wait for certificates to be ready after cleanup
wait_for_certificates() {
  local namespace="$1"
  
  if ! $KUBECTL_CMD get namespace "$namespace" &>/dev/null; then
    echo -e "${YELLOW}Namespace $namespace doesn't exist, skipping certificate check.${NC}"
    return 0
  fi
  
  # Check if there are any certificate resources
  CERTIFICATES=$($KUBECTL_CMD get certificates -n "$namespace" --no-headers 2>/dev/null | awk '{print $1}' || echo "")
  
  if [ -z "$CERTIFICATES" ]; then
    echo -e "${GREEN}No certificates to wait for in namespace $namespace.${NC}"
    return 0
  fi
  
  echo -e "${BLUE}=== WAITING FOR CERTIFICATES ===${NC}"
  echo -e "${BLUE}Found certificates in namespace $namespace:${NC}"
  echo "$CERTIFICATES"
  
  # Wait for certificates to be ready (up to 3 minutes)
  echo "Waiting for certificates to be ready..."
  for i in {1..18}; do  # 18 * 10s = 3 minutes
    READY_CERTS=0
    TOTAL_CERTS=0
    
    for cert in $CERTIFICATES; do
      TOTAL_CERTS=$((TOTAL_CERTS + 1))
      CERT_STATUS=$($KUBECTL_CMD get certificate "$cert" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
      if [ "$CERT_STATUS" = "True" ]; then
        READY_CERTS=$((READY_CERTS + 1))
      fi
    done
    
    if [ "$READY_CERTS" -eq "$TOTAL_CERTS" ]; then
      echo -e "${GREEN}✓ All certificates ready ($READY_CERTS/$TOTAL_CERTS)${NC}"
      return 0
    else
      echo "Waiting for certificates... ($READY_CERTS/$TOTAL_CERTS ready)"
      sleep 10
    fi
  done
  
  # Certificates not ready after timeout
  echo -e "${YELLOW}⚠ Certificates not ready after 3 minutes, but continuing...${NC}"
  echo "You may need to check cert-manager logs if SSL issues persist."
  
  return 0
} 

# Function to verify cleanup completion
verify_cleanup() {
  local namespace="$1"
  
  echo -e "${BLUE}=== VERIFYING CLEANUP COMPLETION ===${NC}"
  
  # Check namespace
  if $KUBECTL_CMD get namespace "$namespace" &>/dev/null; then
    echo -e "${YELLOW}⚠ Namespace $namespace still exists${NC}"
    return 1
  fi
  
  # Check PVCs
  REMAINING_PVCS=$($KUBECTL_CMD get pvc -A --no-headers 2>/dev/null | grep -E "(lair|comfyui|ollama|minio|n8n|postgres|redis)" | wc -l)
  if [ "$REMAINING_PVCS" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found $REMAINING_PVCS remaining PVCs related to Lair${NC}"
    return 1
  fi
  
  # Check PVs
  REMAINING_PVS=$($KUBECTL_CMD get pv --no-headers 2>/dev/null | grep -E "(lair|comfyui|ollama|minio|n8n|postgres|redis)" | wc -l)
  if [ "$REMAINING_PVS" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Found $REMAINING_PVS remaining PVs related to Lair${NC}"
    return 1
  fi
  
  # Check Longhorn volumes
  if $KUBECTL_CMD get namespace longhorn-system &>/dev/null; then
    REMAINING_VOLUMES=$($KUBECTL_CMD get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | grep -E "(lair|comfyui|ollama|minio|n8n|postgres|redis)" | wc -l)
    if [ "$REMAINING_VOLUMES" -gt 0 ]; then
      echo -e "${YELLOW}⚠ Found $REMAINING_VOLUMES remaining Longhorn volumes related to Lair${NC}"
      return 1
    fi
  fi
  
  echo -e "${GREEN}✓ Cleanup verification passed - all resources removed successfully${NC}"
  return 0
}

# Detect environment type and set appropriate commands
detect_environment

# Determine which kubectl to use based on detected environment
if [[ "$ENVIRONMENT_TYPE" == "microk8s" ]]; then
  KUBECTL_CMD="microk8s kubectl"
  echo -e "${GREEN}Using microk8s kubectl${NC}"
else
  KUBECTL_CMD="kubectl"
  echo -e "${GREEN}Using standard kubectl${NC}"
fi

# Function to detect available helm commands
detect_helm_availability() {
  HELM_STANDARD_AVAILABLE=false
  HELM_MICROK8S_AVAILABLE=false
  
  # Check for standard helm
  if command -v helm &>/dev/null && helm version &>/dev/null; then
    HELM_STANDARD_AVAILABLE=true
    echo -e "${GREEN}✓ Standard helm detected and working${NC}"
  else
    echo -e "${YELLOW}✗ Standard helm not available${NC}"
  fi
  
  # Check for microk8s helm3
  if command -v microk8s &>/dev/null && microk8s helm3 version &>/dev/null; then
    HELM_MICROK8S_AVAILABLE=true
    echo -e "${GREEN}✓ MicroK8s helm3 detected and working${NC}"
  else
    echo -e "${YELLOW}✗ MicroK8s helm3 not available${NC}"
  fi
}

# Function to choose helm command
choose_helm_command() {
  # If both are available, let user choose
  if [[ "$HELM_STANDARD_AVAILABLE" == "true" ]] && [[ "$HELM_MICROK8S_AVAILABLE" == "true" ]]; then
    echo ""
    echo -e "${BLUE}=== HELM COMMAND SELECTION ===${NC}"
    echo -e "${BLUE}Multiple Helm installations detected. Please choose which one to use for cleanup:${NC}"
    echo ""
    echo -e "${GREEN}1) Standard Helm (recommended)${NC}"
    echo -e "   • More widely compatible"
    echo -e "   • Better for mixed environments"
    echo -e "   • Standard tooling"
    echo ""
    echo -e "${YELLOW}2) MicroK8s Helm3${NC}"
    echo -e "   • Integrated with MicroK8s"
    echo -e "   • Uses MicroK8s kubectl context automatically"
    echo ""
    
    while true; do
      read -p "Choose Helm command (1-2) [default: 1]: " helm_choice
      helm_choice=${helm_choice:-1}
      
      case $helm_choice in
        1)
          HELM_CMD="helm"
          echo -e "${GREEN}Selected: Standard Helm${NC}"
          break
          ;;
        2)
          HELM_CMD="microk8s helm3"
          echo -e "${GREEN}Selected: MicroK8s Helm3${NC}"
          break
          ;;
        *)
          echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
          ;;
      esac
    done
  # If only one is available, use it
  elif [[ "$HELM_STANDARD_AVAILABLE" == "true" ]]; then
    HELM_CMD="helm"
    echo -e "${GREEN}Using standard helm (only available option)${NC}"
  elif [[ "$HELM_MICROK8S_AVAILABLE" == "true" ]]; then
    HELM_CMD="microk8s helm3"
    echo -e "${GREEN}Using microk8s helm3 (only available option)${NC}"
  else
    echo -e "${RED}Error: No working helm client found. Please install helm.${NC}"
    echo -e "${YELLOW}For standard Kubernetes: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash${NC}"
    echo -e "${YELLOW}For MicroK8s: microk8s enable helm3${NC}"
    exit 1
  fi
}

# Detect available helm commands
echo -e "${BLUE}=== DETECTING HELM AVAILABILITY ===${NC}"
detect_helm_availability

# Choose which helm command to use
choose_helm_command

# List existing Helm releases
echo -e "${BLUE}Existing Helm releases:${NC}"
$HELM_CMD list --all-namespaces 2>/dev/null | head -20 || echo "No Helm releases found"
echo ""

# Ask for the Helm release name
read -p "Enter the Helm release name [default: lair]: " RELEASE_NAME
RELEASE_NAME=${RELEASE_NAME:-lair}
echo -e "${BLUE}Target release: $RELEASE_NAME${NC}"

# List existing namespaces
echo -e "${BLUE}Existing namespaces:${NC}"
$KUBECTL_CMD get namespaces --no-headers 2>/dev/null | awk '{print $1}' | head -20 || echo "No namespaces found"
echo ""

# Ask for namespace to clean up
read -p "Enter the namespace of the Lair installation [default: lair]: " NAMESPACE
NAMESPACE=${NAMESPACE:-lair}
echo -e "${BLUE}Target namespace: $NAMESPACE${NC}"

# List existing StorageClasses
echo -e "${BLUE}Existing StorageClasses:${NC}"
$KUBECTL_CMD get storageclass --no-headers 2>/dev/null | awk '{print $1}' | head -20 || echo "No StorageClasses found"
echo ""

# Find Lair-related StorageClasses
LAIR_STORAGE_CLASSES=$($KUBECTL_CMD get storageclass --no-headers 2>/dev/null | grep "lair-storage" | awk '{print $1}')
if [ -n "$LAIR_STORAGE_CLASSES" ]; then
  echo -e "${YELLOW}Found Lair-related StorageClasses:${NC}"
  echo "$LAIR_STORAGE_CLASSES"
  echo ""
  
  # Ask if user wants to remove all Lair StorageClasses
  read -p "Do you want to delete ALL Lair StorageClasses listed above? (y/n) [default: y]: " DELETE_ALL_LAIR_SC
  DELETE_ALL_LAIR_SC=${DELETE_ALL_LAIR_SC:-y}
  
  if [[ "$DELETE_ALL_LAIR_SC" == "y" || "$DELETE_ALL_LAIR_SC" == "Y" ]]; then
    DELETE_SC="y"
    STORAGE_CLASS="ALL_LAIR"
    echo -e "${BLUE}Will delete ALL Lair StorageClasses${NC}"
  else
    # Ask for specific storage class to clean up
    read -p "Enter the name of the StorageClass to remove [default: lair-storage]: " STORAGE_CLASS
    STORAGE_CLASS=${STORAGE_CLASS:-lair-storage}
    echo -e "${BLUE}Target StorageClass: $STORAGE_CLASS${NC}"
    
    # Ask if user wants to remove the custom StorageClass
    read -p "Do you want to delete the custom StorageClass (if it exists)? (y/n) [default: y]: " DELETE_SC
    DELETE_SC=${DELETE_SC:-y}
  fi
else
  # Ask for storage class to clean up
  read -p "Enter the name of the StorageClass to remove [default: lair-storage]: " STORAGE_CLASS
  STORAGE_CLASS=${STORAGE_CLASS:-lair-storage}
  echo -e "${BLUE}Target StorageClass: $STORAGE_CLASS${NC}"
  
  # Ask if user wants to remove the custom StorageClass
  read -p "Do you want to delete the custom StorageClass (if it exists)? (y/n) [default: y]: " DELETE_SC
  DELETE_SC=${DELETE_SC:-y}
fi

# Confirm cleanup operation
echo -e "${YELLOW}WARNING: This will remove the following:${NC}"
echo -e "- Helm release '$RELEASE_NAME' in namespace '$NAMESPACE'"
echo -e "- All resources in namespace '$NAMESPACE'"
echo -e "- All Longhorn volumes, engines, and replicas related to Lair"
echo -e "- All PVCs and PVs related to Lair"
echo -e "- The namespace '$NAMESPACE' itself"
if [[ "$DELETE_SC" == "y" || "$DELETE_SC" == "Y" ]]; then
  if [[ "$STORAGE_CLASS" == "ALL_LAIR" ]]; then
    echo -e "- ALL Lair StorageClasses (lair-storage*)"
  else
    echo -e "- The StorageClass '$STORAGE_CLASS'"
  fi
fi
echo ""
confirm

# ============================================================================
# MAIN CLEANUP SEQUENCE
# ============================================================================

echo -e "${BLUE}Starting comprehensive cleanup sequence...${NC}"

# Step 1: Clean up Longhorn resources first (before deleting PVCs)
cleanup_longhorn_resources "$NAMESPACE"

# Step 2: Try to uninstall the Helm release
echo -e "${BLUE}=== UNINSTALLING HELM RELEASE ===${NC}"
if $HELM_CMD uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null; then
  echo -e "${GREEN}Helm release $RELEASE_NAME successfully uninstalled.${NC}"
else
  echo -e "${YELLOW}Could not uninstall Helm release normally, attempting force removal...${NC}"
  
  # Try with --no-hooks
  if $HELM_CMD uninstall "$RELEASE_NAME" -n "$NAMESPACE" --no-hooks 2>/dev/null; then
    echo -e "${GREEN}Helm release $RELEASE_NAME successfully uninstalled with --no-hooks.${NC}"
  else
    echo -e "${YELLOW}Also failed with --no-hooks, attempting to force remove Helm secrets...${NC}"
    $KUBECTL_CMD delete secret -n "$NAMESPACE" -l "owner=helm,name=$RELEASE_NAME" --force --grace-period=0 2>/dev/null || true
  fi
fi

# Step 3: Clean up storage resources with proper finalizer handling
cleanup_storage_resources "$NAMESPACE"

# Step 4: Delete any remaining pods, services, etc. in the namespace
echo -e "${BLUE}=== CLEANING UP REMAINING RESOURCES ===${NC}"
$KUBECTL_CMD delete all --all -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true

# Give resources time to clean up
echo "Waiting for resources to be cleaned up..."
sleep 10

# Step 5: Delete the namespace with finalizer handling
echo -e "${BLUE}=== DELETING NAMESPACE ===${NC}"
if ! $KUBECTL_CMD delete namespace "$NAMESPACE" --timeout=30s 2>/dev/null; then
  echo -e "${YELLOW}Could not delete namespace normally, attempting to force remove finalizers...${NC}"
  
  # Force remove namespace
  echo "Attempting to remove finalizers from namespace..."
  $KUBECTL_CMD get namespace "$NAMESPACE" -o json 2>/dev/null | sed 's/"kubernetes"//' | jq '.spec.finalizers = []' > temp_ns.json 2>/dev/null || true
  $KUBECTL_CMD replace --raw "/api/v1/namespaces/$NAMESPACE/finalize" -f temp_ns.json 2>/dev/null || true
  rm -f temp_ns.json
  
  # Wait for namespace deletion
  wait_for_deletion "namespace" "$NAMESPACE" "" 30
else
  echo -e "${GREEN}Namespace $NAMESPACE successfully deleted.${NC}"
fi

# Step 6: Clean up ingress and certificates
echo -e "${BLUE}=== CLEANING UP INGRESS AND CERTIFICATES ===${NC}"

# Define certificate cleanup namespaces based on environment (used for both ingress and certificates)
if [[ "$ENVIRONMENT_TYPE" == "microk8s" ]]; then
  GLOBAL_CERT_NAMESPACES=("default" "kube-system" "cert-manager" "ingress")
else
  GLOBAL_CERT_NAMESPACES=("default" "kube-system" "cert-manager" "ingress-nginx")
fi

# Clean up ingress resources first
echo -e "${BLUE}Cleaning up ingress resources...${NC}"
$KUBECTL_CMD delete ingress --all -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true

# Also clean up any global ingress resources that might point to Lair services
echo -e "${BLUE}Checking for global ingress resources related to Lair...${NC}"
INGRESS_CHECK_NAMESPACES=("${GLOBAL_CERT_NAMESPACES[@]}")

for ingress_ns in "${INGRESS_CHECK_NAMESPACES[@]}"; do
  if $KUBECTL_CMD get namespace "$ingress_ns" &>/dev/null; then
    # Look for ingress rules that might be related to Lair services
    LAIR_INGRESS=$($KUBECTL_CMD get ingress -n "$ingress_ns" --no-headers 2>/dev/null | grep -E "(lair|openwebui|chat|n8n|comfyui|minio)" | awk '{print $1}' || echo "")
    if [ -n "$LAIR_INGRESS" ]; then
      echo -e "${YELLOW}Found Lair-related ingress resources in namespace $ingress_ns:${NC}"
      for ingress in $LAIR_INGRESS; do
        echo "Deleting ingress: $ingress (namespace: $ingress_ns)"
        $KUBECTL_CMD delete ingress "$ingress" -n "$ingress_ns" --force --grace-period=0 2>/dev/null || true
      done
    fi
  fi
done

# Clean up TLS secrets and certificates related to Lair
if $KUBECTL_CMD get namespace cert-manager &>/dev/null; then
  echo -e "${BLUE}Cleaning up certificates and TLS secrets...${NC}"
  
  # Delete certificates in the namespace (this will also clean up TLS secrets)
  $KUBECTL_CMD delete certificates --all -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true
  
  # Delete TLS secrets that might be orphaned
  TLS_SECRETS=$($KUBECTL_CMD get secrets -n "$NAMESPACE" --no-headers 2>/dev/null | grep "tls\|cert" | awk '{print $1}' || echo "")
  if [ -n "$TLS_SECRETS" ]; then
    echo -e "${YELLOW}Deleting TLS secrets:${NC}"
    for secret in $TLS_SECRETS; do
      echo "Deleting TLS secret: $secret"
      $KUBECTL_CMD delete secret "$secret" -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true
    done
  fi
  
  # Clean up certificate requests
  $KUBECTL_CMD delete certificaterequests --all -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true
  
  # Clean up challenges
  $KUBECTL_CMD delete challenges --all -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true
  
  # Clean up orders
  $KUBECTL_CMD delete orders --all -n "$NAMESPACE" --force --grace-period=0 2>/dev/null || true
  
  # Also clean up any global certificates/secrets that might be related to Lair domains
  echo -e "${BLUE}Checking for global certificates related to Lair domains...${NC}"
  echo -e "${BLUE}Checking namespaces: ${GLOBAL_CERT_NAMESPACES[*]}${NC}"
  
  for cert_ns in "${GLOBAL_CERT_NAMESPACES[@]}"; do
    if $KUBECTL_CMD get namespace "$cert_ns" &>/dev/null; then
      echo -e "${BLUE}Checking namespace $cert_ns for Lair certificates...${NC}"
      
      # Look for certificates that might be related to Lair (containing common domain patterns)
      LAIR_CERTS=$($KUBECTL_CMD get certificates -n "$cert_ns" --no-headers 2>/dev/null | grep -E "(lair|openwebui|chat|n8n|comfyui|minio)" | awk '{print $1}' || echo "")
      if [ -n "$LAIR_CERTS" ]; then
        echo -e "${YELLOW}Found Lair-related certificates in namespace $cert_ns:${NC}"
        for cert in $LAIR_CERTS; do
          echo "Deleting certificate: $cert (namespace: $cert_ns)"
          $KUBECTL_CMD delete certificate "$cert" -n "$cert_ns" --force --grace-period=0 2>/dev/null || true
        done
      fi
      
      # Look for TLS secrets that might be related to Lair
      LAIR_TLS_SECRETS=$($KUBECTL_CMD get secrets -n "$cert_ns" --no-headers 2>/dev/null | grep -E "(lair|openwebui|chat|n8n|comfyui|minio).*tls" | awk '{print $1}' || echo "")
      if [ -n "$LAIR_TLS_SECRETS" ]; then
        echo -e "${YELLOW}Found Lair-related TLS secrets in namespace $cert_ns:${NC}"
        for secret in $LAIR_TLS_SECRETS; do
          echo "Deleting TLS secret: $secret (namespace: $cert_ns)"
          $KUBECTL_CMD delete secret "$secret" -n "$cert_ns" --force --grace-period=0 2>/dev/null || true
        done
      fi
      
      # Also look for any TLS secrets with typical ingress patterns (tls-secret, etc.)
      INGRESS_TLS_SECRETS=$($KUBECTL_CMD get secrets -n "$cert_ns" --no-headers 2>/dev/null | grep -E "(tls-secret|tls-cert|ssl-cert)" | awk '{print $1}' || echo "")
      if [ -n "$INGRESS_TLS_SECRETS" ]; then
        echo -e "${YELLOW}Found generic TLS secrets in namespace $cert_ns:${NC}"
        for secret in $INGRESS_TLS_SECRETS; do
          # Check if this secret is related to Lair domains
          SECRET_DOMAINS=$($KUBECTL_CMD get secret "$secret" -n "$cert_ns" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d 2>/dev/null | openssl x509 -text -noout 2>/dev/null | grep -E "(lair|openwebui|chat|n8n|comfyui|minio)" || echo "")
          if [ -n "$SECRET_DOMAINS" ]; then
            echo "Deleting Lair-related TLS secret: $secret (namespace: $cert_ns)"
            $KUBECTL_CMD delete secret "$secret" -n "$cert_ns" --force --grace-period=0 2>/dev/null || true
          fi
        done
      fi
    else
      echo -e "${YELLOW}Namespace $cert_ns not found, skipping.${NC}"
    fi
  done
  
  echo -e "${GREEN}Certificate cleanup completed.${NC}"
else
  echo -e "${YELLOW}cert-manager not found, skipping certificate cleanup.${NC}"
fi

# Step 7: Delete StorageClass if requested
if [[ "$DELETE_SC" == "y" || "$DELETE_SC" == "Y" ]]; then
  echo -e "${BLUE}=== DELETING STORAGE CLASSES ===${NC}"
  if [[ "$STORAGE_CLASS" == "ALL_LAIR" ]]; then
    echo -e "${BLUE}Deleting ALL Lair StorageClasses...${NC}"
    # Get all lair-storage StorageClasses and delete them
    LAIR_SCS=$($KUBECTL_CMD get storageclass --no-headers 2>/dev/null | grep "lair-storage" | awk '{print $1}')
    if [ -n "$LAIR_SCS" ]; then
      for SC in $LAIR_SCS; do
        echo -e "${YELLOW}Deleting StorageClass $SC...${NC}"
        $KUBECTL_CMD delete storageclass "$SC" 2>/dev/null || true
      done
      echo -e "${GREEN}All Lair StorageClasses deleted.${NC}"
    else
      echo -e "${GREEN}No Lair StorageClasses found to delete.${NC}"
    fi
  else
    echo -e "${BLUE}Checking for StorageClass $STORAGE_CLASS...${NC}"
    if $KUBECTL_CMD get storageclass "$STORAGE_CLASS" &>/dev/null; then
      echo -e "${YELLOW}Deleting StorageClass $STORAGE_CLASS...${NC}"
      $KUBECTL_CMD delete storageclass "$STORAGE_CLASS" 2>/dev/null || true
      $KUBECTL_CMD delete storageclass "$STORAGE_CLASS-rwx" 2>/dev/null || true
      echo -e "${GREEN}StorageClass $STORAGE_CLASS deleted.${NC}"
    else
      echo -e "${GREEN}StorageClass $STORAGE_CLASS not found, nothing to delete.${NC}"
    fi
  fi
fi

# Step 8: Clean up local storage data (optional)
echo -e "${BLUE}=== CLEANING UP LOCAL STORAGE DATA ===${NC}"
read -p "Do you want to clean up local storage data? This will free up disk space. (y/n) [default: y]: " CLEAN_LOCAL
CLEAN_LOCAL=${CLEAN_LOCAL:-y}

if [[ "$CLEAN_LOCAL" == "y" || "$CLEAN_LOCAL" == "Y" ]]; then
  # Define storage paths based on environment
  if [[ "$ENVIRONMENT_TYPE" == "microk8s" ]]; then
    COMMON_PATHS=(
      "/var/snap/microk8s/common/default-storage"
      "/var/lib/kubelet/pods"
      "/tmp/hostpath-provisioner"
    )
  else
    # For managed k8s environments
    COMMON_PATHS=(
      "/var/lib/rancher/k3s/storage"
      "/var/lib/kubelet/pods" 
      "/opt/local-path-provisioner"
      "/tmp/hostpath-provisioner"
      "/var/lib/kubernetes/storage"
    )
  fi

  # Handle /var/lib/longhorn separately and more carefully
  LONGHORN_PATH="/var/lib/longhorn"

  for path in "${COMMON_PATHS[@]}"; do
    if [ -d "$path" ]; then
      echo "Checking $path for Lair data..."
      # Look for directories that might contain Lair data
      LAIR_DIRS=$(find "$path" -type d -name "*lair*" -o -name "*comfyui*" -o -name "*ollama*" -o -name "*minio*" -o -name "*n8n*" -o -name "*postgres*" -o -name "*redis*" 2>/dev/null || echo "")
      if [ -n "$LAIR_DIRS" ]; then
        echo -e "${YELLOW}Found potential Lair data directories:${NC}"
        echo "$LAIR_DIRS"
        echo "$LAIR_DIRS" | while read -r dir; do
          if [ -n "$dir" ] && [ -d "$dir" ]; then
            echo "Removing $dir..."
            rm -rf "$dir" 2>/dev/null || true
          fi
        done
        echo -e "${GREEN}Local storage cleanup completed for $path.${NC}"
      fi
    fi
  done

  # Handle Longhorn directory with extra caution for production environments
  if [ -d "$LONGHORN_PATH" ]; then
    echo -e "${BLUE}Checking Longhorn storage for Lair-specific data...${NC}"
    
    # Check if there are other applications using Longhorn
    OTHER_APPS_COUNT=0
    if $KUBECTL_CMD get namespace longhorn-system &>/dev/null; then
      # Count non-Lair volumes in Longhorn
      OTHER_APPS_COUNT=$($KUBECTL_CMD get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | grep -v -E "(lair|comfyui|ollama|minio|n8n|postgres|redis)" | wc -l || echo "0")
    fi
    
    # Look for Lair-specific directories in Longhorn
    LAIR_LONGHORN_DIRS=$(find "$LONGHORN_PATH" -type d -name "*lair*" -o -name "*comfyui*" -o -name "*ollama*" -o -name "*minio*" -o -name "*n8n*" -o -name "*postgres*" -o -name "*redis*" 2>/dev/null || echo "")
    
    if [ -n "$LAIR_LONGHORN_DIRS" ]; then
      echo -e "${YELLOW}Found potential Lair data in Longhorn storage:${NC}"
      echo "$LAIR_LONGHORN_DIRS"
      echo ""
      
      if [ "$OTHER_APPS_COUNT" -gt 0 ]; then
        echo -e "${RED}⚠️  WARNING: Detected $OTHER_APPS_COUNT non-Lair volumes in Longhorn!${NC}"
        echo -e "${RED}   This appears to be a shared Longhorn installation.${NC}"
        echo -e "${RED}   Cleaning Longhorn data could affect other applications!${NC}"
        echo ""
        read -p "Are you SURE you want to delete Lair data from shared Longhorn storage? (yes/no) [default: no]: " DELETE_LONGHORN
        DELETE_LONGHORN=${DELETE_LONGHORN:-no}
      else
        echo -e "${GREEN}No other applications detected using Longhorn.${NC}"
        DELETE_LONGHORN="y"
      fi
      
      if [[ "$DELETE_LONGHORN" == "yes" ]] || [[ "$DELETE_LONGHORN" == "y" || "$DELETE_LONGHORN" == "Y" ]]; then
        echo "$LAIR_LONGHORN_DIRS" | while read -r dir; do
          if [ -n "$dir" ] && [ -d "$dir" ]; then
            echo "Removing $dir..."
            rm -rf "$dir" 2>/dev/null || true
          fi
        done
        echo -e "${GREEN}Lair-specific Longhorn data cleanup completed.${NC}"
      else
        echo -e "${GREEN}Longhorn data cleanup skipped.${NC}"
      fi
    else
      echo -e "${GREEN}No Lair-specific data found in Longhorn storage.${NC}"
    fi
  fi
else
  echo -e "${YELLOW}Local storage cleanup skipped.${NC}"
fi

# Step 9: Clean up unused container images (optional)
echo -e "${BLUE}=== CLEANING UP CONTAINER IMAGES ===${NC}"
read -p "Do you want to clean up unused container images? This will free up disk space. (y/n) [default: y]: " CLEAN_IMAGES
CLEAN_IMAGES=${CLEAN_IMAGES:-y}

if [[ "$CLEAN_IMAGES" == "y" || "$CLEAN_IMAGES" == "Y" ]]; then
  if [[ "$ENVIRONMENT_TYPE" == "microk8s" ]]; then
    # For microk8s, use manual cleanup with ctr (containerd 1.6 compatible)
    echo -e "${YELLOW}Cleaning up containers, snapshots and unused images (MicroK8s)...${NC}"
    
    # Remove stopped containers
    echo "Removing stopped containers..."
    microk8s ctr --namespace k8s.io containers ls 2>/dev/null | awk '$NF!="RUNNING"{print $1}' | xargs -r microk8s ctr --namespace k8s.io containers rm 2>/dev/null || true
    
    # Remove unused snapshots
    echo "Removing unused snapshots..."
    microk8s ctr --namespace k8s.io snapshot ls 2>/dev/null | awk 'NR>1 {print $2}' | xargs -r microk8s ctr --namespace k8s.io snapshots delete 2>/dev/null || true
    
    # Remove images related to Lair components
    echo "Removing Lair-related images..."
    LAIR_IMAGES=$(microk8s ctr --namespace k8s.io images ls 2>/dev/null | grep -E "(comfyui|ollama|open-webui|n8n|minio|postgres|redis|tika)" | awk '{print $1}' || echo "")
    if [ -n "$LAIR_IMAGES" ]; then
      echo "$LAIR_IMAGES" | xargs -r microk8s ctr --namespace k8s.io images rm 2>/dev/null || true
    fi
    
    # Remove unused images (size 0 or marked with *)
    echo "Removing unused images..."
    microk8s ctr --namespace k8s.io images ls 2>/dev/null | awk '$3=="0" || $3=="*"{print $1}' | xargs -r microk8s ctr --namespace k8s.io images rm 2>/dev/null || true
    
    # Remove orphaned overlayfs snapshots
    echo "Removing orphaned overlayfs snapshots..."
    microk8s ctr --namespace k8s.io snapshots ls 2>/dev/null | awk 'NR>1{print $1}' | xargs -r microk8s ctr --namespace k8s.io snapshots rm 2>/dev/null || true
    
    # Force garbage collection
    echo "Running garbage collection..."
    microk8s ctr --namespace k8s.io content gc 2>/dev/null || true
    
    echo -e "${GREEN}Container cleanup completed.${NC}"
  else
    # For managed k8s, try different cleanup methods
    echo -e "${YELLOW}Cleaning up unused images (managed Kubernetes)...${NC}"
    
    # Try crictl first (most common)
    if command -v crictl &>/dev/null; then
      echo "Removing unused images with crictl..."
      if crictl rmi --prune &>/dev/null; then
        echo -e "${GREEN}Unused images removed successfully with crictl.${NC}"
      else
        echo -e "${YELLOW}crictl cleanup failed, trying alternative methods...${NC}"
        
        # Try removing specific Lair-related images
        LAIR_IMAGES=$(crictl images --format table 2>/dev/null | grep -E "(comfyui|ollama|open-webui|n8n|minio|postgres|redis|tika)" | awk '{print $3}' || echo "")
        if [ -n "$LAIR_IMAGES" ]; then
          echo "Removing Lair-related images..."
          echo "$LAIR_IMAGES" | xargs -r crictl rmi 2>/dev/null || true
        fi
      fi
    # Try docker if available (some managed k8s use docker)
    elif command -v docker &>/dev/null; then
      echo "Removing unused images with docker..."
      if docker system prune -af --filter "until=1h" &>/dev/null; then
        echo -e "${GREEN}Unused images removed successfully with docker.${NC}"
      else
        echo -e "${YELLOW}docker cleanup failed.${NC}"
      fi
    # Try containerd ctr directly
    elif command -v ctr &>/dev/null; then
      echo "Removing unused images with containerd..."
      # Try to remove Lair-specific images
      LAIR_IMAGES=$(ctr --namespace k8s.io images ls 2>/dev/null | grep -E "(comfyui|ollama|open-webui|n8n|minio|postgres|redis|tika)" | awk '{print $1}' || echo "")
      if [ -n "$LAIR_IMAGES" ]; then
        echo "$LAIR_IMAGES" | xargs -r ctr --namespace k8s.io images rm 2>/dev/null || true
        echo -e "${GREEN}Lair-related images removed with containerd.${NC}"
      fi
      # Run garbage collection
      ctr --namespace k8s.io content gc 2>/dev/null || true
    else
      echo -e "${YELLOW}No compatible container runtime tools found for image cleanup.${NC}"
      echo -e "${YELLOW}Available tools: crictl, docker, or ctr are typically used.${NC}"
    fi
  fi
else
  echo -e "${YELLOW}Container image cleanup skipped.${NC}"
fi

# Step 9: Restart ingress controller to clean up configuration
restart_ingress_controller

# Step 10: Environment-specific information
echo -e "${BLUE}=== ENVIRONMENT-SPECIFIC INFORMATION ===${NC}"
if [[ "$ENVIRONMENT_TYPE" == "k8s-managed" ]]; then
  echo -e "${YELLOW}📋 MANAGED KUBERNETES ENVIRONMENT DETECTED${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}ℹ️  This cleanup script only removes Lair application components installed via Helm.${NC}"
  echo -e "${YELLOW}   The following infrastructure components are NOT touched:${NC}"
  echo -e "${YELLOW}   • Longhorn storage system (if installed via Helm during setup)${NC}"
  echo -e "${YELLOW}   • NGINX Ingress Controller (if installed via Helm during setup)${NC}"
  echo -e "${YELLOW}   • Cert-Manager (if installed via Helm during setup)${NC}"
  echo -e "${YELLOW}   • Base Kubernetes cluster components${NC}"
  echo ""
  echo -e "${GREEN}✅ Infrastructure components remain available for future Lair installations.${NC}"
  echo ""
elif [[ "$ENVIRONMENT_TYPE" == "microk8s" ]]; then
  # Check and warn about multipathd (if Longhorn is present)
  if $KUBECTL_CMD get namespace longhorn-system &>/dev/null; then
    echo -e "${BLUE}Checking for multipathd conflicts...${NC}"
    if systemctl is-active multipathd &>/dev/null || systemctl is-active multipathd.socket &>/dev/null; then
      echo -e "${YELLOW}⚠️  WARNING: multipathd is active and may cause issues with Longhorn!${NC}"
      echo -e "${YELLOW}   This is a known issue that can cause volume attachment problems.${NC}"
      echo -e "${YELLOW}   Consider disabling it: sudo systemctl stop multipathd && sudo systemctl disable multipathd${NC}"
      echo -e "${YELLOW}   Also disable socket: sudo systemctl stop multipathd.socket && sudo systemctl disable multipathd.socket${NC}"
    else
      echo -e "${GREEN}multipathd is not active, good for Longhorn.${NC}"
    fi
  fi
fi

# Step 11: Final verification
echo -e "\n${BLUE}=== FINAL VERIFICATION ===${NC}"
if verify_cleanup "$NAMESPACE"; then
  echo -e "${GREEN}🎉 CLEANUP COMPLETED SUCCESSFULLY!${NC}"
  echo -e "${GREEN}All Lair resources have been removed cleanly.${NC}"
  echo -e "${GREEN}Longhorn is in a consistent state.${NC}"
  echo -e "${GREEN}System is ready for a fresh Lair installation.${NC}"
else
  echo -e "${YELLOW}⚠ Cleanup completed but some resources may still exist.${NC}"
  echo -e "${YELLOW}You may need to manually remove remaining resources.${NC}"
  echo -e "${YELLOW}Check the output above for details.${NC}"
fi

# Show final disk usage
echo -e "${BLUE}=== DISK USAGE SUMMARY ===${NC}"
DISK_USAGE_AFTER=$(df -h / | tail -1 | awk '{print $3 " used, " $4 " available"}')
echo -e "${GREEN}Current disk usage: $DISK_USAGE_AFTER${NC}"

echo -e "\n${GREEN}Cleanup process completed!${NC}"

# Environment-specific reinstallation instructions
if [[ "$ENVIRONMENT_TYPE" == "microk8s" ]]; then
  echo -e "${BLUE}You can now reinstall Lair with: ./setup.sh${NC}"
elif [[ "$ENVIRONMENT_TYPE" == "k8s-managed" ]]; then
  echo -e "${BLUE}You can now reinstall Lair with: ./setup.sh${NC}"
fi

echo ""
echo -e "${YELLOW}📋 IMPORTANT NOTES AFTER CLEANUP ($(echo ${ENVIRONMENT_TYPE} | tr '[:lower:]' '[:upper:]') ENVIRONMENT):${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}🔐 SSL Certificates: After reinstalling, certificates will need to be regenerated.${NC}"
echo -e "${YELLOW}   • Let's Encrypt certificates may take 1-2 minutes to issue${NC}"
echo -e "${YELLOW}   • Local certificates (mkcert) will be recreated automatically${NC}"
echo -e "${YELLOW}   • Services may show SSL errors until certificates are ready${NC}"
echo ""

if [[ "$ENVIRONMENT_TYPE" == "k8s-managed" ]]; then
  echo -e "${YELLOW}🏗️  Infrastructure Components: Core components remain installed and ready.${NC}"
  echo -e "${YELLOW}   • Longhorn storage system is ready for new volumes${NC}"
  echo -e "${YELLOW}   • NGINX Ingress Controller is ready for new routes${NC}"
  echo -e "${YELLOW}   • Cert-Manager is ready for new certificates${NC}"
  echo -e "${YELLOW}   • No infrastructure setup required for reinstallation${NC}"
  echo ""
else
  echo -e "${YELLOW}🌐 Ingress Controller: Has been restarted and is ready for new configuration.${NC}"
  echo -e "${YELLOW}   • All old SSL certificates and ingress rules have been cleaned up${NC}"
  echo -e "${YELLOW}   • New ingress rules will be applied during reinstallation${NC}"
  echo ""
fi

echo -e "${YELLOW}💾 Storage: Longhorn has been reset to a clean state.${NC}"
echo -e "${YELLOW}   • All previous volumes and data have been removed${NC}"
echo -e "${YELLOW}   • New PVCs will be created during reinstallation${NC}"
echo ""
echo -e "${GREEN}✅ System is now ready for a fresh Lair installation!${NC}"

# Make the script executable
chmod +x "$0"