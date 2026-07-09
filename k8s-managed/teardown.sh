#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Global variables
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logger ANSI colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging functions
timestamp() { date -Iseconds; }
log() { printf '[%s] %s: %s\n' "$(timestamp)" "$1" "$2"; }
info() { printf '%b' "$BLUE";  log "INFO"  "$1"; printf '%b' "$NC"; }
ok()   { printf '%b' "$GREEN"; log "OK"    "$1"; printf '%b' "$NC"; }
warn() { printf '%b' "$YELLOW";log "WARN"  "$1"; printf '%b' "$NC"; }
err()  { printf '%b' "$RED";   log "ERROR" "$1"; printf '%b' "$NC"; }

# Function to redact secrets from commands
redact_secrets() {
  local input="$1"
  printf "%s\n" "$input" | sed -E \
    -e "s/(aws_secret_access_key[[:space:]]*=[[:space:]]*['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/(aws_access_key_id[[:space:]]*=[[:space:]]*['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/(--from-literal=[^'\"[:space:]=]+=['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/(--from-literal=['\"]?[^'\"[:space:]=]+=[[:space:]]*)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/((token|password|secret|key|passwd)[[:space:]]*=[[:space:]]*['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/(--?(token|password|secret|key|passwd)[[:space:]]+['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI"
}

# Function to execute commands with retry
run_cmd() {
  local cmd="$1"
  local max_attempts="${2:-1}"
  local attempt=1
  
  local redacted_cmd
  redacted_cmd=$(redact_secrets "$cmd")
  
  while [ $attempt -le $max_attempts ]; do
    info "Execution (attempt $attempt/$max_attempts): $redacted_cmd"
    if eval "$cmd"; then
      ok "Command executed successfully."
      return 0
    else
      if [ $attempt -eq $max_attempts ]; then
        err "Error executing command after $max_attempts attempts: $redacted_cmd"
        return 1
      else
        warn "Attempt $attempt failed, retrying in 5 seconds..."
        sleep 5
      fi
    fi
    ((attempt++))
  done
}

# Function to wait for namespace deletion
wait_for_namespace_deletion() {
  local namespace="$1"
  local timeout="${2:-120}"
  local elapsed=0
  
  info "Waiting for namespace $namespace deletion..."
  while kubectl get namespace "$namespace" &> /dev/null && [ $elapsed -lt $timeout ]; do
    sleep 5
    elapsed=$((elapsed + 5))
    info "Namespace $namespace still present... ($elapsed/$timeout seconds)"
  done
  
  if kubectl get namespace "$namespace" &> /dev/null; then
    warn "Timeout reached for namespace $namespace deletion"
    return 1
  else
    ok "Namespace $namespace deleted successfully"
    return 0
  fi
}

