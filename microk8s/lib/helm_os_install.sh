#!/usr/bin/env bash
#─────────────────────────────────────────────────────────────────────────────
# helm_os_install.sh – Helm OS-level verification and installation
# Part of: setup_microk8s.sh
#─────────────────────────────────────────────────────────────────────────────

# Step 17.5: Helm OS-level verification and installation
install_helm_os() {
    info "Helm OS-level verification and installation"
    
    # Check if helm is already installed and working
    if command -v helm &>/dev/null && helm version &>/dev/null; then
        local helm_version=$(helm version --short 2>/dev/null | cut -d'+' -f1 || echo "unknown")
        ok "Helm already installed at OS level: $helm_version"
        return 0
    fi
    
    info "Helm not found at OS level, proceeding with installation..."
    
    # Determine system architecture
    local arch=""
    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="arm" ;;
        *)
            err "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac
    
    # Determine OS
    local os=""
    case "$(uname -s)" in
        Linux)  os="linux" ;;
        Darwin) os="darwin" ;;
        *)
            err "Unsupported operating system: $(uname -s)"
            return 1
            ;;
    esac
    
    info "Detected architecture: $arch, OS: $os"
    
    # Download and install helm
    local temp_dir="/tmp/helm-install-$$"
    mkdir -p "$temp_dir"
    
    info "Downloading Helm for $os-$arch..."
    
    # Latest stable version URL
    local helm_url="https://get.helm.sh/helm-v3.17.3-$os-$arch.tar.gz"
    
    if command -v curl &>/dev/null; then
        curl -fsSL "$helm_url" -o "$temp_dir/helm.tar.gz" || {
            err "Failed to download Helm with curl"
            rm -rf "$temp_dir"
            return 1
        }
    elif command -v wget &>/dev/null; then
        wget -q "$helm_url" -O "$temp_dir/helm.tar.gz" || {
            err "Failed to download Helm with wget"
            rm -rf "$temp_dir"
            return 1
        }
    else
        err "Neither curl nor wget available for download"
        rm -rf "$temp_dir"
        return 1
    fi
    
    info "Extracting and installing..."
    
    # Extract the archive
    cd "$temp_dir"
    tar -zxf helm.tar.gz || {
        err "Failed to extract Helm"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Move binary to system directory
    if [[ -f "$os-$arch/helm" ]]; then
        sudo mv "$os-$arch/helm" /usr/local/bin/helm || {
            err "Failed to install Helm in /usr/local/bin/"
            rm -rf "$temp_dir"
            return 1
        }
        sudo chmod +x /usr/local/bin/helm
    else
        err "Helm binary not found in extracted archive"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    
    # Verify installation
    if command -v helm &>/dev/null && helm version &>/dev/null; then
        local installed_version=$(helm version --short 2>/dev/null | cut -d'+' -f1 || echo "unknown")
        ok "Helm successfully installed at OS level: $installed_version"
        
        # Add default stable repository
        info "Adding Helm stable repository..."
        helm repo add stable https://charts.helm.sh/stable &>/dev/null || true
        helm repo update &>/dev/null || true
        
        return 0
    else
        err "Helm installation failed - verification failed"
        return 1
    fi
}

# Function to verify Helm prerequisites
check_helm_prerequisites() {
    info "Verifying Helm prerequisites..."
    
    # Check that we have the necessary tools for download
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        err "Neither curl nor wget available. Installation required."
        info "Installing curl..."
        apt-get update -qq && apt-get install -y curl
    fi
    
    # Check that we have tar
    if ! command -v tar &>/dev/null; then
        err "tar not available. Installation required."
        apt-get update -qq && apt-get install -y tar
    fi
    
    ok "Helm prerequisites verified"
}

# region 17.5) OS-level Helm installation
info "OS-level Helm installation"

check_helm_prerequisites
install_helm_os

if [[ $? -eq 0 ]]; then
    ok "OS-level Helm installation completed successfully"
else
    err "OS-level Helm installation failed"
    exit 1
fi
# endregion 17.5) OS-level Helm installation