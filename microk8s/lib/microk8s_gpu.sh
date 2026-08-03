#!/usr/bin/env bash

# region 25) GPU enablement
info "=== GPU CONFIGURATION ==="

# ARCH=$(uname -m) - old
ARCH=$(dpkg --print-architecture)
# IS_JETSON is already defined in section 7
# Make sure IS_JETSON is always defined
IS_JETSON=${IS_JETSON:-false}
HAS_PCI_GPU=false

# --- GPU type detection ---------------------------------------------------
# Multi-method GPU detection for maximum reliability
GPU_DETECTED=false
HAS_WORKING_NVIDIA=false
GPU_DETECTION_METHOD=""

info "Starting comprehensive GPU detection..."

# Method 1: Check for working NVIDIA drivers first (most reliable if present)
if command -v nvidia-smi >/dev/null 2>&1; then
  debug "nvidia-smi found, testing functionality..."
  if nvidia-smi >/dev/null 2>&1; then
    GPU_DETECTED=true
    HAS_WORKING_NVIDIA=true
    HAS_PCI_GPU=true  # If nvidia-smi works, we definitely have a usable GPU
    GPU_DETECTION_METHOD="nvidia-smi"
    ok "NVIDIA GPU detected via working nvidia-smi"
    
    # Get GPU details
    GPU_COUNT=$(nvidia-smi --query-gpu=count --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "1")
    GPU_INFO=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | tr '\n' ', ' | sed 's/, $//' || echo "Unknown NVIDIA GPU")
    debug "Working NVIDIA GPUs: $GPU_COUNT - $GPU_INFO"
  else
    debug "nvidia-smi found but not working (driver issues)"
  fi
fi

# Method 2: Check for NVIDIA GPU hardware via lspci (if nvidia-smi not working)
if ! $GPU_DETECTED && ! $IS_JETSON; then
  debug "Checking for NVIDIA GPU hardware via lspci..."
  if command -v lspci >/dev/null 2>&1; then
    if lspci -nnk 2>/dev/null | grep -qi 'nvidia'; then
      GPU_DETECTED=true
      HAS_PCI_GPU=true
      GPU_DETECTION_METHOD="lspci"
      ok "NVIDIA GPU hardware detected via lspci (drivers may need installation)"
      
      # Get GPU details from lspci
      GPU_INFO=$(lspci | grep -Ei 'vga|3d|display' | grep -i nvidia | head -1 | sed 's/.*: //' || echo "Unknown NVIDIA GPU")
      debug "PCI GPU hardware: $GPU_INFO"
    else
      debug "No NVIDIA GPU found via lspci"
    fi
  else
    debug "lspci command not available"
  fi
fi

# Method 3: Special handling for Jetson systems
if $IS_JETSON; then
  GPU_DETECTED=true
  HAS_PCI_GPU=true  # Treat Jetson as having GPU
  GPU_DETECTION_METHOD="jetson"
  ok "Jetson system detected - Tegra GPU assumed present"
fi

# Summary of detection results
if $GPU_DETECTED; then
  info "GPU Detection Summary:"
  info "  Method: $GPU_DETECTION_METHOD"
  info "  Working NVIDIA drivers: $(if $HAS_WORKING_NVIDIA; then echo "✅ Yes"; else echo "❌ No"; fi)"
  info "  Hardware detected: $(if $HAS_PCI_GPU; then echo "✅ Yes"; else echo "⚠️  Uncertain"; fi)"
  if [ -n "$GPU_INFO" ]; then
    info "  GPU Details: $GPU_INFO"
  fi
else
  debug "No NVIDIA GPU detected through any method"
fi

# --- Case 1: No GPU Hardware ----------------------------------------------------
if ! $IS_JETSON && ! $HAS_PCI_GPU; then
  warn "No NVIDIA GPU detected: skipping GPU configuration"
