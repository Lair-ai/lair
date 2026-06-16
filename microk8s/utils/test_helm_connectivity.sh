#!/usr/bin/env bash

# Test script to verify Helm connectivity with MicroK8s
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Source required libraries
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/helpers.sh"

info "🧪 Testing Helm connectivity with MicroK8s"

# Check if MicroK8s is running
if ! microk8s status --wait-ready >/dev/null 2>&1; then
  err "MicroK8s is not running or ready"
  exit 1
fi
ok "MicroK8s is running and ready"

# Test microk8s kubectl connectivity
info "Testing microk8s kubectl connectivity..."
if microk8s kubectl cluster-info >/dev/null 2>&1; then
  ok "microk8s kubectl can connect to cluster"
else
  err "microk8s kubectl cannot connect to cluster"
  exit 1
fi

# Test microk8s helm3 availability
info "Testing microk8s helm3 availability..."
if microk8s helm3 version >/dev/null 2>&1; then
  ok "microk8s helm3 is available"
  microk8s helm3 version --short
else
  err "microk8s helm3 is not available"
  exit 1
fi

# Test helm repo operations
info "Testing helm repo operations..."
if microk8s helm3 repo list >/dev/null 2>&1; then
  ok "microk8s helm3 can list repositories"
  echo "Current repositories:"
  microk8s helm3 repo list
else
  warn "microk8s helm3 repo list failed, but this might be normal if no repos are configured"
fi

# Test adding a repository (non-destructive)
info "Testing repository addition..."
if microk8s helm3 repo add stable https://charts.helm.sh/stable >/dev/null 2>&1; then
  ok "microk8s helm3 can add repositories"
else
  warn "microk8s helm3 repo add failed (might already exist)"
fi

# Test helm list
info "Testing helm list..."
if microk8s helm3 list -A >/dev/null 2>&1; then
  ok "microk8s helm3 can list releases"
  echo "Current releases:"
  microk8s helm3 list -A
else
  warn "microk8s helm3 list failed"
fi

# Compare with regular helm (should fail)
info "Testing regular helm (should fail with connection error)..."
if command -v helm >/dev/null 2>&1; then
  if helm version >/dev/null 2>&1; then
    warn "Regular helm can connect (unexpected - might be configured correctly)"
    helm version --short
  else
    ok "Regular helm fails as expected (no kubeconfig for MicroK8s)"
    echo "Error from regular helm:"
    helm version 2>&1 | head -3
  fi
else
  info "Regular helm not found in PATH"
fi

info "🧪 Helm connectivity test completed"