# Advanced Longhorn cleanup with corruption detection
force_cleanup_longhorn() {
  info "Starting advanced Longhorn cleanup..."
  
  # STEP 0A: Remove problematic webhooks that might interfere with cleanup
  info "Removing Longhorn webhooks that could interfere with cleanup..."
  kubectl delete validatingwebhookconfiguration longhorn-webhook-validator 2>/dev/null || true
  kubectl delete mutatingwebhookconfiguration longhorn-webhook-mutator 2>/dev/null || true
  
  # STEP 0B: Clean up any stuck uninstall jobs first
  info "Cleaning up stuck Longhorn uninstall jobs..."
  local stuck_jobs=$(kubectl get jobs -n longhorn-system --no-headers 2>/dev/null | grep -E "(uninstall|Failed|Error)" | awk '{print $1}')
  if [ -n "$stuck_jobs" ]; then
    echo "$stuck_jobs" | while read -r job; do
      if [ -n "$job" ]; then
        warn "Removing stuck job: $job"
        kubectl delete job "$job" -n longhorn-system --force --grace-period=0 2>/dev/null || true
      fi
    done
  fi
  
  # Clean up all pods first to stop any running processes
  info "Force stopping all Longhorn pods..."
  kubectl delete pods --all -n longhorn-system --force --grace-period=0 2>/dev/null || true
  
  # Wait briefly for pods to terminate
  sleep 3
  
  # STEP 1: Remove finalizers from all Longhorn resources BEFORE deleting the namespace
  info "Removing finalizers from Longhorn resources..."
  
  # Remove finalizers from all PVCs in longhorn-system namespace
  local pvc_count=$(kubectl get pvc -n longhorn-system --no-headers 2>/dev/null | wc -l)
  info "Processing $pvc_count PVCs in longhorn-system..."
  kubectl get pvc -n longhorn-system -o name 2>/dev/null | while read -r pvc; do
    if [ -n "$pvc" ]; then
      kubectl patch "$pvc" -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    fi
  done
  
  # Remove finalizers from all PVs with longhorn storageclass
  local pv_count=$(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.storageClassName == "longhorn") | .metadata.name' 2>/dev/null | wc -l)
  info "Processing $pv_count PVs with Longhorn storage class..."
  kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.storageClassName == "longhorn") | .metadata.name' 2>/dev/null | while read -r pv; do
    if [ -n "$pv" ]; then
      kubectl patch pv "$pv" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    fi
  done
  
  # STEP 2: Force deletion of custom Longhorn resources with enhanced logging
  info "Force deleting custom Longhorn resources..."
  
  # Handle nodes.longhorn.io
  local node_count=$(kubectl get nodes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l)
  if [ "$node_count" -gt 0 ]; then
    info "Processing $node_count Longhorn nodes..."
    kubectl get nodes.longhorn.io -n longhorn-system -o name 2>/dev/null | while read -r node; do
      if [ -n "$node" ]; then
        kubectl patch "$node" -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete "$node" -n longhorn-system --force --grace-period=0 2>/dev/null || true
      fi
    done
  fi
  
  # Handle engineimage.longhorn.io
  local ei_count=$(kubectl get engineimage.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l)
  if [ "$ei_count" -gt 0 ]; then
    info "Processing $ei_count Longhorn engine images..."
    kubectl get engineimage.longhorn.io -n longhorn-system -o name 2>/dev/null | while read -r ei; do
      if [ -n "$ei" ]; then
        kubectl patch "$ei" -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete "$ei" -n longhorn-system --force --grace-period=0 2>/dev/null || true
      fi
    done
  fi
  
  # Handle volumes.longhorn.io specifically
  local volume_count=$(kubectl get volumes.longhorn.io -n longhorn-system --no-headers 2>/dev/null | wc -l)
  if [ "$volume_count" -gt 0 ]; then
    info "Processing $volume_count Longhorn volumes..."
    kubectl get volumes.longhorn.io -n longhorn-system -o name 2>/dev/null | while read -r volume; do
      if [ -n "$volume" ]; then
        kubectl patch "$volume" -n longhorn-system -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete "$volume" -n longhorn-system --force --grace-period=0 2>/dev/null || true
      fi
    done
  fi
  
  # STEP 3: Delete all other resources with better error handling
  info "Force deleting other Longhorn resources..."
  kubectl delete all --all -n longhorn-system --force --grace-period=0 2>/dev/null || true
  
  # STEP 4: Clean up remaining workloads
  info "Cleaning up remaining Longhorn workloads..."
  kubectl delete daemonset -n longhorn-system --all --force --grace-period=0 2>/dev/null || true
  kubectl delete statefulset -n longhorn-system --all --force --grace-period=0 2>/dev/null || true
  kubectl delete configmap -n longhorn-system --all --force --grace-period=0 2>/dev/null || true
  kubectl delete secret -n longhorn-system --all --force --grace-period=0 2>/dev/null || true
  
  ok "Advanced Longhorn cleanup completed"
}

