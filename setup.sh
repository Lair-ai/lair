#!/bin/bash

# ============================================================================
# LAIR PROJECT - MAIN SETUP ENTRY POINT
# ============================================================================
# This script guides users through the complete Lair setup process
# - Cluster setup (managed Kubernetes or MicroK8s)
# - Lair application deployment
# ============================================================================

set -e

# Check for sudo privileges
check_sudo() {
    if [ "$EUID" -eq 0 ]; then
        return 0
    elif sudo -n true 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Ensure sudo privileges
if ! check_sudo; then
    echo -e "\033[0;31m❌ This script requires sudo privileges for installation.\033[0m"
    echo -e "\033[1;33m🔑 Please run: sudo ./setup.sh\033[0m"
    echo ""
    echo "Or ensure you have sudo access and try again."
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Utility functions
print_header() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                                                                               ║"
    echo "║                        🚀 WELCOME TO LAIR SETUP 🚀                            ║"
    echo "║                                                                               ║"
    echo "║     Lair is a comprehensive AI development platform that includes:            ║"
    echo "║     • Ollama (Local LLM inference)                                            ║"
    echo "║     • Open WebUI (Chat interface)                                             ║"
    echo "║     • ComfyUI (AI image generation)                                           ║"
    echo "║     • n8n (Workflow automation)                                               ║"
    echo "║     • And much more...                                                        ║"
    echo "║                                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_step() {
    echo -e "${CYAN}📋 SETUP PROCESS OVERVIEW:${NC}"
    echo ""
    echo -e "${YELLOW}Step 1:${NC} Cluster Setup"
    echo "   Choose between managed Kubernetes or local MicroK8s installation"
    echo ""
    echo -e "${YELLOW}Step 2:${NC} Lair Application Deployment"
    echo "   Deploy the Lair platform components using Helm"
    echo ""
    echo "Complete each step separately through the interactive menu."
    echo ""
}

show_main_menu() {
    echo -e "${CYAN}🎯 WHAT WOULD YOU LIKE TO DO?${NC}"
    echo ""
    echo "1) Set up Kubernetes cluster (Step 1)"
    echo "2) Deploy Lair application (Step 2 - requires existing cluster)"
    echo "3) Configure DNS for local network access (Jetson/LAN)"
    echo "4) Teardown/Cleanup options"
    echo "5) Exit"
    echo ""
}

show_cluster_menu() {
    echo -e "${CYAN}🔧 CLUSTER SETUP OPTIONS:${NC}"
    echo ""
    echo "1) I'm already connected to a managed Kubernetes cluster"
    echo "   (OVH MKS, Google GKE, etc.)"
    echo ""
    echo "2) I want to install MicroK8s on this machine"
    echo "   (VPS, bare-metal, or on-premises machine)"
    echo ""
    echo "3) Back to main menu"
    echo ""
}

show_teardown_menu() {
    echo -e "${CYAN}🧹 TEARDOWN/CLEANUP OPTIONS:${NC}"
    echo ""
    echo "1) Remove Lair application only"
    echo "   (Keep the Kubernetes cluster running)"
    echo ""
    echo "2) Remove DNS configuration"
    echo "   (Restore original DNS settings and remove wildcard DNS)"
    echo ""
    echo "3) Teardown MicroK8s cluster completely"
    echo "   (Remove MicroK8s installation and all data - includes Lair)"
    echo ""
    echo "4) Teardown managed cluster tools"
    echo "   (Remove Helm, kubectl, and clean cluster resources - includes Lair)"
    echo ""
    echo "5) Back to main menu"
    echo ""
}

teardown_lair_app() {
    print_info "Removing Lair application..."
    echo ""
    print_warning "This will remove ALL Lair components from your cluster."
    print_warning "This action is IRREVERSIBLE!"
    echo ""
    
    if get_confirmation "Do you want to continue? Type 'yes' to confirm: " | grep -q "^yes$"; then
        cd "$SCRIPT_DIR/helm-chart"
        print_info "Starting Lair cleanup..."
        ./cleanup.sh
        print_success "Lair application removed successfully!"
    else
        print_info "Teardown cancelled."
        return 1
    fi
}

