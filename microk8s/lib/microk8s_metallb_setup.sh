#!/usr/bin/env bash

# region 26) MetalLB enablement
info "Enabling MetalLB range=$METALLB_RANGES..."
debug "MetalLB configuration with pool $METALLB_RANGES"

# On Jetson with Flannel, MetalLB might have issues - adding extra checks
if $IS_JETSON && [ -n "$CUSTOM_CNI" ] && [ "$CUSTOM_CNI" = "flannel" ]; then
  info "MetalLB configuration on Jetson with Flannel - using conservative configuration"
  
  # Intelligent check instead of fixed sleep
  info "Waiting for Flannel stabilization before MetalLB..."
  for i in {1..30}; do
    # Verify that at least 2 core pods are Running (Jetson-safe)
    RUNNING_PODS=$(microk8s kubectl get pods --all-namespaces 2>/dev/null | grep "Running" | wc -l || echo "0")
    # Ensure RUNNING_PODS is a single integer (fix for Jetson)
    RUNNING_PODS=$(echo "$RUNNING_PODS" | tr -d '[:space:]' | head -c 10)
    [ -z "$RUNNING_PODS" ] && RUNNING_PODS="0"
    if [ "$RUNNING_PODS" -ge 2 ] 2>/dev/null; then
      debug "Flannel stabilized with $RUNNING_PODS Running pods after ${i} seconds"
      break
    fi
    if [ $i -eq 30 ]; then
      warn "Flannel not completely stable after 30 seconds, continuing anyway"
    fi
    if [ $((i % 5)) -eq 0 ]; then
      debug "Waiting for Flannel stabilization... ${i}/30s (Running pods: $RUNNING_PODS)"
    fi
    sleep 1
  done
  
  # Verify that base pods are working before adding MetalLB
  info "Verifying that base pods are operational..."
  if ! microk8s kubectl get pods --all-namespaces | grep -q "Running"; then
    warn "No pods in Running state - there might be an issue with Flannel"
    warn "Checking flanneld logs..."
    run_cmd "journalctl -u snap.microk8s.daemon-flanneld --no-pager -n 20" "Log flanneld" || true
  fi
fi

enable_addon metallb:$METALLB_RANGES 5 metallb-system
# endregion 26) MetalLB enablement