# Function for safe CRD cleanup
cleanup_longhorn_crds() {
  info "Cleaning up Longhorn CRDs..."
  
  local longhorn_crds=$(kubectl get crd | grep longhorn | awk '{print $1}')
  
  if [ -z "$longhorn_crds" ]; then
    info "No Longhorn CRDs found"
    return 0
  fi
  
  info "Longhorn CRDs found: $(echo "$longhorn_crds" | wc -l)"
  
  # First try to delete CRDs normally
  echo "$longhorn_crds" | while read -r crd; do
    if [ -n "$crd" ]; then
      info "Attempting normal deletion for CRD: $crd"
      if kubectl delete crd "$crd" --timeout=10s --wait=false 2>/dev/null; then
        ok "CRD $crd deleted normally"
      else
        warn "CRD $crd stuck, trying finalizer removal..."
        
        # Remove finalizers from stuck CRD
        if kubectl patch crd "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null; then
          info "Finalizers removed from $crd"
          sleep 2
          
          # Check if CRD was automatically deleted
          if kubectl get crd "$crd" &> /dev/null; then
            warn "CRD $crd still present, trying manual deletion..."
            kubectl delete crd "$crd" --force --grace-period=0 2>/dev/null || true
          else
            ok "CRD $crd automatically deleted after finalizer removal"
          fi
        else
          err "Unable to remove finalizers from $crd"
        fi
      fi
    fi
  done
  
  # Final verification with additional cleanup for stubborn CRDs
  sleep 5
  local remaining_crds=$(kubectl get crd | grep longhorn | wc -l)
  
  if [ "$remaining_crds" -gt 0 ]; then
    warn "There are still $remaining_crds stuck Longhorn CRDs:"
    kubectl get crd | grep longhorn || true
    warn "Attempting aggressive cleanup of remaining CRDs..."
    
    # Try aggressive cleanup for remaining CRDs
    kubectl get crd | grep longhorn | awk '{print $1}' | while read -r crd; do
      if [ -n "$crd" ]; then
        info "Aggressively cleaning CRD: $crd"
        kubectl patch crd "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        sleep 1
        kubectl delete crd "$crd" --force --grace-period=0 2>/dev/null || true
      fi
    done
    
    # Final check
    sleep 3
    local final_remaining=$(kubectl get crd | grep longhorn | wc -l)
    if [ "$final_remaining" -gt 0 ]; then
      warn "Still $final_remaining CRDs remain - may need manual intervention"
    else
      ok "All stubborn CRDs successfully removed with aggressive cleanup"
    fi
  else
    ok "All Longhorn CRDs have been successfully removed"
  fi
}

# Function to detect corruption and provide diagnostics
detect_cluster_corruption() {
  local namespace="$1"
  info "Detecting corruption in namespace $namespace..."
  
  if ! kubectl get namespace "$namespace" &> /dev/null; then
    info "Namespace $namespace does not exist"
    return 0
  fi
  
  local corruption_detected=false
  
  # Check for stuck pods
  local stuck_pods=$(kubectl get pods -n "$namespace" --field-selector=status.phase!=Running,status.phase!=Succeeded,status.phase!=Pending --no-headers 2>/dev/null | wc -l)
  if [ "$stuck_pods" -gt 0 ]; then
    warn "Found $stuck_pods stuck pods in $namespace"
    corruption_detected=true
  fi
  
  # Check for failed jobs
  local failed_jobs=$(kubectl get jobs -n "$namespace" --field-selector=status.successful!=1 --no-headers 2>/dev/null | wc -l)
  if [ "$failed_jobs" -gt 0 ]; then
    warn "Found $failed_jobs failed jobs in $namespace"
    corruption_detected=true
  fi
  
  # Check for orphaned resources (pods without controller)
  local orphaned_pods=$(kubectl get pods -n "$namespace" -o json 2>/dev/null | jq -r '.items[] | select(.metadata.ownerReferences == null) | .metadata.name' 2>/dev/null | wc -l)
  if [ "$orphaned_pods" -gt 0 ]; then
    warn "Found $orphaned_pods orphaned pods in $namespace"
    corruption_detected=true
  fi
  
  if [ "$corruption_detected" = true ]; then
    warn "Corruption detected in namespace $namespace - will use forced cleanup"
    return 1
  else
    info "No corruption detected in namespace $namespace"
    return 0
  fi
}

# Enhanced function to force deletion of a stuck namespace
force_delete_namespace() {
  local namespace="$1"
  info "Forcing deletion of namespace $namespace..."
  
  if kubectl get namespace "$namespace" &> /dev/null; then
    # First attempt: try to clear all finalizers from resources in the namespace
    info "Clearing finalizers from all resources in $namespace..."
    kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | while read -r resource; do
      kubectl get "$resource" -n "$namespace" -o name 2>/dev/null | while read -r obj; do
        if [ -n "$obj" ]; then
          kubectl patch "$obj" -n "$namespace" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        fi
      done
    done
    
    # Wait a moment for finalizers to be processed
    sleep 5
    
    # Second attempt: force delete the namespace itself
    kubectl get namespace "$namespace" -o json | jq '.spec.finalizers = []' | kubectl replace --raw "/api/v1/namespaces/$namespace/finalize" -f - 2>/dev/null || true
    ok "Finalizer removed from namespace $namespace"
  else
    info "Namespace $namespace already deleted"
  fi
}

