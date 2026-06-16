#!/usr/bin/env bash

run_system_setup() {
    info "Running system setup..."

    # In a managed K8s environment, most system configurations
    # (hostname, OS updates, kernel modules) are managed by the cloud provider.
    # We only install necessary dependencies for configuration scripts.

    # Installing YAML parsing dependencies for configuration scripts
    info "Installing YAML parsing dependencies for configuration scripts"
    if ! (apt update -y && apt install -y python3-yaml yq jq); then
        warn "python3-yaml, yq, or jq installation failed, trying separate installations..."
        
        # Try python3-yaml installation
        if ! apt install -y python3-yaml; then
            warn "Unable to install python3-yaml"
            
            # Fallback: try installation via pip
            if command -v pip3 >/dev/null 2>&1; then
                info "Attempting PyYAML installation via pip3..."
                if ! pip3 install --break-system-packages PyYAML; then
                    warn "PyYAML installation via pip3 failed"
                else
                    ok "PyYAML installed via pip3"
                fi
            else
                warn "pip3 not available, YAML parser installation failed"
            fi
        else
            ok "python3-yaml installed"
        fi
        
        # Try yq installation
        if ! apt install -y yq; then
            warn "Unable to install yq from standard repository"
            
            # Fallback: yq installation via snap
            if command -v snap >/dev/null 2>&1; then
                info "Attempting yq installation via snap..."
                if ! snap install yq; then
                    warn "yq installation via snap failed"
                else
                    ok "yq installed via snap"
                fi
            else
                warn "snap not available, yq installation failed"
            fi
        else
            ok "yq installed"
        fi
        
        # Try jq installation
        if ! apt install -y jq; then
            warn "Unable to install jq from standard repository"
            
            # Fallback: jq installation via snap
            if command -v snap >/dev/null 2>&1; then
                info "Attempting jq installation via snap..."
                if ! snap install jq; then
                    warn "jq installation via snap failed"
                else
                    ok "jq installed via snap"
                fi
            else
                warn "snap not available, jq installation failed"
            fi
        else
            ok "jq installed"
        fi
    else
        ok "All dependencies (python3-yaml, yq, jq) installed correctly"
    fi

    # Final verification of available YAML parsers
    info "Verifying available YAML parsers..."
    YAML_PARSERS_AVAILABLE=0

    if command -v yq >/dev/null 2>&1; then
        ok "yq parser available"
        YAML_PARSERS_AVAILABLE=1
    fi

    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import yaml" >/dev/null 2>&1; then
            ok "python3 with yaml module available"
            YAML_PARSERS_AVAILABLE=1
        else
            warn "python3 available but without yaml module"
        fi
    fi

    if [ $YAML_PARSERS_AVAILABLE -eq 0 ]; then
        warn "No YAML parser available - configuration scripts will use interactive mode"
    else
        ok "At least one YAML parser is available"
    fi
    
    # Verify jq availability (required for Longhorn optimization)
    if command -v jq >/dev/null 2>&1; then
        ok "jq available for JSON parsing"
    else
        warn "jq not available - Longhorn storage optimization will be skipped"
    fi

    ok "System setup completed."
}