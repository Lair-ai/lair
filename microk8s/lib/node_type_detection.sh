#!/usr/bin/env bash

# region 2.5) Node Type Detection and Configuration
info "Detecting node type and cluster configuration..."

# Global variables for node configuration
NODE_TYPE=""           # "primary" or "secondary"
PRIMARY_NODE_IP=""     # IP of the primary node (for secondary nodes)
JOIN_TOKEN=""          # Token to join the cluster (for secondary nodes)
CLUSTER_NAME=""        # Name of the cluster

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        local IFS='.'
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            (( octet >= 0 && octet <= 255 )) || return 1
        done
        return 0
    fi
    return 1
}

# Function to test connectivity to primary node
test_primary_connectivity() {
    local primary_ip=$1
    info "Testing connectivity to primary node at $primary_ip..."
    
    # Test basic connectivity
    if ! ping -c 3 -W 5 "$primary_ip" >/dev/null 2>&1; then
        warn "Cannot reach primary node at $primary_ip"
        return 1
    fi
    
    # Test if MicroK8s API is accessible (port 16443)
    if command -v nc >/dev/null 2>&1; then
        if ! timeout 5 nc -z "$primary_ip" 16443 2>/dev/null; then
            warn "MicroK8s API port (16443) not accessible on $primary_ip"
            warn "Make sure the primary node is properly configured and accessible"
            return 1
        fi
    fi
    
    ok "Primary node connectivity verified"
    return 0
}

# Load configuration file if exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/cluster.conf"

if [[ -f "$CONFIG_FILE" ]]; then
    info "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
fi

# Check for command line arguments first
CMDLINE_NODE_TYPE=""
CMDLINE_PRIMARY_IP=""
CMDLINE_JOIN_TOKEN=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --node-type)
            CMDLINE_NODE_TYPE="$2"
            shift 2
            ;;
        --primary-ip)
            CMDLINE_PRIMARY_IP="$2"
            shift 2
            ;;
        --join-token)
            CMDLINE_JOIN_TOKEN="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --node-type TYPE     Node type: 'primary' or 'secondary'"
            echo "  --primary-ip IP      IP address of the primary node (for secondary nodes)"
            echo "  --join-token TOKEN   Join token from primary node (for secondary nodes)"
            echo "  --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  # Primary node setup"
            echo "  sudo $0 --node-type primary"
            echo ""
            echo "  # Secondary node setup"
            echo "  sudo $0 --node-type secondary --primary-ip 192.168.1.100 --join-token 192.168.1.100:25000/abc123..."
            echo ""
            echo "  # Interactive mode (default)"
            echo "  sudo $0"
            exit 0
            ;;
        *)
            warn "Unknown option: $1"
            shift
            ;;
    esac
done

# Use command line arguments or environment variables, with interactive as fallback
if [[ -n "$CMDLINE_NODE_TYPE" ]]; then
    NODE_TYPE="$CMDLINE_NODE_TYPE"
elif [[ -n "${NODE_TYPE:-}" ]]; then
    # Use environment variable if set
    NODE_TYPE="$NODE_TYPE"
elif [[ -n "${PRIMARY_NODE_IP:-}" && -n "${JOIN_TOKEN:-}" ]]; then
    # Auto-detect secondary if both PRIMARY_NODE_IP and JOIN_TOKEN are set
    NODE_TYPE="secondary"
    info "Auto-detected secondary node setup from environment variables"
elif $INTERACTIVE; then
    echo -e "\n${BLUE}=== 🏗️  MICROK8S CLUSTER SETUP ===${NC}"
    echo -e "${YELLOW}This script can setup MicroK8s in two modes:${NC}"
    echo ""
    echo -e "${GREEN}1. PRIMARY NODE${NC} - First node of the cluster"
    echo -e "   • Installs and configures all MicroK8s components"
    echo -e "   • Sets up MetalLB, storage, and networking"
    echo -e "   • Generates join tokens for secondary nodes"
    echo -e "   • Configures ingress and DNS"
    echo ""
    echo -e "${GREEN}2. SECONDARY NODE${NC} - Additional nodes joining existing cluster"
    echo -e "   • Joins an existing MicroK8s cluster"
    echo -e "   • Minimal configuration (no addons installation)"
    echo -e "   • Requires primary node IP and join token"
    echo -e "   • Extends cluster capacity and availability"
    echo ""
    
    while :; do
        read -rp "🎯 Is this the PRIMARY node or a SECONDARY node? [primary/secondary]: " choice
        choice="${choice,,}"
        if [[ "$choice" == "primary" || "$choice" == "p" ]]; then
            NODE_TYPE="primary"
            break
        elif [[ "$choice" == "secondary" || "$choice" == "s" ]]; then
            NODE_TYPE="secondary"
            break
        else
            warn "Invalid choice. Please enter 'primary' or 'secondary'"
        fi
    done
else
    # Non-interactive mode: default to primary
    NODE_TYPE="primary"
    info "Non-interactive mode: defaulting to PRIMARY node"
fi

ok "Node type selected: $NODE_TYPE"

