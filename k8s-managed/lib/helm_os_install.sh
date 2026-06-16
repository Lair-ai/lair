#!/usr/bin/env bash
#─────────────────────────────────────────────────────────────────────────────
# helm_os_install.sh – Helm OS-level verification and installation
# Part of: k8s-managed setup
#─────────────────────────────────────────────────────────────────────────────

# Helm OS-level verification and installation for k8s-managed environment
install_helm_os() {
    info "Checking and installing Helm at OS level"
    
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
    local helm_url="https://get.helm.sh/helm-v3.14.0-$os-$arch.tar.gz"
    
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
    
    # Extract archive
    cd "$temp_dir"
    tar -zxf helm.tar.gz || {
        err "Failed to extract Helm"
        rm -rf "$temp_dir"
        return 1
    }
    
    # Move binary to system directory
    if [[ -f "$os-$arch/helm" ]]; then
        sudo mv "$os-$arch/helm" /usr/local/bin/helm || {
            err "Failed to install Helm to /usr/local/bin/"
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
        
        # Add standard default repositories
        info "Adding standard Helm repositories..."
        helm repo add stable https://charts.helm.sh/stable &>/dev/null || true
        helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx &>/dev/null || true
        helm repo add cert-manager https://charts.jetstack.io &>/dev/null || true
        helm repo add longhorn https://charts.longhorn.io &>/dev/null || true
        helm repo update &>/dev/null || true
        
        return 0
    else
        err "Helm installation failed - verification unsuccessful"
        return 1
    fi
}

# Function to verify Helm prerequisites
check_helm_prerequisites() {
    info "Verifying Helm prerequisites..."
    
    # Check that we have necessary tools for download
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        err "Neither curl nor wget available. Installation required."
        info "Installing curl..."
        
        # Detect package manager
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y curl
        elif command -v yum &>/dev/null; then
            sudo yum install -y curl
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y curl
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy curl --noconfirm
        else
            err "Unsupported package manager. Install curl manually."
            return 1
        fi
    fi
    
    # Check that we have tar
    if ! command -v tar &>/dev/null; then
        err "tar not available. Installation required."
        
        # Detect package manager
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y tar
        elif command -v yum &>/dev/null; then
            sudo yum install -y tar
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y tar
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy tar --noconfirm
        else
            err "Unsupported package manager. Install tar manually."
            return 1
        fi
    fi
    
    ok "Helm prerequisites verified"
}

# Main function for Helm OS installation
setup_helm_os() {
    info "=== HELM OS-LEVEL SETUP ==="
    
    check_helm_prerequisites || return 1
    install_helm_os || return 1
    
    ok "Helm OS setup completed successfully"
} 