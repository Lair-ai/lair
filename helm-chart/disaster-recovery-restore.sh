#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# LAIR DISASTER RECOVERY RESTORE SCRIPT
# ============================================================================
# Comprehensive disaster recovery with pre-cleanup and enhanced validation
#
# Usage:
#   ./disaster-recovery-restore.sh                  # Interactive mode
#   ./disaster-recovery-restore.sh --list-backups   # List all backups
#   ./disaster-recovery-restore.sh --list-backups zeus  # List backups for cluster 'zeus'
#   ./disaster-recovery-restore.sh BACKUP_NAME      # Direct restore
#   ./disaster-recovery-restore.sh --clean-restore BACKUP_NAME  # Clean + restore
#   ./disaster-recovery-restore.sh --to-namespace lair-test BACKUP_NAME  # Restore to different namespace
# ============================================================================

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_err() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Prerequisites check
check_prerequisites() {
    log_step "🔍 Checking Prerequisites"
    
    # Check kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        log_err "kubectl not found. Please install kubectl first."
        exit 1
    fi
    log_ok "kubectl found"
    
    # Check cluster access
    if ! kubectl cluster-info >/dev/null 2>&1; then
        log_err "Cannot access Kubernetes cluster. Check your kubeconfig."
        exit 1
    fi
    log_ok "Kubernetes cluster accessible"
    
    # Check Velero installation
    if ! kubectl get namespace velero >/dev/null 2>&1; then
        log_err "Velero namespace not found. Please install Velero first."
        exit 1
    fi
    log_ok "Velero namespace exists"
    
    # Check Velero deployment
    if ! kubectl get deployment velero -n velero >/dev/null 2>&1; then
        log_err "Velero deployment not found. Please install Velero first."
        exit 1
    fi
    
    # Check Velero is running
    VELERO_READY=$(kubectl get deployment velero -n velero -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$VELERO_READY" == "0" ]]; then
        log_err "Velero is not running. Please check Velero installation."
        exit 1
    fi
    log_ok "Velero deployment is running"
    
    # Check BackupStorageLocation
    log_info "Verifying BackupStorageLocation..."
    if ! kubectl get backupstoragelocations -n velero default >/dev/null 2>&1; then
        log_err "Default BackupStorageLocation not found."
        exit 1
    fi
    
    # Check BSL status
    BSL_PHASE=$(kubectl get backupstoragelocations default -n velero -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [[ "$BSL_PHASE" != "Available" ]]; then
        log_warn "BackupStorageLocation status: $BSL_PHASE (expected: Available)"
        log_info "Checking S3 connectivity..."
        
        # Get BSL details
        BSL_BUCKET=$(kubectl get backupstoragelocations default -n velero -o jsonpath='{.spec.objectStorage.bucket}')
        BSL_S3URL=$(kubectl get backupstoragelocations default -n velero -o jsonpath='{.spec.config.s3Url}')
        
        log_info "  Bucket: $BSL_BUCKET"
        log_info "  S3 URL: $BSL_S3URL"
        
        # Test S3 connectivity by checking Velero pod logs
        log_info "Testing S3 connectivity through Velero..."
        VELERO_POD=$(kubectl get pods -n velero -l app.kubernetes.io/name=velero -o jsonpath='{.items[0].metadata.name}')
        
        if kubectl logs "$VELERO_POD" -n velero --tail=50 2>/dev/null | grep -qi "error.*backup.*storage"; then
            log_err "S3 connectivity issues detected in Velero logs"
            log_err "Please verify S3 credentials and network connectivity"
            exit 1
        fi
        
        log_warn "Proceeding despite BSL status - will verify during backup listing"
    else
        log_ok "BackupStorageLocation is Available"
    fi
    
    # Check node-agent (CRITICAL for volume data restore)
    log_info "Verifying node-agent for volume data restore..."
    if ! kubectl get daemonset node-agent -n velero >/dev/null 2>&1; then
        log_err "❌ CRITICAL: node-agent DaemonSet not found!"
        log_err ""
        log_err "Without node-agent, restored PVCs will be EMPTY (no data)!"
        log_err ""
        log_err "To fix this, run:"
        log_err "  helm upgrade velero vmware-tanzu/velero -n velero \\"
        log_err "    --set configuration.defaultVolumesToFsBackup=true \\"
        log_err "    --set deployNodeAgent=true \\"
        log_err "    --reuse-values"
        log_err ""
        exit 1
    fi
    
    # Check node-agent pods are running
    NODE_AGENT_READY=$(kubectl get daemonset node-agent -n velero -o jsonpath='{.status.numberReady}' 2>/dev/null || echo "0")
    NODE_AGENT_DESIRED=$(kubectl get daemonset node-agent -n velero -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo "0")
    
    if [[ "$NODE_AGENT_READY" == "0" ]] || [[ "$NODE_AGENT_READY" != "$NODE_AGENT_DESIRED" ]]; then
        log_warn "node-agent not fully ready: $NODE_AGENT_READY/$NODE_AGENT_DESIRED pods"
        log_warn "Volume data restore may not work properly"
    else
        log_ok "node-agent is ready: $NODE_AGENT_READY/$NODE_AGENT_DESIRED pods running"
    fi
}

# List available backups
list_backups() {
    local filter_cluster="${1:-}"
    
    log_step "📋 Available Backups"
    
    # Check if any backups exist
    local all_backups
    all_backups=$(kubectl get backups.velero.io -n velero --no-headers 2>/dev/null || echo "")
    
    if [[ -z "$all_backups" ]]; then
        log_warn "No backups found in Velero"
        log_info "Possible causes:"
        log_info "  1. No backups have been created yet"
        log_info "  2. S3 connectivity issues"
        log_info "  3. Different BackupStorageLocation configured"
        exit 1
    fi
    
    # Detect unique cluster prefixes from backup names
    local clusters
    clusters=$(echo "$all_backups" | awk '{print $1}' | sed 's/-backup-[0-9]*$//' | sort -u | tr '\n' ', ' | sed 's/,$//')
    
    if [[ -n "$filter_cluster" ]]; then
        log_info "Filtering backups for cluster: $filter_cluster"
        BACKUP_COUNT=$(echo "$all_backups" | grep "^${filter_cluster}-backup-" | wc -l | tr -d ' ')
    else
        BACKUP_COUNT=$(echo "$all_backups" | wc -l | tr -d ' ')
        if [[ $(echo "$clusters" | tr ',' '\n' | wc -l | tr -d ' ') -gt 1 ]]; then
            log_info "Detected clusters: $clusters"
            log_info "Tip: Use './disaster-recovery-restore.sh --list-backups <cluster-name>' to filter"
        fi
    fi
    
    if [[ "$BACKUP_COUNT" == "0" ]]; then
        log_warn "No backups found for cluster: $filter_cluster"
        exit 1
    fi
    
    log_info "Found $BACKUP_COUNT backup(s) (newest first):"
    echo
    
    # Get backups sorted by creation timestamp (newest first)
    # Sort by CREATED column (3rd field) in reverse order
    {
        # Print header
        printf "%-32s %-17s %-22s %-22s %s\n" "NAME" "STATUS" "CREATED" "EXPIRES" "STORAGE"
        # Get data and sort by timestamp (3rd column) in reverse order
        if [[ -n "$filter_cluster" ]]; then
            kubectl get backups.velero.io -n velero --no-headers -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
CREATED:.status.startTimestamp,\
EXPIRES:.status.expiration,\
STORAGE:.spec.storageLocation | grep "^${filter_cluster}-backup-" | sort -k3 -r
        else
            kubectl get backups.velero.io -n velero --no-headers -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
CREATED:.status.startTimestamp,\
EXPIRES:.status.expiration,\
STORAGE:.spec.storageLocation | sort -k3 -r
        fi
    }
    
    echo
}

# Find backups with flexible pattern matching
find_backup() {
    local search_pattern="$1"
    
    log_info "Searching for backup: $search_pattern" >&2
    
    # Try exact match first
    if kubectl get backups.velero.io "$search_pattern" -n velero >/dev/null 2>&1; then
        echo "$search_pattern"
        return 0
    fi
    
    # Try fuzzy match with common patterns
    local found_backup=""
    
    # Pattern 1: lair-backup-YYYYMMDD-HHMMSS
    found_backup=$(kubectl get backups.velero.io -n velero -o jsonpath='{.items[?(@.metadata.name=="'"$search_pattern"'")].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$found_backup" ]]; then
        echo "$found_backup"
        return 0
    fi
    
    # Pattern 2: Latest backup matching prefix
    found_backup=$(kubectl get backups.velero.io -n velero --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[?(@.metadata.name=~"^'"$search_pattern"'.*")].metadata.name}' 2>/dev/null | tail -n1 || echo "")
    if [[ -n "$found_backup" ]]; then
        echo "$found_backup"
        return 0
    fi
    
    # Pattern 3: Any backup with lair in name
    if [[ "$search_pattern" == "lair"* ]] || [[ "$search_pattern" == *"lair"* ]]; then
        found_backup=$(kubectl get backups.velero.io -n velero --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[?(@.spec.includedNamespaces[*]=="lair")].metadata.name}' 2>/dev/null | tail -n1 || echo "")
        if [[ -n "$found_backup" ]]; then
            log_info "Found backup containing lair namespace: $found_backup"
            echo "$found_backup"
            return 0
        fi
    fi
    
    return 1
}

# Verify backup status
verify_backup() {
    local backup_name="$1"
    
    log_info "Verifying backup: $backup_name"
    
    # Check backup exists
    if ! kubectl get backups.velero.io "$backup_name" -n velero >/dev/null 2>&1; then
        log_err "Backup not found: $backup_name"
        return 1
    fi
    
    # Check backup status
    BACKUP_PHASE=$(kubectl get backups.velero.io "$backup_name" -n velero -o jsonpath='{.status.phase}')
    
    if [[ "$BACKUP_PHASE" != "Completed" ]]; then
        log_err "Backup status is '$BACKUP_PHASE' (expected: Completed)"
        log_info "Backup details:"
        kubectl describe backups.velero.io "$backup_name" -n velero | grep -A 10 "Status:"
        return 1
    fi
    
    log_ok "Backup status: Completed"
    
    # Show backup details
    log_info "Backup details:"
    kubectl get backups.velero.io "$backup_name" -n velero -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
ITEMS:.status.progress.itemsBackedUp,\
SIZE:.status.progress.totalItems,\
CREATED:.status.startTimestamp
    
    echo
    
    return 0
}

# Clean existing Lair installation
clean_lair_installation() {
    log_step "🧹 Cleaning Existing Lair Installation"
    
    # Check if lair namespace exists
    if ! kubectl get namespace lair >/dev/null 2>&1; then
        log_info "Lair namespace doesn't exist - nothing to clean"
        return 0
    fi
    
    log_warn "This will DELETE all existing Lair resources!"
    log_warn "  • All Pods will be terminated"
    log_warn "  • All PersistentVolumeClaims will be deleted"
    log_warn "  • All data in volumes will be lost"
    log_warn "  • Services, ConfigMaps, and Secrets will be removed"
    echo
    log_info "The restore will recreate everything from backup."
    echo
    
    # Only ask for confirmation in interactive mode
    if [[ -z "$BATCH_MODE" ]]; then
        read -p "Are you sure you want to proceed? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Cleanup cancelled"
            exit 0
        fi
    else
        log_info "Running in batch mode - proceeding with cleanup..."
    fi
    
    log_info "Starting cleanup sequence..."
    
    # Step 1: Scale down all deployments and statefulsets
    log_info "Scaling down workloads..."
    kubectl scale deployment --all --replicas=0 -n lair >/dev/null 2>&1 || true
    kubectl scale statefulset --all --replicas=0 -n lair >/dev/null 2>&1 || true
    
    # Wait for pods to terminate
    log_info "Waiting for pods to terminate (max 60s)..."
    kubectl wait --for=delete pod --all -n lair --timeout=60s 2>/dev/null || true
    
    # Force delete any remaining pods
    REMAINING_PODS=$(kubectl get pods -n lair --no-headers 2>/dev/null | wc -l | tr -d ' \n')
    if [[ "$REMAINING_PODS" -gt 0 ]]; then
        log_warn "Force deleting $REMAINING_PODS remaining pod(s)..."
        kubectl delete pods --all -n lair --force --grace-period=0 2>/dev/null || true
        
        # Check for stuck pods after force delete (with finalizers blocking deletion)
        sleep 5
        STUCK_PODS=$(kubectl get pods -n lair --no-headers 2>/dev/null | grep -c "Terminating" || echo "0")
        STUCK_PODS=$(echo "$STUCK_PODS" | tr -d ' \n')
        if [[ "$STUCK_PODS" -gt 0 ]]; then
            log_warn "$STUCK_PODS pod(s) still stuck in Terminating state - removing finalizers..."
            for pod in $(kubectl get pods -n lair --no-headers 2>/dev/null | grep "Terminating" | awk '{print $1}'); do
                log_info "Patching pod: $pod"
                kubectl patch pod "$pod" -n lair -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
            done
            sleep 3
        fi
    fi
    
    # Step 2: Delete PVCs (this will trigger PV deletion)
    log_info "Deleting PersistentVolumeClaims..."
    kubectl delete pvc --all -n lair --timeout=60s 2>/dev/null || true
    
    # Check for stuck PVCs (with finalizers blocking deletion)
    sleep 5
    STUCK_PVCS=$(kubectl get pvc -n lair --no-headers 2>/dev/null | grep -c "Terminating" || echo "0")
    STUCK_PVCS=$(echo "$STUCK_PVCS" | tr -d ' \n')
    if [[ "$STUCK_PVCS" -gt 0 ]]; then
        log_warn "$STUCK_PVCS PVC(s) stuck in Terminating state - removing finalizers..."
        for pvc in $(kubectl get pvc -n lair --no-headers 2>/dev/null | grep "Terminating" | awk '{print $1}'); do
            log_info "Patching PVC: $pvc"
            kubectl patch pvc "$pvc" -n lair -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null || true
        done
        sleep 3
    fi
    
    # Step 3: Delete all other resources
    log_info "Deleting remaining resources..."
    kubectl delete all --all -n lair --timeout=30s 2>/dev/null || true
    kubectl delete configmap --all -n lair 2>/dev/null || true
    kubectl delete secret --all -n lair 2>/dev/null || true
    kubectl delete ingress --all -n lair 2>/dev/null || true
    
    # Step 4: Verify cleanup
    REMAINING_RESOURCES=$(kubectl get all -n lair --no-headers 2>/dev/null | wc -l | tr -d ' \n')
    if [[ "$REMAINING_RESOURCES" -gt 0 ]]; then
        log_warn "$REMAINING_RESOURCES resource(s) still exist"
        log_info "Listing remaining resources:"
        kubectl get all -n lair
    else
        log_ok "All resources cleaned successfully"
    fi
    
    # Optional: Delete the namespace and recreate it (only in interactive mode)
    if [[ -z "$BATCH_MODE" ]]; then
        read -p "Do you want to delete and recreate the lair namespace? (yes/no): " delete_ns
        if [[ "$delete_ns" == "yes" ]]; then
            log_info "Deleting lair namespace..."
            kubectl delete namespace lair --timeout=120s || true
            
            log_info "Recreating lair namespace..."
            kubectl create namespace lair
            log_ok "Namespace recreated"
        fi
    else
        # In batch mode, always recreate namespace for clean restore
        log_info "Deleting lair namespace (batch mode)..."
        kubectl delete namespace lair --timeout=120s || true
        
        log_info "Recreating lair namespace..."
        kubectl create namespace lair
        log_ok "Namespace recreated"
    fi
    
    log_ok "Cleanup completed"
}

# Ensure StorageClass exists for Lair
# This handles backups created before includeClusterResources was added
ensure_storage_class() {
    local storage_class_name="${1:-lair-storage-longhorn}"
    
    log_info "Checking StorageClass: $storage_class_name"
    
    # Check if StorageClass already exists
    if kubectl get storageclass "$storage_class_name" >/dev/null 2>&1; then
        log_ok "StorageClass '$storage_class_name' already exists"
        return 0
    fi
    
    log_warn "StorageClass '$storage_class_name' not found"
    log_info "This is expected for backups created before v1.2.4"
    log_info "Creating StorageClass automatically..."
    
    # Detect number of nodes for replica count (min 1, max 3)
    local node_count
    node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    local replica_count=$node_count
    if [[ $replica_count -gt 3 ]]; then
        replica_count=3
    fi
    if [[ $replica_count -lt 1 ]]; then
        replica_count=1
    fi
    
    log_info "Detected $node_count node(s), using $replica_count replica(s)"
    
    # Check if Longhorn is available
    if ! kubectl get storageclass longhorn >/dev/null 2>&1; then
        log_err "Longhorn StorageClass not found!"
        log_err "Please ensure Longhorn is installed on this cluster."
        log_err "For MicroK8s: microk8s enable longhorn"
        return 1
    fi
    
    # Create the StorageClass
    cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $storage_class_name
  labels:
    app.kubernetes.io/managed-by: disaster-recovery-restore
    lair.io/platform: standard
  annotations:
    lair.io/description: "StorageClass created by disaster-recovery-restore.sh for backup compatibility"
parameters:
  numberOfReplicas: "$replica_count"
  staleReplicaTimeout: "30"
  fsType: "ext4"
  dataLocality: "disabled"
  disableRevisionCounter: "true"
  unmapMarkSnapChainRemoved: "ignored"
  fromBackup: ""
  dataEngine: "v1"
provisioner: driver.longhorn.io
reclaimPolicy: Delete
volumeBindingMode: Immediate
allowVolumeExpansion: true
EOF
    
    if [[ $? -eq 0 ]]; then
        log_ok "StorageClass '$storage_class_name' created successfully"
        log_info "Note: Future backups will include StorageClass automatically (v1.2.4+)"
    else
        log_err "Failed to create StorageClass"
        return 1
    fi
}

# Perform restore
perform_restore() {
    local backup_name="$1"
    local target_namespace="${2:-lair}"  # Default to 'lair' if not specified
    local restore_name="lair-restore-$(date +%Y%m%d-%H%M%S)"
    
    log_step "🔄 Starting Restore Process"
    
    log_info "Creating restore: $restore_name"
    log_info "From backup: $backup_name"
    if [[ "$target_namespace" != "lair" ]]; then
        log_info "Target namespace: $target_namespace (mapped from: lair)"
        
        # Create target namespace if it doesn't exist
        if ! kubectl get namespace "$target_namespace" >/dev/null 2>&1; then
            log_info "Creating namespace: $target_namespace"
            kubectl create namespace "$target_namespace"
            log_ok "Namespace created"
        fi
    fi
    echo
    
    # Ensure StorageClass exists (handles pre-v1.2.4 backups)
    log_step "🗄️ Verifying Storage Configuration"
    ensure_storage_class "lair-storage-longhorn"
    echo
    
    # Create restore with optional namespace mapping
    if [[ "$target_namespace" != "lair" ]]; then
        # Restore to different namespace
        cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: $restore_name
  namespace: velero
spec:
  backupName: $backup_name
  includedNamespaces:
  - lair
  namespaceMapping:
    lair: $target_namespace
  restorePVs: true
  preserveNodePorts: true
  excludedResources:
  - nodes
  - events
  - events.events.k8s.io
  - backups.velero.io
  - restores.velero.io
  - resticrepositories.velero.io
  - csinodes.storage.k8s.io
  - volumeattachments.storage.k8s.io
  - backuprepositories.velero.io
  itemOperationTimeout: 4h0m0s
EOF
    else
        # Normal restore to same namespace
        cat <<EOF | kubectl apply -f -
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: $restore_name
  namespace: velero
spec:
  backupName: $backup_name
  includedNamespaces:
  - lair
  restorePVs: true
  preserveNodePorts: true
  excludedResources:
  - nodes
  - events
  - events.events.k8s.io
  - backups.velero.io
  - restores.velero.io
  - resticrepositories.velero.io
  - csinodes.storage.k8s.io
  - volumeattachments.storage.k8s.io
  - backuprepositories.velero.io
  itemOperationTimeout: 4h0m0s
EOF
    fi
    
    log_ok "Restore created: $restore_name"
    
    # Monitor restore progress
    log_info "Monitoring restore progress..."
    echo
    
    local max_wait=600  # 10 minutes
    local elapsed=0
    local interval=10
    
    while [[ $elapsed -lt $max_wait ]]; do
        RESTORE_PHASE=$(kubectl get restore "$restore_name" -n velero -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        ITEMS_RESTORED=$(kubectl get restore "$restore_name" -n velero -o jsonpath='{.status.progress.itemsRestored}' 2>/dev/null || echo "0")
        TOTAL_ITEMS=$(kubectl get restore "$restore_name" -n velero -o jsonpath='{.status.progress.totalItems}' 2>/dev/null || echo "0")
        
        log_info "Status: $RESTORE_PHASE | Progress: $ITEMS_RESTORED/$TOTAL_ITEMS items"
        
        if [[ "$RESTORE_PHASE" == "Completed" ]]; then
            log_ok "Restore completed successfully!"
            break
        elif [[ "$RESTORE_PHASE" == "Failed" ]] || [[ "$RESTORE_PHASE" == "PartiallyFailed" ]]; then
            log_err "Restore failed or partially failed"
            break
        fi
        
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [[ $elapsed -ge $max_wait ]]; then
        log_warn "Restore still in progress after ${max_wait}s"
    fi
    
    # Show detailed restore status
    log_step "📊 Restore Summary"
    
    kubectl describe restore "$restore_name" -n velero
    
    # Check for warnings or errors
    WARNINGS=$(kubectl get restore "$restore_name" -n velero -o jsonpath='{.status.warnings}' 2>/dev/null || echo "0")
    ERRORS=$(kubectl get restore "$restore_name" -n velero -o jsonpath='{.status.errors}' 2>/dev/null || echo "0")
    
    # Clean up empty values
    WARNINGS="${WARNINGS:-0}"
    ERRORS="${ERRORS:-0}"
    
    # Only show if there are actual warnings or errors (> 0)
    if [[ "$WARNINGS" =~ ^[0-9]+$ ]] && [[ "$WARNINGS" -gt 0 ]]; then
        log_warn "⚠️  Restore completed with $WARNINGS warning(s)"
        log_info "Check logs for details: kubectl logs -n velero deployment/velero | grep '$restore_name'"
    fi
    
    if [[ "$ERRORS" =~ ^[0-9]+$ ]] && [[ "$ERRORS" -gt 0 ]]; then
        log_err "❌ Restore completed with $ERRORS error(s)"
        log_err "Check restore status: kubectl describe restore $restore_name -n velero"
    fi
    
    # Show success message if no errors
    if [[ "$ERRORS" == "0" ]] || [[ -z "$ERRORS" ]]; then
        if [[ "$WARNINGS" == "0" ]] || [[ -z "$WARNINGS" ]]; then
            log_ok "✅ Restore completed successfully with no warnings or errors!"
        fi
    fi
    
    # Check PodVolumeRestores (volume data restoration)
    log_step "💾 Verifying Volume Data Restoration"
    
    log_info "Checking for PodVolumeRestores..."
    PVR_COUNT=$(kubectl get podvolumerestores -n velero 2>/dev/null | grep -c "$restore_name" || echo "0")
    PVR_COUNT=$(echo "$PVR_COUNT" | tr -d ' \n')
    
    if [[ "$PVR_COUNT" == "0" ]]; then
        log_warn "⚠️  No PodVolumeRestores found!"
        log_warn "This means volume DATA was NOT restored!"
        log_warn ""
        log_warn "Most common cause: PVCs already existed before restore"
        log_warn "➜ Velero skips existing PVCs and does not restore data into them"
        log_warn ""
        log_warn "Solutions:"
        log_warn "  1. Use './disaster-recovery-restore.sh --clean-restore <backup>' to delete PVCs first"
        log_warn "  2. Manually delete PVCs before running restore"
        log_warn "  3. Restore to a fresh cluster (true disaster recovery)"
        log_warn ""
        log_warn "Other possible causes:"
        log_warn "  • Backup created without volume data (snapshotVolumes: false)"
        log_warn "  • node-agent not running during restore"
        log_warn "  • Backup contains no PodVolumeBackups"
        echo
    else
        log_ok "Found $PVR_COUNT PodVolumeRestore(s)"
        echo
        
        # Show PodVolumeRestore status
        log_info "PodVolumeRestore status:"
        kubectl get podvolumerestores -n velero | grep "$restore_name" || true
        echo
        
        # Check if all PVRs are completed
        if command -v jq >/dev/null 2>&1; then
            # Use jq if available
            PVR_COMPLETED=$(kubectl get podvolumerestores -n velero -o json 2>/dev/null | \
                jq -r ".items[] | select(.metadata.name | contains(\"$restore_name\")) | select(.status.phase == \"Completed\") | .metadata.name" | \
                wc -l | tr -d ' ' || echo "0")
        else
            # Fallback without jq
            PVR_COMPLETED=$(kubectl get podvolumerestores -n velero --no-headers 2>/dev/null | \
                grep "$restore_name" | grep -c "Completed" || echo "0")
        fi
        
        # Clean up any whitespace
        PVR_COMPLETED=$(echo "$PVR_COMPLETED" | tr -d ' \n')
        
        if [[ "$PVR_COMPLETED" == "$PVR_COUNT" ]]; then
            log_ok "All $PVR_COUNT PodVolumeRestores completed successfully!"
            log_ok "✅ Volume data has been restored"
        else
            log_warn "$PVR_COMPLETED/$PVR_COUNT PodVolumeRestores completed"
            log_info "Waiting for volume data restoration (max 5 minutes)..."
            
            # Wait for PVRs to complete
            local pvr_wait=0
            local pvr_max_wait=300
            log_info "(Press Ctrl+C to skip waiting and continue with verification)"
            while [[ $pvr_wait -lt $pvr_max_wait ]]; do
                if command -v jq >/dev/null 2>&1; then
                    PVR_COMPLETED=$(kubectl get podvolumerestores -n velero -o json 2>/dev/null | \
                        jq -r ".items[] | select(.metadata.name | contains(\"$restore_name\")) | select(.status.phase == \"Completed\") | .metadata.name" | \
                        wc -l | tr -d ' ' || echo "0")
                else
                    PVR_COMPLETED=$(kubectl get podvolumerestores -n velero --no-headers 2>/dev/null | \
                        grep "$restore_name" | grep -c "Completed" || echo "0")
                fi
                
                # Clean up whitespace
                PVR_COMPLETED=$(echo "$PVR_COMPLETED" | tr -d ' \n')
                
                if [[ "$PVR_COMPLETED" == "$PVR_COUNT" ]]; then
                    log_ok "All PodVolumeRestores completed!"
                    break
                fi
                
                log_info "Progress: $PVR_COMPLETED/$PVR_COUNT PodVolumeRestores completed..."
                sleep 10
                pvr_wait=$((pvr_wait + 10))
            done
            
            if [[ $pvr_wait -ge $pvr_max_wait ]]; then
                log_warn "Some PodVolumeRestores still in progress after 5 minutes"
            fi
        fi
    fi
    
    # Verify restored resources
    log_step "✅ Verifying Restored Resources"
    
    log_info "Pods in $target_namespace namespace:"
    kubectl get pods -n "$target_namespace" -o wide
    echo
    
    log_info "PersistentVolumeClaims in $target_namespace namespace:"
    kubectl get pvc -n "$target_namespace"
    echo
    
    log_info "Services in $target_namespace namespace:"
    kubectl get svc -n "$target_namespace"
    echo
    
    # Check pod health
    log_info "Waiting for pods to become ready (max 5 minutes)..."
    kubectl wait --for=condition=Ready pod --all -n "$target_namespace" --timeout=300s 2>/dev/null || log_warn "Some pods may not be ready yet"
    
    # Final verification
    log_step "🎯 Restore Verification Summary"
    
    echo "Kubernetes Resources:"
    TOTAL_PODS=$(kubectl get pods -n "$target_namespace" --no-headers 2>/dev/null | wc -l)
    READY_PODS=$(kubectl get pods -n "$target_namespace" --no-headers 2>/dev/null | grep -c " Running " || echo "0")
    echo "  ✅ Pods: $READY_PODS/$TOTAL_PODS running"
    
    TOTAL_PVC=$(kubectl get pvc -n "$target_namespace" --no-headers 2>/dev/null | wc -l)
    BOUND_PVC=$(kubectl get pvc -n "$target_namespace" --no-headers 2>/dev/null | grep -c " Bound " || echo "0")
    echo "  ✅ PVCs: $BOUND_PVC/$TOTAL_PVC bound"
    
    TOTAL_SVC=$(kubectl get svc -n "$target_namespace" --no-headers 2>/dev/null | wc -l)
    echo "  ✅ Services: $TOTAL_SVC created"
    echo
    
    echo "Volume Data Restoration:"
    # Re-count PVRs for verification summary (they may have been created after initial check)
    local PVR_COUNT_FINAL=$(kubectl get podvolumerestores -n velero 2>/dev/null | grep -c "$restore_name" || echo "0")
    PVR_COUNT_FINAL=$(echo "$PVR_COUNT_FINAL" | tr -d ' \n')
    local PVR_COMPLETED_FINAL=$(kubectl get podvolumerestores -n velero 2>/dev/null | grep "$restore_name" | grep -c "Completed" || echo "0")
    PVR_COMPLETED_FINAL=$(echo "$PVR_COMPLETED_FINAL" | tr -d ' \n')
    
    if [[ "$PVR_COUNT_FINAL" -gt 0 ]]; then
        echo "  ✅ PodVolumeRestores: $PVR_COMPLETED_FINAL/$PVR_COUNT_FINAL completed"
        echo "  ✅ Volume data: RESTORED"
    else
        echo "  ⚠️  PodVolumeRestores: 0 found"
        echo "  ⚠️  Volume data: NOT RESTORED (PVCs are EMPTY)"
    fi
    echo
    
    log_ok "Restore process completed!"
    log_info "Restore name: $restore_name"
    
    if [[ "$PVR_COUNT" == "0" ]]; then
        echo
        log_warn "⚠️  IMPORTANT: Volume data was NOT restored!"
        log_warn "Your databases, models, and documents are MISSING."
        log_warn "Check backup configuration and node-agent status."
    fi
}

# Interactive mode
interactive_mode() {
    log_step "🎯 Interactive Disaster Recovery"
    
    echo "This wizard will guide you through the restore process."
    echo
    
    # List backups
    list_backups
    
    # Ask for backup name
    echo
    read -p "Enter backup name to restore: " backup_name
    
    if [[ -z "$backup_name" ]]; then
        log_err "No backup name provided"
        exit 1
    fi
    
    # Find and verify backup
    FOUND_BACKUP=$(find_backup "$backup_name")
    if [[ -z "$FOUND_BACKUP" ]]; then
        log_err "Backup not found: $backup_name"
        exit 1
    fi
    
    log_ok "Found backup: $FOUND_BACKUP"
    
    if ! verify_backup "$FOUND_BACKUP"; then
        log_err "Backup verification failed"
        exit 1
    fi
    
    # Ask if user wants to clean first
    echo
    read -p "Do you want to clean existing Lair installation first? (recommended, yes/no): " clean_first
    
    if [[ "$clean_first" == "yes" ]]; then
        clean_lair_installation
        # Perform restore to default namespace
        perform_restore "$FOUND_BACKUP"
    else
        # Ask for target namespace
        echo
        log_warn "Without cleanup, restore may fail if resources already exist in 'lair' namespace."
        log_info "You can restore to a different namespace for testing (recommended)."
        echo
        read -p "Enter target namespace [default: lair]: " target_ns
        
        # Use default if empty
        target_ns="${target_ns:-lair}"
        
        if [[ "$target_ns" != "lair" ]]; then
            log_info "Will restore to namespace: $target_ns"
            perform_restore "$FOUND_BACKUP" "$target_ns"
        else
            log_warn "Restoring to 'lair' namespace without cleanup - this may fail!"
            read -p "Are you sure? (yes/no): " confirm
            if [[ "$confirm" == "yes" ]]; then
                perform_restore "$FOUND_BACKUP"
            else
                log_err "Restore cancelled by user"
                exit 1
            fi
        fi
    fi
}

# Main execution
main() {
    echo
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     LAIR DISASTER RECOVERY RESTORE                        ║"
    echo "║     Automated Kubernetes Application Recovery             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo
    
    # Check prerequisites first
    check_prerequisites
    
    # Parse arguments
    case "${1:-}" in
        --list-backups|-l)
            # Optional cluster filter as second argument
            list_backups "${2:-}"
            ;;
        --interactive|-i|"")
            interactive_mode
            ;;
        --clean-restore|-c)
            if [[ -z "${2:-}" ]]; then
                log_err "Backup name required for clean restore"
                exit 1
            fi
            
            BACKUP_NAME=$(find_backup "$2")
            if [[ -z "$BACKUP_NAME" ]]; then
                log_err "Backup not found: $2"
                exit 1
            fi
            
            verify_backup "$BACKUP_NAME" || exit 1
            
            # Set batch mode flag to skip interactive prompts
            BATCH_MODE=1
            clean_lair_installation
            perform_restore "$BACKUP_NAME"
            ;;
        --to-namespace|-n)
            if [[ -z "${2:-}" ]]; then
                log_err "Target namespace required"
                exit 1
            fi
            if [[ -z "${3:-}" ]]; then
                log_err "Backup name required"
                exit 1
            fi
            
            TARGET_NS="$2"
            BACKUP_NAME=$(find_backup "$3")
            if [[ -z "$BACKUP_NAME" ]]; then
                log_err "Backup not found: $3"
                exit 1
            fi
            
            verify_backup "$BACKUP_NAME" || exit 1
            perform_restore "$BACKUP_NAME" "$TARGET_NS"
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS] [BACKUP_NAME]"
            echo
            echo "Options:"
            echo "  --interactive, -i              Interactive mode (default)"
            echo "  --list-backups, -l [CLUSTER]   List available backups (optionally filter by cluster)"
            echo "  --clean-restore, -c BACKUP     Clean install before restore"
            echo "  --to-namespace, -n NS BACKUP   Restore to different namespace"
            echo "  --help, -h                     Show this help message"
            echo
            echo "Examples:"
            echo "  $0                                           # Interactive mode"
            echo "  $0 --list-backups                            # List all backups"
            echo "  $0 --list-backups zeus                       # List backups for cluster 'zeus'"
            echo "  $0 zeus-backup-20240921                      # Direct restore"
            echo "  $0 --clean-restore lair-backup               # Clean + restore"
            echo "  $0 --to-namespace lair-test lair-backup      # Restore to lair-test namespace"
            ;;
        *)
            # Direct restore mode
            BACKUP_NAME=$(find_backup "$1")
            if [[ -z "$BACKUP_NAME" ]]; then
                log_err "Backup not found: $1"
                exit 1
            fi
            
            verify_backup "$BACKUP_NAME" || exit 1
            perform_restore "$BACKUP_NAME"
            ;;
    esac
    
    echo
    log_ok "✨ All operations completed!"
    echo
}

# Run main function
main "$@"