else
  info "GPU configuration for $(if $IS_JETSON; then echo "Jetson"; else echo "PCIe"; fi)"
  
  # --- Fix expired ROS GPG key (if present) -----------------------------
  if grep -q "packages.ros.org" /etc/apt/sources.list.d/*.list 2>/dev/null; then
    info "Removing ROS repository with expired key..."
    run_cmd "rm -f /etc/apt/sources.list.d/ros*" "Remove ROS repo" || true
  fi
  
  # --- Common runtime packages ----------------------------------------------
  if ! run_cmd "apt-get update" "Update APT repo"; then
    warn "Cannot update APT, continuing anyway"
  fi

  # Install drivers and runtime specific to GPU type and current state
  if $HAS_WORKING_NVIDIA; then
    # --- PATH A: GPU is already working ------------------------------------
    info "NVIDIA GPU already functional, ensuring container toolkit is available..."
    
    # Check if container toolkit is already installed
    if command -v nvidia-container-runtime >/dev/null 2>&1; then
      info "NVIDIA container toolkit already installed and ready"
    else
      info "Installing NVIDIA container toolkit for working GPU..."
      
      # Add NVIDIA repository only if needed
      if [ ! -f "/etc/apt/sources.list.d/nvidia-container-toolkit.list" ]; then
        info "Adding NVIDIA container toolkit repository..."
        
        if ! run_cmd "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg" \
                "Add NVIDIA GPG key"; then
          warn "Cannot add NVIDIA GPG key"
        fi
        
        run_cmd "chmod 644 /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg" "Set GPG key permissions" || true
        
        if run_cmd "curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's|deb https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /|deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/'${ARCH}' /|' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list" \
                "Add nvidia-container-toolkit repository"; then
          run_cmd "apt-get update" "Update repo with NVIDIA" || true
        fi
      fi
      
      # Install only container toolkit
      if ! run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit nvidia-container-runtime" \
              "Install NVIDIA container runtime"; then
        warn "Cannot install NVIDIA container runtime"
      fi
    fi
  elif $HAS_PCI_GPU; then
    # --- PATH B: GPU hardware detected, drivers needed ---------------------
    # Standard PCIe GPU - add NVIDIA repository and install drivers and runtime
    info "Configuring NVIDIA repository for PCIe GPU..."
    if ! run_cmd "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg" \
            "Add NVIDIA GPG key"; then
      warn "Cannot add NVIDIA GPG key"
    fi
    
    # Ensure the key is readable by APT
    if ! run_cmd "chmod 644 /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg" \
            "Set GPG key permissions"; then
      warn "Cannot set GPG key permissions"
    fi
    
    # apt-key is deprecated - we already have the keyring, so skip
    debug "GPG key already configured in keyring /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
    
    # Determine the correct architecture
    if run_cmd "curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's|deb https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /|deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/'${ARCH}' /|' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list" \
            "Add nvidia-container-toolkit repository"; then
      info "NVIDIA repository configured with GPG key for architecture ${ARCH}"
    else
      warn "Cannot add NVIDIA repository, trying manual configuration"
      # Fallback: manually create the repository file
      if ! run_cmd "echo 'deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/${ARCH} /' | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list" \
              "Create NVIDIA repository manually"; then
        warn "Cannot create NVIDIA repository"
      fi
    fi
    
    run_cmd "apt-get update" "Update repo with NVIDIA" || true
    
    info "Installing NVIDIA driver for PCIe GPU..."
    
    # Check if a newer NVIDIA driver already exists
    CURRENT_DRIVER=""
    DRIVER_INSTALLED=false
    DRIVER_MISMATCH=false
    
    if command -v nvidia-smi >/dev/null 2>&1; then
      CURRENT_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>&1 | head -1)
      
      # Check if output contains error messages indicating mismatch
      if echo "$CURRENT_DRIVER" | grep -qi "error\|failed\|mismatch"; then
        warn "NVIDIA driver/library version mismatch detected"
        debug "nvidia-smi output: $CURRENT_DRIVER"
        DRIVER_MISMATCH=true
        
        # Try to fix by reloading kernel modules
        info "Attempting to reload NVIDIA kernel modules..."
        
        # Check if modules are loaded
        if lsmod | grep -q nvidia; then
          info "Unloading NVIDIA modules..."
          modprobe -r nvidia_uvm 2>/dev/null || true
          modprobe -r nvidia_drm 2>/dev/null || true
          modprobe -r nvidia_modeset 2>/dev/null || true
          modprobe -r nvidia 2>/dev/null || true
          sleep 2
        fi
        
        # Try to reload modules
        if modprobe nvidia 2>/dev/null && \
           modprobe nvidia_modeset 2>/dev/null && \
           modprobe nvidia_drm 2>/dev/null && \
           modprobe nvidia_uvm 2>/dev/null; then
          ok "NVIDIA kernel modules reloaded"
          sleep 2
          
          # Test if nvidia-smi works now
          if nvidia-smi >/dev/null 2>&1; then
            CURRENT_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -1)
            if [[ "$CURRENT_DRIVER" =~ ^[0-9]+\.[0-9]+ ]]; then
              ok "NVIDIA driver now functional: version $CURRENT_DRIVER"
              DRIVER_MISMATCH=false
            fi
          fi
        else
          debug "Cannot reload NVIDIA modules - may be in use by other processes"
        fi
        
        # If still mismatch after reload attempt, skip GPU config and continue
        if $DRIVER_MISMATCH; then
          warn "⚠️  Driver/library mismatch persists - modules in use"
          warn "⚠️  GPU configuration requires system reboot"
          warn "⚠️  Please reboot the system: sudo reboot"
          warn "⚠️  Then re-run this setup to complete GPU configuration"
          warn ""
          info "Continuing with non-GPU setup..."
          # Set flag to skip GPU runtime configuration
          GPU_RUNTIME_AVAILABLE=false
        fi
      elif [[ "$CURRENT_DRIVER" =~ ^[0-9]+\.[0-9]+ ]]; then
        # Valid version number detected
        info "NVIDIA driver functional: version $CURRENT_DRIVER"
        DRIVER_VERSION_MAJOR=$(echo "$CURRENT_DRIVER" | cut -d. -f1)
        
        # Check if driver version is compatible (>= 570)
        if [ "$DRIVER_VERSION_MAJOR" -ge 570 ]; then
          info "Driver version $DRIVER_VERSION_MAJOR is compatible (>= 570)"
          
          # Install only container toolkit if not already present
          if ! command -v nvidia-container-runtime >/dev/null 2>&1; then
            info "Installing NVIDIA container toolkit for existing driver..."
            if ! run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit nvidia-container-runtime" \
                    "Install NVIDIA container runtime"; then
              warn "Cannot install NVIDIA container runtime"
            fi
          else
            info "NVIDIA container runtime already present"
          fi
          DRIVER_INSTALLED=true
        else
          info "Driver version $DRIVER_VERSION_MAJOR < 570, upgrade recommended"
          # Will proceed with driver installation below
        fi
      else
        debug "Cannot parse NVIDIA driver version output: $CURRENT_DRIVER"
        CURRENT_DRIVER=""
      fi
    fi
    
    # Install/upgrade driver only if not already compatible and no mismatch detected
    if [ "$DRIVER_INSTALLED" != "true" ] && ! $DRIVER_MISMATCH; then
      info "Installing/upgrading to NVIDIA driver 570..."
      
      if run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-driver-570-server nvidia-container-toolkit nvidia-container-runtime" \
              "Install NVIDIA driver and container runtime"; then
        ok "NVIDIA driver packages installed"
        
        # Test if newly installed driver works immediately
        sleep 2
        if nvidia-smi >/dev/null 2>&1; then
          CURRENT_DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -1)
          if [[ "$CURRENT_DRIVER" =~ ^[0-9]+\.[0-9]+ ]]; then
            ok "NVIDIA driver operational immediately: version $CURRENT_DRIVER"
          else
            warn "Driver installed but not yet operational - reboot recommended"
            warn "⚠️  System reboot required for GPU functionality"
            warn "⚠️  Please reboot: sudo reboot"
            warn "⚠️  Then re-run setup to complete GPU configuration"
            warn ""
            info "Continuing with non-GPU setup..."
            GPU_RUNTIME_AVAILABLE=false
          fi
        else
          warn "Driver installed but requires reboot to load kernel modules"
          warn "⚠️  System reboot required for GPU functionality"
          warn "⚠️  Please reboot: sudo reboot"
          warn "⚠️  Then re-run setup to complete GPU configuration"
          warn ""
          info "Continuing with non-GPU setup..."
          GPU_RUNTIME_AVAILABLE=false
        fi
      else
        warn "Cannot install NVIDIA driver package, trying container runtime only..."
        if ! run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit nvidia-container-runtime" \
                "Install NVIDIA container runtime"; then
          warn "Cannot install NVIDIA container runtime"
          warn "GPU will not work in containers"
        fi
      fi
    fi  # Close: if [ "$DRIVER_INSTALLED" != "true" ] && ! $DRIVER_MISMATCH
  elif $IS_JETSON; then
    # Jetson - use specific repository for nvidia-container-toolkit
    info "Configuring NVIDIA repository for Jetson..."
    distribution=$(. /etc/os-release; echo ${ID}${VERSION_ID})
    if ! run_cmd "curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg" \
            "Add NVIDIA GPG key"; then
      warn "Cannot add NVIDIA GPG key"
    fi
    
    # Ensure the key is readable by APT
    if ! run_cmd "chmod 644 /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg" \
            "Set GPG key permissions"; then
      warn "Cannot set GPG key permissions"
    fi
    
    # apt-key is deprecated - we already have the keyring, so skip
    debug "GPG key already configured in keyring /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
    
    # Fallback for older L4T versions
    if ! curl -fsSL "https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list" >/dev/null 2>&1; then
      warn "Repository for $distribution not found, using ubuntu18.04 fallback"
      distribution="ubuntu18.04"
    fi
    
    if run_cmd "curl -fsSL https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | sed 's|deb https://nvidia.github.io/libnvidia-container/|deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/|' | tee /etc/apt/sources.list.d/libnvidia-container.list" \
            "Add libnvidia-container repository"; then
      info "NVIDIA Jetson repository configured with GPG key"
    else
      warn "Cannot add NVIDIA repository, trying manual configuration"
      # Fallback: manually create repository file
      if ! run_cmd "echo 'deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container /' | tee /etc/apt/sources.list.d/libnvidia-container.list" \
              "Create NVIDIA Jetson repository manually"; then
        warn "Cannot create NVIDIA Jetson repository"
      fi
    fi
    
    run_cmd "apt-get update" "Update repo with NVIDIA" || true
    
    if ! run_cmd "DEBIAN_FRONTEND=noninteractive apt-get install -y nvidia-container-toolkit" \
            "Install NVIDIA container toolkit for Jetson"; then
      warn "Cannot install NVIDIA container toolkit"
      warn "GPU might not work in containers"
    fi
  fi  # End: elif $IS_JETSON
  
  # Verify if at least the runtime is installed
  GPU_RUNTIME_AVAILABLE=false
  if command -v nvidia-container-runtime &>/dev/null || [ -f /usr/bin/nvidia-container-runtime ]; then
    ok "NVIDIA container runtime available"
    GPU_RUNTIME_AVAILABLE=true
  else
    warn "NVIDIA container runtime not available, skipping GPU configuration"
  fi
   
  # Proceed only if NVIDIA runtime is available
  if $GPU_RUNTIME_AVAILABLE; then
     # --- Verify that MicroK8s is in Ready state before proceeding --------
     info "Checking MicroK8s state before modifying containerd..."
    READY_WAIT=0
    READY_MAX_WAIT=120
    while [ $READY_WAIT -lt $READY_MAX_WAIT ]; do
      if microk8s status --wait-ready 2>/dev/null; then
        ok "MicroK8s is in Ready state"
        break
      fi
      READY_WAIT=$((READY_WAIT + 10))
      debug "Waiting for MicroK8s ready... ${READY_WAIT}s/${READY_MAX_WAIT}s"
      sleep 10
    done
    
    if [ $READY_WAIT -ge $READY_MAX_WAIT ]; then
      err "MicroK8s not in Ready state after ${READY_MAX_WAIT}s, skipping GPU configuration"
    else
      # --- Safe containerd patch with validation --------------------------
      CRT_FILE=/var/snap/microk8s/current/args/containerd-template.toml
      CRT_BACKUP="$CRT_FILE.backup.$(date +%s)"
      
      info "Configuring NVIDIA runtime in containerd..."
      
      # Backup with timestamp
      cp "$CRT_FILE" "$CRT_BACKUP"
      debug "Backup saved in $CRT_BACKUP"
      
      # Check if nvidia runtime is already configured correctly
      NEEDS_PATCH=false
      
      # Check if default_runtime_name is already set to nvidia
      if ! grep -q '^\s*default_runtime_name\s*=\s*"nvidia"' "$CRT_FILE"; then
        NEEDS_PATCH=true
        debug "default_runtime_name not set to nvidia"
      fi
      
      # Check if nvidia runtime section exists
      if ! grep -q '\[plugins\."io.containerd.grpc.v1.cri"\.containerd\.runtimes\.nvidia\]' "$CRT_FILE"; then
        NEEDS_PATCH=true
        debug "nvidia runtime section missing"
      fi
      
      if $NEEDS_PATCH; then
        info "Applying containerd config patch..."
        
        # Create temporary file
        TMP_FILE=$(mktemp /tmp/containerd-config.XXXXXX.toml)
        cp "$CRT_FILE" "$TMP_FILE"
        
        # 1. Replace (don't duplicate) default_runtime_name
        # First check if a line with default_runtime_name already exists
        if grep -q '^\s*default_runtime_name\s*=' "$TMP_FILE"; then
          # Replace existing line
          sed -i 's|^\s*default_runtime_name\s*=.*|  default_runtime_name = "nvidia"|' "$TMP_FILE"
          debug "Replaced existing default_runtime_name line"
        else
          # Add after [plugins."io.containerd.grpc.v1.cri".containerd]
          sed -i '/\[plugins\."io.containerd.grpc.v1.cri"\.containerd\]/a\  default_runtime_name = "nvidia"' "$TMP_FILE"
          debug "Added default_runtime_name line"
        fi
        
        # 2. Remove any existing nvidia runtime sections
        # Use awk to remove from nvidia section until next [
        awk '
          BEGIN { skip = 0 }
          /\[plugins\."io.containerd.grpc.v1.cri"\.containerd\.runtimes\.nvidia/ { skip = 1 }
          /^\[/ && skip == 1 && !/\[plugins\."io.containerd.grpc.v1.cri"\.containerd\.runtimes\.nvidia/ { skip = 0 }
          skip == 0 { print }
        ' "$TMP_FILE" > "$TMP_FILE.2"
        mv "$TMP_FILE.2" "$TMP_FILE"
        
        # 3. Add nvidia runtime configuration
        cat >> "$TMP_FILE" << 'EOF'

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
  runtime_type = "io.containerd.runc.v2"
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "/usr/bin/nvidia-container-runtime"
EOF
        
        # 4. Validation using containerd itself
        info "Validating containerd configuration..."
        # Use MicroK8s containerd binary for validation
        CONTAINERD_BIN="/snap/microk8s/current/bin/containerd"
        if [ -x "$CONTAINERD_BIN" ]; then
          if $CONTAINERD_BIN --config "$TMP_FILE" config dump > /dev/null 2>&1; then
            ok "Containerd configuration valid"
            mv "$TMP_FILE" "$CRT_FILE"
          else
            err "Containerd configuration invalid!"
            debug "Validation error: $($CONTAINERD_BIN --config "$TMP_FILE" config dump 2>&1)"
            rm -f "$TMP_FILE"
            warn "GPU configuration cancelled due to validation error"
          fi
        else
          # Fallback: basic validation
          warn "Containerd binary not found, using basic validation"
          if grep -q 'default_runtime_name = "nvidia"' "$TMP_FILE" && \
             grep -q 'BinaryName = "/usr/bin/nvidia-container-runtime"' "$TMP_FILE"; then
            info "Basic validation passed"
            mv "$TMP_FILE" "$CRT_FILE"
          else
            err "Configuration incomplete"
            rm -f "$TMP_FILE"
          fi
        fi
        
        # Only if patch was applied, restart MicroK8s
        if [ ! -f "$TMP_FILE" ]; then  # Temporary file removed = patch applied
          info "Restarting MicroK8s to apply changes..."
          
          # Stop MicroK8s using run_cmd like other scripts
          if ! run_cmd "microk8s stop" "Stop MicroK8s for configuration"; then
            warn "Stop command failed, continuing anyway..."
          fi
          sleep 5
          
          # Start with retry
          START_ATTEMPTS=0
          START_SUCCESS=false
          while [ $START_ATTEMPTS -lt 3 ]; do
            info "Starting MicroK8s (attempt $((START_ATTEMPTS + 1))/3)..."
            
            if run_cmd "microk8s start" "Start MicroK8s with NVIDIA runtime"; then
              START_SUCCESS=true
              break
            fi
            
            START_ATTEMPTS=$((START_ATTEMPTS + 1))
            if [ $START_ATTEMPTS -lt 3 ]; then
              warn "Start failed, retrying in 10s..."
              sleep 10
            fi
          done
          
          if ! $START_SUCCESS; then
            err "Cannot restart MicroK8s after 3 attempts"
            warn "Restoring previous configuration..."
            cp "$CRT_BACKUP" "$CRT_FILE"
            
            # Try to restart with original configuration
            info "Restarting with original configuration..."
            run_cmd "microk8s stop" "Stop MicroK8s" || true
            sleep 5
            if run_cmd "microk8s start" "Start MicroK8s with original config"; then
              warn "MicroK8s restarted with original configuration"
            else
              err "CRITICAL: MicroK8s won't start even with original config!"
            fi
          else
            # Wait for MicroK8s to be fully ready
            info "Waiting for MicroK8s to be fully operational..."
            WAIT_TIME=0
            MAX_WAIT=180  # 3 minutes
            while [ $WAIT_TIME -lt $MAX_WAIT ]; do
              if microk8s status --wait-ready 2>/dev/null; then
                ok "MicroK8s operational with NVIDIA runtime"
                break
              fi
              WAIT_TIME=$((WAIT_TIME + 10))
              debug "Waiting for MicroK8s ready... ${WAIT_TIME}s/${MAX_WAIT}s"
              sleep 10
            done
            
            if [ $WAIT_TIME -ge $MAX_WAIT ]; then
              warn "MicroK8s not fully ready after ${MAX_WAIT}s"
            fi
          fi
        fi
      else
        ok "NVIDIA runtime already configured correctly"
      fi
      
      # --- Verify that at least one node is Ready before proceeding ---------
      info "Checking Kubernetes nodes..."
      NODE_WAIT=0
      NODE_MAX_WAIT=120
      NODE_READY=false
      while [ $NODE_WAIT -lt $NODE_MAX_WAIT ]; do
        if microk8s kubectl get nodes 2>/dev/null | grep -q " Ready "; then
          NODE_READY=true
          ok "Kubernetes node Ready"
          break
        fi
        NODE_WAIT=$((NODE_WAIT + 10))
        debug "Waiting for node Ready... ${NODE_WAIT}s/${NODE_MAX_WAIT}s"
        sleep 10
      done
      
      if ! $NODE_READY; then
        err "No Ready node after ${NODE_MAX_WAIT}s"
        warn "Cannot proceed with GPU device plugin"
      else
        # --- RuntimeClass creation for Kubernetes ---------------------------
        info "Creating RuntimeClass nvidia..."
        cat <<'EOF' | microk8s kubectl apply -f - || warn "Cannot create RuntimeClass"
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: nvidia
handler: nvidia
EOF
          
          # --- Architecture-specific device plugin installation ---------
          # Initialize global addon status variables
          ADDON_ENABLED=false
          ADDON_OPERATIONAL=false
          
                    if $HAS_PCI_GPU && ! $IS_JETSON; then
            # Desktop/server GPU (non-Jetson) - use official addon
            info "Checking MicroK8s GPU addon status for desktop/server GPU..."
            
            if microk8s status | grep -E "nvidia.*enabled|gpu.*enabled" >/dev/null 2>&1; then
              ADDON_ENABLED=true
              info "NVIDIA/GPU addon is enabled"
              
              # Check if the addon is actually operational (device plugin running)
              if microk8s kubectl get pods -n gpu-operator-resources -l app=nvidia-device-plugin-daemonset --field-selector=status.phase=Running 2>/dev/null | grep -q "Running"; then
                ADDON_OPERATIONAL=true
                info "NVIDIA addon is operational (device plugin running)"
              else
                info "NVIDIA addon enabled but not yet operational"
              fi
            fi
            
            if $ADDON_ENABLED && $ADDON_OPERATIONAL; then
info "NVIDIA/GPU addon already fully operational, skipping enablement"
            else
              if $ADDON_ENABLED; then
                info "NVIDIA addon enabled but not operational, waiting for deployment..."
              else
                info "Enabling official MicroK8s GPU addon for desktop/server..."
                # Try nvidia (official name) first, then gpu (deprecated) as fallback
                if run_cmd "microk8s enable nvidia" "NVIDIA addon enablement"; then
                  ok "NVIDIA addon enabled"
                elif run_cmd "microk8s enable gpu" "GPU addon enablement (deprecated)"; then
                  ok "GPU addon enabled (deprecated, use nvidia in future)"
                else
                  warn "GPU addon not available, installing manual device plugin..."
                # Fallback to official NVIDIA device plugin v0.17.2 (multi-arch)
                cat <<'EOF' | microk8s kubectl apply -f - || warn "Cannot install device plugin"
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      priorityClassName: "system-node-critical"
      runtimeClassName: nvidia
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:v0.17.2
        name: nvidia-device-plugin-ctr
        env:
          - name: FAIL_ON_INIT_ERROR
            value: "false"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/snap/microk8s/common/var/lib/kubelet/device-plugins
EOF
                fi  # close: if run_cmd "microk8s enable nvidia"
              fi    # close: if $ADDON_ENABLED (else branch)
            fi      # close: if $ADDON_ENABLED && $ADDON_OPERATIONAL
          elif $IS_JETSON; then
            # Jetson GPU - skip official addon, use direct device plugin deployment
            info "GPU configuration for Jetson"
            info "Checking MicroK8s GPU addon status..."
            
            # Check if addon is already enabled (shouldn't be, but check anyway)
            if microk8s status | grep -E "nvidia.*enabled|gpu.*enabled" >/dev/null 2>&1; then
              warn "Official GPU addon enabled on Jetson - this often doesn't work properly"
              warn "Consider disabling it: microk8s disable nvidia"
            fi
            
            info "Enabling official MicroK8s GPU addon..."
            # Try to enable addon first (it might work on some Jetson configurations)
            if run_cmd "microk8s enable nvidia" "NVIDIA addon enablement"; then
              ok "NVIDIA addon enabled"
              ADDON_ENABLED=true
            elif run_cmd "microk8s enable gpu" "GPU addon enablement (deprecated)"; then
              ok "GPU addon enabled (deprecated)"
              ADDON_ENABLED=true
            else
              warn "GPU addon not available on this Jetson, will use manual device plugin..."
              ADDON_ENABLED=false
            fi
            
            # ALWAYS deploy manual device plugin for Jetson (regardless of addon status)
            info "Deploying optimized device plugin for Jetson..."
            cat <<'EOF' | microk8s kubectl apply -f - || warn "Cannot install Jetson device plugin"
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      priorityClassName: "system-node-critical"
      runtimeClassName: nvidia
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - image: nvcr.io/nvidia/k8s-device-plugin:v0.17.2
        name: nvidia-device-plugin-ctr
        env:
          - name: PASS_DEVICE_SPECS
            value: "true"
          - name: FAIL_ON_INIT_ERROR
            value: "false"
        securityContext:
          privileged: true
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
        - name: dev
          mountPath: /dev
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/snap/microk8s/common/var/lib/kubelet/device-plugins
      - name: dev
        hostPath:
          path: /dev
EOF
          fi
          

          # Wait for device plugin to be ready
          info "Waiting for device plugin to be operational..."
          
          # Jetson-specific configuration
          if $IS_JETSON; then
            # On Jetson, always use kube-system and shorter timeouts
            PLUGIN_NS="kube-system"
            PLUGIN_LABEL="name=nvidia-device-plugin-ds"
            PLUGIN_MAX_WAIT=300  # Increased timeout for Jetson (image download can be slow)
            
            # Skip long wait for addon on Jetson - manual device plugin should be quick
            if ! $ADDON_OPERATIONAL; then
              info "Jetson detected - starting device plugin monitoring immediately..."
            fi
          else
            # Desktop/server configuration
            PLUGIN_MAX_WAIT=180  # Longer timeout for desktop/server
            PLUGIN_NS="gpu-operator-resources"
            PLUGIN_LABEL="app=nvidia-device-plugin-daemonset"
            
            # If addon was just enabled, give it extra time for initial setup
            if ! $ADDON_OPERATIONAL; then
              info "Addon just enabled, allowing extra time for initial deployment (60s)..."
              sleep 60
              info "Initial grace period complete, starting device plugin monitoring..."
            fi
            
            # Fallback to kube-system if gpu-operator-resources doesn't exist
            if ! microk8s kubectl get namespace "$PLUGIN_NS" >/dev/null 2>&1; then
              PLUGIN_NS="kube-system"
              PLUGIN_LABEL="name=nvidia-device-plugin-ds"
              debug "Namespace gpu-operator-resources not found, using kube-system"
            fi
          fi
          
          PLUGIN_WAIT=0
          
          # Check if device plugin is already running (optimized for existing setups)
          if microk8s kubectl get pods -n "$PLUGIN_NS" -l "$PLUGIN_LABEL" --field-selector=status.phase=Running 2>/dev/null | grep -q "Running"; then
            info "Device plugin already running, verifying GPU registration..."
            # Give kubelet a moment to register the GPU if just started
            sleep 5
            GPU_COUNT=$(microk8s kubectl get node $(hostname) -o jsonpath="{.status.capacity['nvidia\.com/gpu']}" 2>/dev/null)
            if [[ -n "$GPU_COUNT" && "$GPU_COUNT" -gt 0 ]]; then
              ok "GPU already available in cluster: $GPU_COUNT GPU"
              # Skip the waiting loop, everything is ready
              PLUGIN_WAIT=$PLUGIN_MAX_WAIT
            else
              warn "Device plugin running but GPU not yet registered, continuing monitoring..."
            fi
          else
            # For fresh installations, start monitoring for namespace creation first
            if ! $ADDON_OPERATIONAL; then
              info "Fresh installation detected, monitoring namespace and pod creation..."
              # Wait for namespace to be created
              NS_WAIT=0
              while [ $NS_WAIT -lt 60 ] && ! microk8s kubectl get namespace "$PLUGIN_NS" >/dev/null 2>&1; do
                debug "Waiting for namespace $PLUGIN_NS to be created... ${NS_WAIT}s/60s"
                sleep 5
                NS_WAIT=$((NS_WAIT + 5))
              done
              
              if microk8s kubectl get namespace "$PLUGIN_NS" >/dev/null 2>&1; then
                info "Namespace $PLUGIN_NS created"
              else
                warn "Namespace $PLUGIN_NS not created yet, using fallback"
                PLUGIN_NS="kube-system"
                PLUGIN_LABEL="name=nvidia-device-plugin-ds"
              fi
            fi
          fi
          
          while [ $PLUGIN_WAIT -lt $PLUGIN_MAX_WAIT ]; do
            # Check if plugin is running
            if microk8s kubectl get pods -n "$PLUGIN_NS" -l "$PLUGIN_LABEL" --field-selector=status.phase=Running 2>/dev/null | grep -q "Running"; then
              ok "GPU device plugin operational in namespace $PLUGIN_NS"
              break
            fi
            
            # Progressive monitoring - show pod creation and image pull status
            if [ $((PLUGIN_WAIT % 30)) -eq 0 ] && [ $PLUGIN_WAIT -gt 0 ]; then
              debug "Progressive monitoring (${PLUGIN_WAIT}s/${PLUGIN_MAX_WAIT}s)..."
              
              # Check if pods exist (even if not running)
              POD_COUNT=$(microk8s kubectl get pods -n "$PLUGIN_NS" -l "$PLUGIN_LABEL" 2>/dev/null | grep -v "NAME" | wc -l 2>/dev/null | tr -d '\n' || echo "0")
              # Remove any whitespace and ensure POD_COUNT is a valid single number
              POD_COUNT=$(echo "$POD_COUNT" | tr -d ' \t\n\r' | head -c 10)
              if ! [[ "$POD_COUNT" =~ ^[0-9]+$ ]] || [ -z "$POD_COUNT" ]; then
                POD_COUNT=0
              fi
              if [ "$POD_COUNT" -gt 0 ]; then
                # Pods exist, check their status
                POD_STATUS=$(microk8s kubectl get pods -n "$PLUGIN_NS" -l "$PLUGIN_LABEL" -o jsonpath="{.items[0].status.phase}" 2>/dev/null || echo "Unknown")
                POD_NAME=$(microk8s kubectl get pods -n "$PLUGIN_NS" -l "$PLUGIN_LABEL" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "unknown-pod")
                
                case "$POD_STATUS" in
                  "Pending")
                    info "Device plugin pod '$POD_NAME' created, checking containers..."
                    # Check if it's waiting for image pull
                    if microk8s kubectl describe pod -n "$PLUGIN_NS" "$POD_NAME" 2>/dev/null | grep -q "Pulling\|ErrImagePull\|ImagePullBackOff"; then
                      if $IS_JETSON; then
                        info "📥 Downloading NVIDIA device plugin image on Jetson (can take 3-5 minutes)..."
                      else
                        info "Still downloading NVIDIA device plugin image..."
                      fi
                    else
                      info "Pod pending for other reasons, checking events..."
                    fi
                    ;;
                  "ContainerCreating")
                    if $IS_JETSON; then
                      info "📥 NVIDIA device plugin container creating on Jetson (image download in progress)..."
                    else
                      info "Device plugin container creating..."
                    fi
                    ;;
                  "Running")
                    info "Device plugin pod is running but not ready yet"
                    ;;
                  *)
                    warn "Device plugin pod in unexpected state: $POD_STATUS"
                    ;;
                esac
              else
                # No pods yet, check if DaemonSet exists
                if microk8s kubectl get daemonset -n "$PLUGIN_NS" 2>/dev/null | grep -q "nvidia"; then
                  info "NVIDIA DaemonSet exists, waiting for pod creation..."
                else
                  if $IS_JETSON; then
                    info "Waiting for manual NVIDIA DaemonSet to be created..."
                  else
                    info "Waiting for NVIDIA DaemonSet to be created..."
                  fi
                fi
              fi
              
              # Also check for device plugin in any namespace
              if microk8s kubectl get pods --all-namespaces 2>/dev/null | grep -i "nvidia.*device.*plugin\|device.*plugin.*nvidia" | grep -q "Running"; then
                warn "Found NVIDIA device plugin running in different location"
                run_cmd "microk8s kubectl get pods --all-namespaces | grep -i nvidia" "Current NVIDIA pods" || true
              fi
            fi
            
            PLUGIN_WAIT=$((PLUGIN_WAIT + 10))
            debug "Waiting for device plugin... ${PLUGIN_WAIT}s/${PLUGIN_MAX_WAIT}s"
            sleep 10
          done
          
          if [ $PLUGIN_WAIT -ge $PLUGIN_MAX_WAIT ]; then
            warn "Device plugin not ready after ${PLUGIN_MAX_WAIT}s"
            
            # Comprehensive diagnostic information
            warn "Troubleshooting device plugin issue..."
            echo "============================================================================"
            
            # 1. Check all GPU-related pods in both namespaces
            echo "All GPU-related pods in cluster:"
            microk8s kubectl get pods --all-namespaces 2>/dev/null | grep -i gpu || echo "   No GPU pods found"
            echo ""
            echo "All NVIDIA-related pods in cluster:"
            microk8s kubectl get pods --all-namespaces 2>/dev/null | grep -i nvidia || echo "   No NVIDIA pods found"
            echo ""
            
            # 2. Detailed pod status in target namespace
            echo "Detailed pod status in namespace '$PLUGIN_NS':"
            if microk8s kubectl get namespace "$PLUGIN_NS" >/dev/null 2>&1; then
              microk8s kubectl get pods -n "$PLUGIN_NS" -l "$PLUGIN_LABEL" -o wide 2>/dev/null || echo "   No pods with label '$PLUGIN_LABEL' found"
            else
              echo "   Namespace '$PLUGIN_NS' does not exist"
            fi
            echo ""
            
            # 3. Pod descriptions and events
            echo "Pod descriptions and events:"
            PLUGIN_POD=$(microk8s kubectl get pods -n "$PLUGIN_NS" -l "$PLUGIN_LABEL" -o jsonpath="{.items[0].metadata.name}" 2>/dev/null || echo "")
            if [[ -n "$PLUGIN_POD" ]]; then
              echo "   Pod found: $PLUGIN_POD"
              microk8s kubectl describe pod -n "$PLUGIN_NS" "$PLUGIN_POD" 2>/dev/null | tail -20
            else
              echo "   No device plugin pods found for description"
            fi
            echo ""
            
            # 4. Pod logs if they exist
            echo "Device plugin logs:"
            if [[ -n "$PLUGIN_POD" ]]; then
              microk8s kubectl logs -n "$PLUGIN_NS" "$PLUGIN_POD" --tail=20 2>/dev/null || echo "   Cannot retrieve logs for $PLUGIN_POD"
            else
              echo "   No device plugin pods found for logs"
            fi
            echo ""
            
            # 5. Check DaemonSet status
            echo "NVIDIA DaemonSets status:"
            microk8s kubectl get daemonsets --all-namespaces 2>/dev/null | grep -i nvidia || echo "   No NVIDIA DaemonSets found"
            echo ""
            
            # 6. Node status and GPU visibility
            echo "Node GPU capacity and allocatable:"
            NODE_NAME=$(hostname)
            echo "   Node: $NODE_NAME"
            microk8s kubectl get node "$NODE_NAME" -o jsonpath="{.status.capacity}" 2>/dev/null | grep -o '"nvidia[^"]*"[^,}]*' || echo "   No NVIDIA capacity found"
            echo ""
            
            # 7. RuntimeClass status
            echo "RuntimeClass status:"
            microk8s kubectl get runtimeclass 2>/dev/null || echo "   No RuntimeClasses found"
            echo ""
            
            # 8. System verification
            echo "System NVIDIA verification:"
            if command -v nvidia-smi >/dev/null 2>&1; then
              echo "   nvidia-smi:"
              nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null || echo "   nvidia-smi failed"
            else
              echo "   nvidia-smi not found"
            fi
            
            if command -v nvidia-container-runtime >/dev/null 2>&1; then
              echo "   nvidia-container-runtime:"
              nvidia-container-runtime --version 2>/dev/null || echo "   nvidia-container-runtime failed"
            else
              echo "   nvidia-container-runtime not found"
            fi
            echo "============================================================================"
            
            warn "💡 Common solutions:"
            warn "   1. Check if NVIDIA drivers are properly loaded: sudo nvidia-smi"
            warn "   2. Verify container runtime: sudo nvidia-container-runtime --version"
            warn "   3. Check containerd config: sudo microk8s stop && sudo microk8s start"
            warn "   4. Manual addon restart: microk8s disable nvidia && microk8s enable nvidia"
          fi
          
          # Final GPU verification
          info "Final GPU availability verification..."
          sleep 10  # Give kubelet time to update capacity
          
          # Use a more robust jsonpath query instead of parsing `describe` output
          GPU_COUNT=$(microk8s kubectl get node $(hostname) -o jsonpath="{.status.capacity['nvidia\.com/gpu']}" 2>/dev/null)
          
          if [[ -n "$GPU_COUNT" && "$GPU_COUNT" -gt 0 ]]; then
            ok "GPU available in cluster: $GPU_COUNT GPU"
          else
            warn "GPU not yet visible in node"
            debug "   This can happen if the device plugin is not running correctly."
            debug "   Final check output for 'nvidia.com/gpu': '$GPU_COUNT'"
          fi
        fi
      fi
    fi
  fi  # End GPU_RUNTIME_AVAILABLE block
# TODO: MISSING fi BLOCKS HERE
# endregion 25) GPU enablement