teardown_microk8s() {
    print_info "Tearing down MicroK8s cluster..."
    echo ""
    print_warning "This will COMPLETELY remove MicroK8s and all its data."
    print_warning "This includes ALL applications, persistent volumes, and configurations."
    print_warning "This action is IRREVERSIBLE!"
    echo ""
    
    if get_confirmation "Do you want to continue? Type 'yes' to confirm: " | grep -q "^yes$"; then
        cd "$SCRIPT_DIR/microk8s"
        print_info "Starting MicroK8s teardown..."
        ./teardown.sh
        print_success "MicroK8s teardown completed!"
    else
        print_info "Teardown cancelled."
        return 1
    fi
}

teardown_dns() {
    print_info "Removing DNS configuration..."
    echo ""
    print_warning "This will restore your original DNS settings."
    print_warning "Wildcard DNS (*.hostname.local) will no longer work."
    print_warning "Other devices will no longer be able to use this machine as DNS server."
    echo ""
    
    if get_confirmation "Do you want to continue? (y/N): " | grep -iq "^y"; then
        cd "$SCRIPT_DIR/microk8s"
        print_info "Starting DNS restore process..."
        echo ""
        
        # Call the restore command directly - it handles everything
        sudo ./setup_dns.sh restore
        return_code=$?
        
        if [ $return_code -eq 0 ]; then
            echo ""
            print_success "DNS configuration restored successfully!"
            print_info "Your system is back to original DNS settings"
            print_info "Wildcard DNS has been removed"
        else
            echo ""
            print_warning "DNS restore process exited with code $return_code"
            print_info "This might mean no DNS backup was found or restore was cancelled"
        fi
        
        return $return_code
    else
        print_info "DNS removal cancelled."
        return 1
    fi
}

teardown_managed_cluster() {
    print_info "Tearing down managed cluster tools..."
    echo ""
    print_warning "This will remove Helm, kubectl, and clean cluster resources."
    print_warning "Your managed cluster will remain but tools will be uninstalled."
    echo ""
    
    if get_confirmation "Do you want to continue? Type 'yes' to confirm: " | grep -q "^yes$"; then
        cd "$SCRIPT_DIR/k8s-managed"
        print_info "Starting managed cluster teardown..."
        ./teardown.sh
        print_success "Managed cluster tools teardown completed!"
    else
        print_info "Teardown cancelled."
        return 1
    fi
}

setup_dns_wizard() {
    print_info "Starting DNS Configuration Wizard..."
    echo ""
    print_info "This wizard will configure DNS for local network access."
    print_info "Perfect for Jetson devices and LAN environments."
    echo ""
    print_warning "The process involves 4 simple steps:"
    echo ""
    echo -e "${YELLOW}Step 1:${NC} test      → Check current DNS status"
    echo -e "${YELLOW}Step 2:${NC} install   → Install wildcard DNS (*.hostname.local)"
    echo -e "${YELLOW}Step 3:${NC} test      → Verify DNS is working locally"
    echo -e "${YELLOW}Step 4:${NC} enable-network → Allow other devices to use this DNS"
    echo ""
    
    if get_confirmation "Do you want to continue with DNS setup? (y/N): " | grep -iq "^y"; then
        cd "$SCRIPT_DIR/microk8s"
        print_info "Starting DNS setup wizard..."
        echo ""
        # Call the interactive wizard (default when no parameters)
        sudo ./setup_dns.sh
        return_code=$?
        if [ $return_code -eq 0 ]; then
            echo ""
            print_success "DNS setup wizard completed!"
            print_info "Your system is now configured for *.$(hostname).local DNS resolution"
            print_info "Other devices on your network can use this machine as DNS server"
        else
            print_warning "DNS setup wizard exited with issues. Check the output above."
        fi
    else
        print_info "DNS setup cancelled."
        return 1
    fi
}



get_user_choice() {
    local prompt="$1"
    local choice
    echo -n -e "${YELLOW}$prompt${NC}" >&2
    read -r choice
    echo "$choice"
}

get_confirmation() {
    local prompt="$1"
    local response
    echo -n -e "${YELLOW}$prompt${NC}" >&2
    read -r response
    echo "$response"
}

setup_managed_cluster() {
    print_info "Setting up tools for managed Kubernetes cluster..."
    echo ""
    print_warning "This will install kubectl, helm, and other required tools."
    print_warning "Make sure you're already connected to your Kubernetes cluster!"
    echo ""
    
    if get_confirmation "Do you want to continue? (y/N): " | grep -iq "^y"; then
        cd "$SCRIPT_DIR/k8s-managed"
        print_info "Starting managed cluster setup..."
        ./setup.sh
        print_success "Managed cluster tools setup completed!"
    else
        print_info "Setup cancelled."
        return 1
    fi
}

