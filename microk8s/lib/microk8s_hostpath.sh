#!/usr/bin/env bash

# region 24) Hostpath-provisioner patch for Jetson
if $IS_JETSON; then
  info "Jetson system: enabling hostpath-storage addon..."
  run_cmd "microk8s enable hostpath-storage" "Enabling hostpath-storage addon for Jetson"
  
  info "Jetson system: applying hostpath-provisioner patch..."
  
  # Check if there's already a working deployment
  EXISTING_PODS=$(microk8s kubectl -n kube-system get pods -l k8s-app=hostpath-provisioner --field-selector=status.phase=Running 2>/dev/null | wc -l)
  
  if [ "$EXISTING_PODS" -gt 1 ]; then
    info "Hostpath-provisioner already working on Jetson, skipping patch"
  else
    # Wait for the deployment to be created
    info "Waiting for hostpath-provisioner ready (max 3')..."
    microk8s kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=hostpath-provisioner --timeout=180s || true
    
    # Check if there's already a deployment with correct image for Jetson
    if microk8s kubectl -n kube-system get deployment -o yaml | grep -q "cdkbot/hostpath-provisioner"; then
      info "Hostpath-provisioner deployment already with correct image for Jetson"
    else
      info "Patching hostpath-provisioner for Jetson..."
      # Use the correct image that works on Jetson
      if microk8s kubectl -n kube-system get deployment hostpath-provisioner >/dev/null 2>&1; then
        microk8s kubectl -n kube-system patch deployment hostpath-provisioner \
          --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"cdkbot/hostpath-provisioner:1.5.0"}]' || warn "Hostpath-provisioner patch failed, but continuing"
        ok "Hostpath-provisioner patch for Jetson applied"
      else
        warn "Hostpath-provisioner deployment not found for Jetson patch"
      fi
    fi
  fi
  
  # Cleanup any failed duplicate deployments
  info "Cleaning up any duplicate hostpath-provisioner deployments..."
  FAILED_REPLICAS=$(microk8s kubectl -n kube-system get replicaset -l k8s-app=hostpath-provisioner -o jsonpath='{.items[?(@.status.readyReplicas==0)].metadata.name}' 2>/dev/null || echo "")
  if [ -n "$FAILED_REPLICAS" ]; then
    for replica in $FAILED_REPLICAS; do
      info "Removing failed replica: $replica"
      microk8s kubectl -n kube-system delete replicaset "$replica" --ignore-not-found=true || true
    done
  fi
else
  info "Non-Jetson system, skipping hostpath-provisioner patch"
fi
# endregion 24) Hostpath-provisioner patch for Jetson
