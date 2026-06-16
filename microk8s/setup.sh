#!/usr/bin/env bash
#─────────────────────────────────────────────────────────────────────────────
# setup_microk8s.sh – Resilient MicroK8s Bootstrap (Ubuntu 24.04)
# Usage: sudo ./setup_microk8s.sh [-v|--verbose]
#─────────────────────────────────────────────────────────────────────────────

# Set the base directory of the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Initialize INTERACTIVE variable early
INTERACTIVE=false; [ -t 0 ] && INTERACTIVE=true
export INTERACTIVE

# Sourcing modules
source "$LIB_DIR/preflight.sh" #step 0-2
source "$LIB_DIR/initial_setup.sh" #step 3-6
source "$LIB_DIR/platform_detection.sh" #step 7
source "$LIB_DIR/logging.sh" #step 8
source "$LIB_DIR/helpers.sh" #step 9
source "$LIB_DIR/node_type_detection.sh" #step 2.5

# Conditional execution based on node type
if [[ "$IS_PRIMARY_NODE" == "true" ]]; then
    info "🏗️  PRIMARY NODE: Full installation with all components"
    
    # Velero configuration (only on primary node)
    source "$LIB_DIR/microk8s_velero.sh" #step 9.5 - Velero configuration and installation
    ask_velero_settings # Ask Velero settings early (before installation steps)
    
    source "$LIB_DIR/network.sh" #step 10
    source "$LIB_DIR/hostname_setup.sh" #step 10.5 (hostname configuration)
    source "$LIB_DIR/microk8s_metallb_config.sh" #step 11-14
    source "$LIB_DIR/system_setup.sh" #step 15-17
    source "$LIB_DIR/helm_os_install.sh" #step 17.5
    source "$LIB_DIR/microk8s_install.sh" #step 18-20.5
    source "$LIB_DIR/microk8s_addon_core.sh" #step 21
    source "$LIB_DIR/microk8s_flannel.sh" #step 22
    source "$LIB_DIR/microk8s_certmanager.sh" #step 23
    source "$LIB_DIR/microk8s_hostpath.sh" #step 24
    source "$LIB_DIR/jetson_multi_disk.sh" #step 24.5
    source "$LIB_DIR/microk8s_gpu.sh" #step 25
    source "$LIB_DIR/microk8s_metallb_setup.sh" #step 26
    source "$LIB_DIR/microk8s_longhorn.sh" #step 27
    source "$LIB_DIR/longhorn_multi_disk.sh" #step 27.5
    source "$LIB_DIR/longhorn_optimize_storage.sh" #step 27.6
    source "$LIB_DIR/microk8s_addon_community.sh" #step 28
    
    # Install Velero (if enabled) - only on primary node
    info "📦 Install Velero: invoking installer (step 28.5)"
    install_velero #step 28.5
    
    source "$LIB_DIR/setup_check.sh" #step 29-33
    source "$LIB_DIR/jetson_alias.sh" #step 33.5
elif [[ "$IS_SECONDARY_NODE" == "true" ]]; then
    info "🔗 SECONDARY NODE: Installation for cluster join with storage support"
    source "$LIB_DIR/hostname_setup.sh" #step 10.5 (hostname configuration for secondary nodes)
    source "$LIB_DIR/system_setup.sh" #step 15-17 (basic system setup)
    source "$LIB_DIR/microk8s_install.sh" #step 18-20.5 (modified for join)
    source "$LIB_DIR/jetson_multi_disk.sh" #step 24.5 (Jetson disk detection for secondary nodes)
    source "$LIB_DIR/microk8s_longhorn.sh" #step 27 (Longhorn installation for distributed storage)
    source "$LIB_DIR/longhorn_multi_disk.sh" #step 27.5 (disk detection and configuration for secondary nodes)
    source "$LIB_DIR/longhorn_optimize_storage.sh" #step 27.6 (optimize storage reservation for system disk)
    source "$LIB_DIR/setup_check.sh" #step 29-33 (modified for secondary)
    source "$LIB_DIR/jetson_alias.sh" #step 33.5
else
    # Default to single-node setup (backward compatibility)
    info "🏗️  SINGLE NODE: Full installation (backward compatibility mode)"
    
    # Velero configuration (single-node mode)
    source "$LIB_DIR/microk8s_velero.sh" #step 9.5 - Velero configuration and installation
    ask_velero_settings # Ask Velero settings early (before installation steps)
    
    source "$LIB_DIR/network.sh" #step 10
    source "$LIB_DIR/microk8s_metallb_config.sh" #step 11-14
    source "$LIB_DIR/system_setup.sh" #step 15-17
    source "$LIB_DIR/helm_os_install.sh" #step 17.5
    source "$LIB_DIR/microk8s_install.sh" #step 18-20.5
    source "$LIB_DIR/microk8s_addon_core.sh" #step 21
    source "$LIB_DIR/microk8s_flannel.sh" #step 22
    source "$LIB_DIR/microk8s_certmanager.sh" #step 23
    source "$LIB_DIR/microk8s_hostpath.sh" #step 24
    source "$LIB_DIR/microk8s_gpu.sh" #step 25
    source "$LIB_DIR/microk8s_metallb_setup.sh" #step 26
    source "$LIB_DIR/microk8s_longhorn.sh" #step 27
    source "$LIB_DIR/longhorn_multi_disk.sh" #step 27.5
    source "$LIB_DIR/longhorn_optimize_storage.sh" #step 27.6
    source "$LIB_DIR/microk8s_addon_community.sh" #step 28
    
    # Install Velero (if enabled) - single-node mode
    info "📦 Install Velero: invoking installer (step 28.5)"
    install_velero #step 28.5
    
    source "$LIB_DIR/setup_check.sh" #step 29-33
    source "$LIB_DIR/jetson_alias.sh" #step 33.5
fi

# Final message
info "Installation completed successfully!"
ok "MicroK8s is ready to be used."