setup_microk8s() {
    print_info "Setting up MicroK8s on this machine..."
    echo ""
    print_warning "This will install MicroK8s and configure it with all required addons."
    print_warning "This process requires sudo privileges and may take several minutes."
    echo ""
    
    if get_confirmation "Do you want to continue? (y/N): " | grep -iq "^y"; then
        cd "$SCRIPT_DIR/microk8s"
        print_info "Starting MicroK8s setup..."
        ./setup.sh
        print_success "MicroK8s setup completed!"
    else
        print_info "Setup cancelled."
        return 1
    fi
}

deploy_lair() {
    print_info "Deploying Lair application..."
    echo ""
    print_warning "This will deploy Lair components to your Kubernetes cluster."
    print_warning "Make sure your cluster is ready and you have admin access."
    echo ""
    
    if get_confirmation "Do you want to continue? (y/N): " | grep -iq "^y"; then
        cd "$SCRIPT_DIR/helm-chart"
        print_info "Starting Lair deployment..."
        ./setup.sh
        print_success "Lair deployment completed!"
    else
        print_info "Deployment cancelled."
        return 1
    fi
}

check_cluster_connectivity() {
    print_info "Checking cluster connectivity..."
    if command -v kubectl >/dev/null 2>&1; then
        if kubectl cluster-info >/dev/null 2>&1; then
            print_success "Successfully connected to Kubernetes cluster!"
            kubectl cluster-info
            return 0
        else
            print_warning "kubectl is installed but not connected to a cluster."
            return 1
        fi
    else
        print_warning "kubectl is not installed or not in PATH."
        return 1
    fi
}

handle_cluster_setup() {
    while true; do
        show_cluster_menu
        choice=$(get_user_choice "Enter your choice (1-3): ")
        
        case $choice in
            1)
                print_info "Proceeding with managed cluster setup..."
                if check_cluster_connectivity; then
                    setup_managed_cluster
                    return $?
                else
                    print_error "Please ensure you're connected to your managed cluster first!"
                    echo "Use: kubectl config set-context <your-context>"
                    continue
                fi
                ;;
            2)
                print_info "Proceeding with MicroK8s installation..."
                setup_microk8s
                return $?
                ;;
            3)
                return 0
                ;;
            *)
                print_error "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
}

handle_teardown() {
    while true; do
        show_teardown_menu
        choice=$(get_user_choice "Enter your choice (1-5): ")
        
        case $choice in
            1)
                print_info "Proceeding with Lair application removal..."
                if check_cluster_connectivity; then
                    teardown_lair_app
                    return $?
                else
                    print_error "No Kubernetes cluster detected!"
                    print_info "Cannot remove Lair without cluster access."
                fi
                ;;
            2)
                print_info "Proceeding with DNS configuration removal..."
                teardown_dns
                return $?
                ;;
            3)
                print_info "Proceeding with MicroK8s teardown..."
                teardown_microk8s
                return $?
                ;;
            4)
                print_info "Proceeding with managed cluster teardown..."
                teardown_managed_cluster
                return $?
                ;;
            5)
                return 0
                ;;
            *)
                print_error "Invalid choice. Please enter 1, 2, 3, 4, or 5."
                ;;
        esac
    done
}

main() {
    print_header
    print_step
    
    while true; do
        show_main_menu
        choice=$(get_user_choice "Enter your choice (1-5): ")
        
        case $choice in
            1)
                print_info "Starting cluster setup..."
                handle_cluster_setup
                ;;
            2)
                print_info "Starting Lair deployment..."
                if check_cluster_connectivity; then
                    deploy_lair
                else
                    print_error "No Kubernetes cluster detected!"
                    print_info "Please complete Step 1 (cluster setup) first."
                fi
                ;;
            3)
                print_info "Starting DNS configuration..."
                setup_dns_wizard
                ;;
            4)
                print_info "Starting teardown/cleanup..."
                handle_teardown
                ;;
            5)
                print_info "Goodbye! 👋"
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please enter 1, 2, 3, 4, or 5."
                ;;
        esac
        
        echo ""
        echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
        echo ""
    done
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 