# Pre-flight checks for better teardown
preflight_checks() {
    info "Running pre-flight checks..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        err "kubectl not found. Please install kubectl to continue."
        exit 1
    fi

    # Check if Helm is installed
    if ! command -v helm &> /dev/null; then
        err "Helm not found. Please install Helm to continue."
        exit 1
    fi
    
    # Check if jq is available (needed for JSON processing)
    if ! command -v jq &> /dev/null; then
        err "jq not found. Please install jq to continue."
        exit 1
    fi
    
    # Test cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        err "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    # Check cluster permissions
    if ! kubectl auth can-i delete namespace &> /dev/null; then
        err "Insufficient permissions to delete namespaces. Please check your RBAC configuration."
        exit 1
    fi
    
    # Display cluster context for confirmation
    local current_context=$(kubectl config current-context 2>/dev/null || echo "unknown")
    warn "Current kubectl context: $current_context"
    
    # Show what namespaces will be affected
    local affected_ns=$(kubectl get namespace | grep -E "(longhorn-system|ingress-nginx|cert-manager)" | awk '{print $1}' | tr '\n' ' ')
    if [ -n "$affected_ns" ]; then
        warn "Namespaces that will be deleted: $affected_ns"
    else
        info "No target namespaces found - teardown may have limited effect"
    fi
    
    ok "Pre-flight checks completed"
}

