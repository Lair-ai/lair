#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Global variables
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LIB_DIR="$SCRIPT_DIR/lib"

# Creating necessary directories
mkdir -p "$LIB_DIR"

# Sourcing libraries
source "$LIB_DIR/logging.sh"
source "$LIB_DIR/helpers.sh"
source "$LIB_DIR/k8s_velero.sh"
source "$LIB_DIR/preflight.sh"
source "$LIB_DIR/system_setup.sh"
source "$LIB_DIR/helm_os_install.sh"
source "$LIB_DIR/component_install.sh"
source "$LIB_DIR/longhorn_optimize_storage.sh"

# Main function
main() {
    info "Starting K8s Managed setup script..."

    # Ask Velero settings early
    ask_velero_settings

    run_preflight_checks
    run_system_setup
    run_component_install

    ok "Setup completed successfully!"
}

# Script execution
main