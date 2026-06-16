#!/usr/bin/env bash
#─────────────────────────────────────────────────────────────────────────────
# setup-secondary.sh – Simplified secondary node setup
# Usage: sudo ./setup-secondary.sh <PRIMARY_IP> <JOIN_TOKEN>
#─────────────────────────────────────────────────────────────────────────────

# Colors for output
BLUE="\e[94m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; NC="\e[0m"

# Helper functions
info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
ok() { printf "${GREEN}[✓]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[⚠]${NC} %s\n" "$1"; }
err() { printf "${RED}[✗]${NC} %s\n" "$1"; }

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    err "This script must be run as root"
    echo "Usage: sudo $0 <PRIMARY_IP> <JOIN_TOKEN>"
    exit 1
fi

# Show help if requested
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo -e "${BLUE}=== MicroK8s Secondary Node Setup ===${NC}"
    echo ""
    echo "This script simplifies the setup of secondary nodes in a MicroK8s cluster."
    echo ""
    echo -e "${GREEN}Usage:${NC}"
    echo "  sudo $0 <PRIMARY_IP> <JOIN_TOKEN>"
    echo ""
    echo -e "${GREEN}Parameters:${NC}"
    echo "  PRIMARY_IP   - IP address of the primary node"
    echo "  JOIN_TOKEN   - Join token from the primary node"
    echo ""
    echo -e "${GREEN}Examples:${NC}"
    echo "  sudo $0 192.168.1.100 192.168.1.100:25000/abc123def456..."
    echo ""
    echo -e "${YELLOW}To get the join token from the primary node:${NC}"
    echo "  microk8s add-node"
    echo ""
    echo -e "${YELLOW}Alternative: Use the main setup script with parameters:${NC}"
    echo "  sudo ./setup.sh --node-type secondary --primary-ip 192.168.1.100 --join-token 192.168.1.100:25000/abc123..."
    exit 0
fi

# Check parameters
if [[ $# -lt 2 ]]; then
    err "Missing required parameters"
    echo ""
    echo -e "${YELLOW}Usage:${NC} sudo $0 <PRIMARY_IP> <JOIN_TOKEN>"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  sudo $0 192.168.1.100 192.168.1.100:25000/abc123def456..."
    echo ""
    echo -e "${YELLOW}For help:${NC} sudo $0 --help"
    exit 1
fi

PRIMARY_IP="$1"
JOIN_TOKEN="$2"

# Validate IP format
if ! [[ "$PRIMARY_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    err "Invalid IP address format: $PRIMARY_IP"
    exit 1
fi

# Validate token format (basic check)
if ! [[ "$JOIN_TOKEN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/[a-zA-Z0-9]+$ ]]; then
    warn "Join token format may be invalid"
    warn "Expected format: IP:PORT/TOKEN"
    echo ""
    read -rp "Continue anyway? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        info "Setup cancelled"
        exit 0
    fi
fi

# Show configuration
echo -e "${BLUE}=== 🔗 SECONDARY NODE SETUP ===${NC}"
echo -e "${GREEN}Primary Node IP:${NC} $PRIMARY_IP"
echo -e "${GREEN}Join Token:${NC} ${JOIN_TOKEN:0:20}... (truncated for security)"
echo ""

# Confirm setup
read -rp "Proceed with secondary node setup? [Y/n]: " confirm
if [[ "$confirm" =~ ^[nN]$ ]]; then
    info "Setup cancelled by user"
    exit 0
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run the main setup script with parameters
info "Starting secondary node setup..."
exec "$SCRIPT_DIR/setup.sh" --node-type secondary --primary-ip "$PRIMARY_IP" --join-token "$JOIN_TOKEN"