# Main function
main() {
    info "Starting K8s Managed teardown script..."
    
    # Run comprehensive pre-flight checks
    preflight_checks

    # Uninstalling Longhorn (first to avoid dependencies)
    info "Uninstalling Longhorn..."
    
    # First check for corruption in longhorn-system namespace
    if kubectl get namespace longhorn-system &> /dev/null; then
        if ! detect_cluster_corruption "longhorn-system"; then
            warn "Corruption detected in longhorn-system, will use forced cleanup"
            force_cleanup_longhorn
        else
            # Try normal Helm uninstall for clean state
            if helm status longhorn -n longhorn-system &> /dev/null; then
                if ! run_cmd "helm uninstall longhorn -n longhorn-system --timeout=180s" 2; then
                    warn "Standard Longhorn uninstallation failed, proceeding with forced cleanup..."
                    force_cleanup_longhorn
                fi
            else
                warn "Longhorn Helm release not found but namespace exists, proceeding with forced cleanup..."
                force_cleanup_longhorn
            fi
        fi
    else
        info "Longhorn namespace not found, skipping uninstallation."
    fi

    # Cleanup Longhorn CRDs before deleting namespaces
    cleanup_longhorn_crds

    # NGINX Ingress Controller uninstallation
    info "Uninstalling NGINX Ingress Controller..."
    if helm status ingress-nginx -n ingress-nginx &> /dev/null; then
        run_cmd "helm uninstall ingress-nginx -n ingress-nginx --timeout=180s" 2
    else
        warn "NGINX Ingress Controller not found, skipping uninstallation."
    fi

    # Cert-Manager uninstallation
    info "Uninstalling Cert-Manager..."
    if helm status cert-manager -n cert-manager &> /dev/null; then
        run_cmd "helm uninstall cert-manager -n cert-manager --timeout=180s" 2
    else
        warn "Cert-Manager not found, skipping uninstallation."
    fi

    # Namespace cleanup with waiting
    info "Cleaning up namespaces..."
    
    # Delete namespaces one at a time and wait
    for namespace in longhorn-system ingress-nginx cert-manager; do
      if kubectl get namespace "$namespace" &> /dev/null; then
        info "Deleting namespace $namespace..."
        kubectl delete namespace "$namespace" --ignore-not-found --timeout=60s || true
        if ! wait_for_namespace_deletion "$namespace" 180; then
          warn "Namespace $namespace stuck, proceeding with forced deletion..."
          force_delete_namespace "$namespace"
          # Brief wait to verify forced deletion
          sleep 5
          if kubectl get namespace "$namespace" &> /dev/null; then
            err "Unable to delete namespace $namespace even with forced deletion"
          else
            ok "Namespace $namespace successfully deleted via forced deletion"
          fi
        fi
      else
        info "Namespace $namespace already deleted or non-existent"
      fi
    done

    # Final cleanup of orphaned resources
    info "Cleaning up orphaned resources..."
    
    # Remove Longhorn storage classes if still present
    kubectl delete storageclass longhorn --ignore-not-found 2>/dev/null || true
    
    # Final webhook cleanup - remove any webhooks that might have been recreated
    info "Final cleanup of Longhorn webhooks..."
    kubectl delete validatingwebhookconfiguration longhorn-webhook-validator 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration longhorn-webhook-mutator 2>/dev/null || true
    
    # Cleanup remaining cert-manager CRDs
    info "Cleaning up cert-manager CRDs..."
    local certmanager_crds=$(kubectl get crd | grep cert-manager | awk '{print $1}')
    
    if [ -n "$certmanager_crds" ]; then
      echo "$certmanager_crds" | while read -r crd; do
        if [ -n "$crd" ]; then
          info "Attempting cert-manager CRD deletion: $crd"
          if kubectl delete crd "$crd" --timeout=10s --wait=false 2>/dev/null; then
            ok "cert-manager CRD $crd deleted"
          else
            warn "CRD $crd stuck, trying finalizer removal..."
            kubectl patch crd "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            sleep 2
            kubectl delete crd "$crd" --force --grace-period=0 2>/dev/null || warn "CRD $crd not deleted"
          fi
        fi
      done
    else
      info "No cert-manager CRDs found"
    fi

    # Log directory cleanup
    info "Cleaning up log directory..."
    if [ -d "$SCRIPT_DIR/k8s-managed-setup-logs" ]; then
        rm -rf "$SCRIPT_DIR/k8s-managed-setup-logs"
        ok "Log directory removed."
    fi

    # Final verification and comprehensive report
    info "Final verification of cluster state..."
    
    # Check remaining namespaces
    local remaining_ns=$(kubectl get namespace | grep -E "(longhorn-system|ingress-nginx|cert-manager)" | wc -l)
    if [ "$remaining_ns" -eq 0 ]; then
        ok "✅ All target namespaces have been successfully removed"
    else
        warn "⚠️  Some namespaces may still be present:"
        kubectl get namespace | grep -E "(longhorn-system|ingress-nginx|cert-manager)" || true
    fi
    
    # Check remaining Helm releases
    local remaining_releases=$(helm list -A --short | grep -E "(longhorn|ingress-nginx|cert-manager)" | wc -l)
    if [ "$remaining_releases" -eq 0 ]; then
        ok "✅ All target Helm releases have been removed"
    else
        warn "⚠️  Some Helm releases may still be present:"
        helm list -A | grep -E "(longhorn|ingress-nginx|cert-manager)" || true
    fi
    
    # Check remaining CRDs
    local remaining_crds=$(kubectl get crd | grep -E "(longhorn|cert-manager)" | wc -l)
    if [ "$remaining_crds" -eq 0 ]; then
        ok "✅ All target CRDs have been removed"
    else
        warn "⚠️  Some CRDs may still be present:"
        kubectl get crd | grep -E "(longhorn|cert-manager)" || true
    fi
    
    # Check storage classes
    local remaining_sc=$(kubectl get storageclass | grep longhorn | wc -l)
    if [ "$remaining_sc" -eq 0 ]; then
        ok "✅ Longhorn storage class has been removed"
    else
        warn "⚠️  Longhorn storage class may still be present"
    fi
    
    # Check webhooks
    local remaining_validating_webhooks=$(kubectl get validatingwebhookconfigurations | grep longhorn | wc -l)
    local remaining_mutating_webhooks=$(kubectl get mutatingwebhookconfigurations | grep longhorn | wc -l)
    local total_webhooks=$((remaining_validating_webhooks + remaining_mutating_webhooks))
    if [ "$total_webhooks" -eq 0 ]; then
        ok "✅ All Longhorn webhooks have been removed"
    else
        warn "⚠️  Some Longhorn webhooks may still be present:"
        kubectl get validatingwebhookconfigurations | grep longhorn || true
        kubectl get mutatingwebhookconfigurations | grep longhorn || true
    fi
    
    # Final status
    local total_issues=$((remaining_ns + remaining_releases + remaining_crds + remaining_sc + total_webhooks))
    if [ "$total_issues" -eq 0 ]; then
        ok "🎉 Teardown completed successfully! Cluster is clean."
    else
        warn "⚠️  Teardown completed with $total_issues potential issues. Manual cleanup may be required."
    fi
}

# Signal handling for cleanup in case of interruption
trap 'err "Script interrupted by signal"; exit 1' INT TERM

# Script execution
main