#!/usr/bin/env bash

# region 27) Longhorn installation with extended diagnostics
if ! $IS_JETSON; then
  info "Installing Longhorn..."

  # region 27.1) Installation of dependencies and host prerequisites for Longhorn
  info "Installing dependencies for Longhorn (open-iscsi, nfs-common, util-linux)..."
  run_cmd "DEBIAN_FRONTEND=noninteractive apt update -y && \
           DEBIAN_FRONTEND=noninteractive apt install -y nfs-common util-linux" \
           "Installing Longhorn base packages"

  # ── iSCSI: service and kernel modules ─────────────────────────────────────────
  info "Enabling and starting iSCSI services..."
  run_cmd "DEBIAN_FRONTEND=noninteractive apt update -qq" "Updating package list"

  # 1. Ensure the tools are present
  run_cmd "DEBIAN_FRONTEND=noninteractive apt install -y open-iscsi" "Installing open-iscsi"

  # 2. Enable both daemon and client parts
  run_cmd "systemctl enable --now iscsid open-iscsi" "Enabling iSCSI services"

  # 3. Check if the module is already loadable (without generating error output)
  if ! modprobe -n -q iscsi_tcp 2>/dev/null; then
    warn "iscsi_tcp module not available, installing additional modules..."

    # 3a. Try the specific package first (lighter, useful on linux-virtual)
    if ! run_cmd "DEBIAN_FRONTEND=noninteractive apt install -y linux-modules-extra-\$(uname -r)" \
                 "Installing linux-modules-extra"; then
      warn "modules-extra package missing, installing the entire linux-generic stack"
      run_cmd "DEBIAN_FRONTEND=noninteractive apt install -y linux-generic" \
              "Installing linux-generic (includes image + modules-extra)"
    fi

    # 3b. Regenerate dependencies and initramfs
    run_cmd "depmod -a" "Regenerating depmod"
    run_cmd "update-initramfs -u" "Updating initramfs"

    # 3c. Load the module again
    run_cmd "modprobe iscsi_tcp" "Loading iscsi_tcp module (post install)"
  else
    debug "iscsi_tcp module already present in kernel"
    # Load the module if not already loaded
    if ! lsmod | grep -q '^iscsi_tcp'; then
      run_cmd "modprobe iscsi_tcp" "Loading iscsi_tcp module"
    else
      debug "iscsi_tcp module already loaded"
    fi
  fi

  # Persistence across reboots
  if [ ! -f /etc/modules-load.d/iscsi_tcp.conf ]; then
    echo iscsi_tcp | tee /etc/modules-load.d/iscsi_tcp.conf >/dev/null
    ok "iscsi_tcp module made persistent"
  fi

  # ── FIX Longhorn BUG (replica log) ─────────────────────────────────────────
  # Some Longhorn versions fail if /var/log/instances doesn't exist.
  info "Fix Longhorn instance-manager (creating /var/log/instances)…"
  run_cmd "mkdir -p /var/log/instances && chmod 1777 /var/log/instances" \
          "Creating /var/log/instances directory"
  # endregion 27.1) Installation of dependencies and host prerequisites for Longhorn

  # region 27.2) Adding Helm repository and updating
  debug "Adding Helm repository and updating"
  run_cmd "microk8s helm3 repo add longhorn https://charts.longhorn.io" "Adding Longhorn repository"
  run_cmd "microk8s helm3 repo update" "Updating Helm repositories"
  # endregion 27.2) Adding Helm repository and updating

  # region 27.3) Verifying Longhorn prerequisites
  debug "Verifying Longhorn prerequisites"
  run_cmd "which curl" "Checking curl presence" || run_cmd "DEBIAN_FRONTEND=noninteractive apt install -y curl" "Installing curl"
  run_cmd "df -h" "Disk space" || true
  # endregion 27.3) Verifying Longhorn prerequisites

  # region 27.4) Installing jq dependency for idempotent patching
  info "Installing jq dependency for idempotent patching..."
  run_cmd "DEBIAN_FRONTEND=noninteractive apt update -y" "Updating package list for jq"
  run_cmd "DEBIAN_FRONTEND=noninteractive apt install -y jq" "Installing jq"
  ok "jq installed"
  # endregion 27.4) Installing jq dependency for idempotent patching

  # region 27.5) Longhorn installation / upgrade (auto-adaptive replica-count)
  info "Checking if Longhorn is already installed..."

  # Dynamic replica calculation
  NODE_CNT=$(microk8s kubectl get nodes --no-headers | grep -cw ' Ready ')
  REP_CNT=$(( NODE_CNT < 3 ? NODE_CNT : 2 ))     # 1→1, 2→2, ≥3→2
  info "Setting defaultReplicaCount=${REP_CNT} (Ready nodes: ${NODE_CNT})"

  LH_VALUES="--set csi.kubeletRootDir=/var/snap/microk8s/common/var/lib/kubelet \
             --set-string defaultSettings.defaultReplicaCount=${REP_CNT} \
             --set storageClass.allowVolumeExpansion=true \
             --set defaultSettings.guaranteedInstanceManagerCPU=12 \
             --set longhornManager.resources.limits.memory=1000Mi \
             --set longhornManager.resources.requests.memory=256Mi"

  if microk8s helm3 list -n longhorn-system | grep -iq '^longhorn'; then
    info "Longhorn already present: performing upgrade"

    run_cmd "microk8s kubectl -n longhorn-system delete job longhorn-pre-upgrade \
             --ignore-not-found=true" "Cleaning up pre-upgrade job"

    if ! run_cmd "microk8s helm3 upgrade longhorn longhorn/longhorn \
                  --namespace longhorn-system ${LH_VALUES}" "Upgrading Longhorn"; then
      warn "Longhorn upgrade failed, proceeding with reinstallation..."

      run_cmd "microk8s helm3 uninstall longhorn -n longhorn-system || true" \
              "Uninstalling Longhorn"
      run_cmd "microk8s kubectl delete namespace longhorn-system \
              --ignore-not-found=true" "Removing namespace"

      info "Waiting for complete cleanup (30s)..."; sleep 30

      run_cmd "microk8s helm3 install longhorn longhorn/longhorn \
               --namespace longhorn-system --create-namespace ${LH_VALUES}" \
               "Reinstalling Longhorn"
    fi
    ok "Longhorn updated"
  else
    info "Longhorn not found: installing"

    run_cmd "microk8s helm3 install longhorn longhorn/longhorn \
             --namespace longhorn-system --create-namespace --version 1.12.1 ${LH_VALUES}" \
             "Installing Longhorn"
    ok "Longhorn installed"
  fi
  # endregion 27.5) Longhorn installation / upgrade

  # region 27.6) Patch longhorn-driver-deployer to add --kubelet-root-dir
  DRIVER_NS="longhorn-system"
  info "Patching longhorn-driver-deployer for MicroK8s..."

  # Wait for pods to be created
  info "Waiting for Longhorn pod creation (30s)..."
  sleep 30

  # Verify deployment exists
  if ! microk8s kubectl -n $DRIVER_NS get deployment longhorn-driver-deployer >/dev/null 2>&1; then
    warn "Deployment longhorn-driver-deployer not found, waiting more..."
    sleep 30
  fi

  # Patch deployment with kubelet-root-dir parameter
  if microk8s kubectl -n $DRIVER_NS get deployment longhorn-driver-deployer >/dev/null 2>&1; then
    info "Applying kubelet-root-dir patch to driver-deployer..."
    
    # Check if patch is already present
    if microk8s kubectl -n $DRIVER_NS get deployment longhorn-driver-deployer -o yaml | grep -q "/var/snap/microk8s/common/var/lib/kubelet"; then
      ok "kubelet-root-dir patch already applied"
    else
      # Apply JSON patch
      if run_cmd "microk8s kubectl -n $DRIVER_NS patch deployment longhorn-driver-deployer --type=json -p '[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-root-dir\"},{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"/var/snap/microk8s/common/var/lib/kubelet\"}]'" "Patch driver-deployer"; then
        ok "kubelet-root-dir patch applied successfully"
      else
        warn "Patch failed, but continuing - may already be present"
      fi
    fi
  else
    warn "Deployment longhorn-driver-deployer not found, continuing without patch"
  fi
  # endregion 27.6) Patch longhorn-driver-deployer to add --kubelet-root-dir

  # region 27.7) Waiting for Longhorn stabilization
  info "Waiting for Longhorn stabilization..."

  # region 27.7.1) Timeout per sistemi non-Jetson
  TIMEOUT_ROLLOUT=600  # 10 minuti
  TIMEOUT_PODS=900     # 15 minuti
  # endregion 27.7.1) Timeout per sistemi non-Jetson

  # region 27.7.2) Wait for driver-deployer rollout
  info "Waiting for driver-deployer rollout (max ${TIMEOUT_ROLLOUT}s)..."
  if ! microk8s kubectl -n $DRIVER_NS rollout status deployment/longhorn-driver-deployer --timeout=${TIMEOUT_ROLLOUT}s; then
    warn "driver-deployer rollout timeout, but continuing"
  fi
  # endregion 27.7.2) Wait for driver-deployer rollout

  # region 27.7.3) Wait for manager rollout if exists
  info "Checking longhorn-manager daemonset existence..."
  if microk8s kubectl -n $DRIVER_NS get daemonset longhorn-manager >/dev/null 2>&1; then
    info "Waiting for longhorn-manager rollout (max ${TIMEOUT_ROLLOUT}s)..."
    if ! microk8s kubectl -n $DRIVER_NS rollout status daemonset/longhorn-manager --timeout=${TIMEOUT_ROLLOUT}s; then
      warn "longhorn-manager rollout timeout, but continuing"
    fi
  else
    warn "DaemonSet longhorn-manager not found, may still be creating"
  fi
  # endregion 27.7.3) Wait for manager rollout if exists

  # region 27.7.4) Wait for CRDs
  info "Waiting for Longhorn CRDs (max ${TIMEOUT_PODS}s)..."
  if ! microk8s kubectl wait --for=condition=Established crd engines.longhorn.io --timeout=${TIMEOUT_PODS}s; then
    warn "Longhorn CRDs not ready within timeout, but continuing"
  fi
  # endregion 27.7.4) Wait for CRDs

  # region 27.7.5) Verify pods Ready with more tolerance
  info "Waiting for Longhorn pods to be Ready (max 300s)..."
  
  # Show current pod status before waiting
  info "Current Longhorn pod status:"
  run_cmd "microk8s kubectl -n $DRIVER_NS get pods -o wide" "Current pod status" || true
  
  # Wait with shorter timeout and better feedback
  if ! timeout 300 bash -c "
    while true; do
      ready_pods=\$(microk8s kubectl -n $DRIVER_NS get pods --no-headers 2>/dev/null | awk '\$2 ~ /^[0-9]+\/[0-9]+\$/ && \$3 == \"Running\" {split(\$2, a, \"/\"); if (a[1] == a[2]) ready++} END {print ready+0}')
      total_pods=\$(microk8s kubectl -n $DRIVER_NS get pods --no-headers 2>/dev/null | wc -l)
      
      echo \"Ready pods: \$ready_pods/\$total_pods\"
      
      if [ \"\$ready_pods\" -eq \"\$total_pods\" ] && [ \"\$total_pods\" -gt 0 ]; then
        echo \"All pods ready!\"
        exit 0
      fi
      
      sleep 10
    done
  "; then
    warn "Not all Longhorn pods are Ready within timeout"
    
    # Show detailed status of problematic pods
    info "Checking pod status details:"
    run_cmd "microk8s kubectl -n $DRIVER_NS get pods -o wide" "Pod status" || true
    run_cmd "microk8s kubectl -n $DRIVER_NS describe pods | grep -A 10 -B 5 'Warning\\|Error\\|Failed'" "Pod issues" || true
    
    # Check how many pods are actually running
    RUNNING_PODS=$(microk8s kubectl -n $DRIVER_NS get pods --field-selector=status.phase=Running 2>/dev/null | wc -l || echo "0")
    TOTAL_PODS=$(microk8s kubectl -n $DRIVER_NS get pods 2>/dev/null | wc -l || echo "0")
    
    if [ "$RUNNING_PODS" -gt 1 ]; then
      ok "Longhorn partially operational ($RUNNING_PODS/$TOTAL_PODS pods Running)"
    else
      warn "Longhorn may have issues - few pods Running"
    fi
  else
    ok "All Longhorn pods are Ready!"
  fi
  # endregion 27.7.5) Verify pods Ready with more tolerance

  # region 27.7.6) Test Longhorn functionality with PVC
  info "Testing Longhorn functionality..."
  if microk8s kubectl get sc longhorn >/dev/null 2>&1; then
    ok "StorageClass longhorn available"
    
    # Quick PVC test
    if run_cmd "microk8s kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: longhorn-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 1Gi
EOF" "Test PVC Longhorn"; then
      
      # Wait for PVC binding with improved diagnostics
      info "Waiting for PVC binding (max 120s)..."

      # ── modern method: kubectl wait + jsonpath (>=1.27) ────────────────
      if microk8s kubectl wait \
            --for=jsonpath='{.status.phase}=Bound' \
            --timeout=120s pvc/longhorn-test-pvc 2>/dev/null; then
        ok "Longhorn works correctly!"
        run_cmd "microk8s kubectl delete pvc longhorn-test-pvc" "Cleanup test PVC"
      else
        # ── fallback for older kubectl ───────────────────────────────
        BOUND=false
        for i in {1..24}; do
          PHASE=$(microk8s kubectl get pvc longhorn-test-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
          if [ "$PHASE" = "Bound" ]; then
            ok "Longhorn works correctly! PVC Bound in $((i*5)) s"
            BOUND=true
            break
          fi
          sleep 5
        done

        if ! $BOUND; then
          warn "Test PVC not Bound within timeout"
          info "Checking PVC and volume status..."
          run_cmd "microk8s kubectl get pvc longhorn-test-pvc -o wide" "PVC status" || true
          run_cmd "microk8s kubectl get pv" "Persistent volumes" || true
          run_cmd "microk8s kubectl -n longhorn-system get pods | grep -E '(engine|replica)'" "Longhorn engine/replica pods" || true
          warn "Longhorn installed but may have configuration issues"
          run_cmd "microk8s kubectl delete pvc longhorn-test-pvc --ignore-not-found=true" "Cleanup test PVC"
        else
          run_cmd "microk8s kubectl delete pvc longhorn-test-pvc" "Cleanup test PVC"
        fi
      fi
    fi
  else
    warn "StorageClass longhorn not found - Longhorn may have issues"
  fi
  # endregion 27.7.6) Test Longhorn functionality with PVC

  ok "Longhorn installation completed!"
  # endregion 27.7) Waiting for Longhorn stabilization

else
  # On Jetson we use only microk8s-hostpath as storage
  info "Jetson system detected: skipping Longhorn installation, using microk8s-hostpath"
  
  # Ensure microk8s-hostpath is configured as default
  if microk8s kubectl get sc microk8s-hostpath >/dev/null 2>&1; then
    info "Configuring microk8s-hostpath as default storage class for Jetson..."
    run_cmd "microk8s kubectl patch sc microk8s-hostpath -p '{\"metadata\": {\"annotations\": {\"storageclass.kubernetes.io/is-default-class\":\"true\"}}}}'" "Setting microk8s-hostpath as default"
    ok "microk8s-hostpath configured as default storage class for Jetson"
  else
    warn "Storage class microk8s-hostpath not found"
  fi
fi

# region 27.8) Final storage verification
info "Verifying final storage configuration..."

# If we're not on Jetson and have installed Longhorn, remove the default flag from microk8s-hostpath
if ! $IS_JETSON; then
  info "Verifying storage configuration with Longhorn as default..."
  if microk8s kubectl get sc microk8s-hostpath >/dev/null 2>&1; then
    info "Removing default flag from microk8s-hostpath to leave only Longhorn as default..."
    run_cmd "microk8s kubectl patch sc microk8s-hostpath -p '{\"metadata\": {\"annotations\": {\"storageclass.kubernetes.io/is-default-class\":\"false\"}}}}'" "Removing default flag from microk8s-hostpath"
    ok "microk8s-hostpath is no longer default - only Longhorn remains default"
  else
    warn "Storage class microk8s-hostpath not found"
  fi
fi

run_cmd "microk8s kubectl get sc" "List storage classes"

# Show which is the default
DEFAULT_SC=$(microk8s kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "none")
if $IS_JETSON; then
  if [ "$DEFAULT_SC" = "microk8s-hostpath" ]; then
    ok "Default storage class for Jetson: $DEFAULT_SC ✓"
  else
    warn "Default storage class: $DEFAULT_SC (expected for Jetson: microk8s-hostpath)"
  fi
else
  if [ "$DEFAULT_SC" = "longhorn" ]; then
    ok "Default storage class: $DEFAULT_SC ✓"
  else
    warn "Default storage class: $DEFAULT_SC (expected: longhorn)"
  fi
fi
# endregion 27.8) Final storage verification
#endregion 27) Longhorn installation with extended diagnostics