# Configure based on node type
case "$NODE_TYPE" in
    primary)
        info "🏗️  PRIMARY NODE SETUP"
        info "This node will be configured as the cluster master"
        info "All MicroK8s components and addons will be installed"
        
        # Set cluster name
        if $INTERACTIVE; then
            read -rp "📛 Enter cluster name [microk8s-cluster]: " CLUSTER_NAME
            CLUSTER_NAME="${CLUSTER_NAME:-microk8s-cluster}"
        else
            CLUSTER_NAME="microk8s-cluster"
        fi
        ok "Cluster name: $CLUSTER_NAME"
        ;;
        
    secondary)
        info "🔗 SECONDARY NODE SETUP"
        info "This node will join an existing MicroK8s cluster"
        
        # Get primary node information
        if [[ -n "$CMDLINE_PRIMARY_IP" ]]; then
            PRIMARY_NODE_IP="$CMDLINE_PRIMARY_IP"
        elif [[ -n "${PRIMARY_NODE_IP:-}" ]]; then
            # Use environment variable if already set
            PRIMARY_NODE_IP="$PRIMARY_NODE_IP"
        fi
        
        while [[ -z "$PRIMARY_NODE_IP" ]]; do
            if $INTERACTIVE; then
                read -rp "🌐 Enter PRIMARY node IP address: " PRIMARY_NODE_IP
            else
                err "Non-interactive mode requires PRIMARY_NODE_IP environment variable or --primary-ip parameter"
                exit 1
            fi
            
            if validate_ip "$PRIMARY_NODE_IP"; then
                if test_primary_connectivity "$PRIMARY_NODE_IP"; then
                    break
                else
                    if $INTERACTIVE; then
                        read -rp "❓ Continue anyway? [y/N]: " continue_choice
                        if [[ "$continue_choice" =~ ^[yY]$ ]]; then
                            warn "Continuing without connectivity verification"
                            break
                        fi
                    else
                        err "Cannot connect to primary node. Aborting."
                        exit 1
                    fi
                fi
            else
                err "Invalid IP address format: $PRIMARY_NODE_IP"
                if ! $INTERACTIVE; then
                    exit 1
                fi
            fi
        done
        
        # Get join token
        if [[ -n "$CMDLINE_JOIN_TOKEN" ]]; then
            JOIN_TOKEN="$CMDLINE_JOIN_TOKEN"
        elif [[ -n "${JOIN_TOKEN:-}" ]]; then
            # Use environment variable if already set
            JOIN_TOKEN="$JOIN_TOKEN"
        fi
        
        if [[ -z "$JOIN_TOKEN" ]]; then
            echo ""
            echo -e "${YELLOW}📋 To get the join token from the PRIMARY node, run:${NC}"
            echo -e "${GREEN}   microk8s add-node${NC}"
            echo -e "${YELLOW}Copy the complete join command or just the token part.${NC}"
            echo ""
        fi
        
        while [[ -z "$JOIN_TOKEN" ]]; do
            if $INTERACTIVE; then
                read -rp "🔑 Enter join token (or complete join command): " JOIN_TOKEN
            else
                err "Non-interactive mode requires JOIN_TOKEN environment variable or --join-token parameter"
                exit 1
            fi
            
            if [[ -n "$JOIN_TOKEN" ]]; then
                # Extract token from full command if provided
                if [[ "$JOIN_TOKEN" == *"microk8s join"* ]]; then
                    # Try to extract IP:port/token format first
                    extracted_token=$(echo "$JOIN_TOKEN" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/[a-zA-Z0-9]+' || echo "")
                    if [[ -n "$extracted_token" ]]; then
                        JOIN_TOKEN="$extracted_token"
                    else
                        # Try to extract newer token formats (TOKEN/TOKEN or TOKEN/TOKEN/TOKEN)
                        extracted_token=$(echo "$JOIN_TOKEN" | grep -oE '[a-zA-Z0-9]+/[a-zA-Z0-9]+(/[a-zA-Z0-9]+)?' || echo "")
                        if [[ -n "$extracted_token" ]]; then
                            JOIN_TOKEN="$extracted_token"
                        fi
                    fi
                fi
                
                # Validate token format - accept multiple formats
                if [[ "$JOIN_TOKEN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/[a-zA-Z0-9]+$ ]] || \
                   [[ "$JOIN_TOKEN" =~ ^[a-zA-Z0-9]+/[a-zA-Z0-9]+$ ]] || \
                   [[ "$JOIN_TOKEN" =~ ^[a-zA-Z0-9]+/[a-zA-Z0-9]+/[a-zA-Z0-9]+$ ]]; then
                    break
                else
                    err "Invalid token format. Expected: IP:PORT/TOKEN, TOKEN/TOKEN, or TOKEN/TOKEN/TOKEN"
                    if ! $INTERACTIVE; then
                        exit 1
                    fi
                fi
            else
                err "Join token cannot be empty"
                if ! $INTERACTIVE; then
                    exit 1
                fi
            fi
        done
        
        ok "Primary node: $PRIMARY_NODE_IP"
        ok "Join token configured"
        
        # Extract cluster name from primary if possible
        CLUSTER_NAME="microk8s-cluster"  # Default fallback
        ;;
        
    *)
        err "Invalid node type: $NODE_TYPE"
        exit 1
        ;;
esac

# Export variables for use in other modules
export NODE_TYPE
export PRIMARY_NODE_IP
export JOIN_TOKEN
export CLUSTER_NAME

# Set flags for conditional execution in other modules
export IS_PRIMARY_NODE=$([[ "$NODE_TYPE" == "primary" ]] && echo "true" || echo "false")
export IS_SECONDARY_NODE=$([[ "$NODE_TYPE" == "secondary" ]] && echo "true" || echo "false")

info "Node configuration completed"
debug "NODE_TYPE=$NODE_TYPE"
debug "IS_PRIMARY_NODE=$IS_PRIMARY_NODE"
debug "IS_SECONDARY_NODE=$IS_SECONDARY_NODE"
if [[ "$NODE_TYPE" == "secondary" ]]; then
    debug "PRIMARY_NODE_IP=$PRIMARY_NODE_IP"
    debug "JOIN_TOKEN=[REDACTED]"
fi
debug "CLUSTER_NAME=$CLUSTER_NAME"

# endregion 2.5) Node Type Detection and Configuration
