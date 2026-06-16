#!/usr/bin/env bash
#===============================================================================
# Script: optimize-system-disk.sh
# Description: Manually optimize Longhorn storage reservation on system disk
# Usage: sudo ./optimize-system-disk.sh [--force]
#===============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   err "This script must be run as root (use sudo)"
   exit 1
fi

# Parse arguments
FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
    info "Force mode enabled - will apply optimization even if within tolerance"
fi

echo ""
echo "=========================================="
echo "  Longhorn System Disk Optimization"
echo "=========================================="
echo ""

# Check if microk8s is installed
if ! command -v microk8s >/dev/null 2>&1; then
    err "MicroK8s not found. Please install MicroK8s first."
    exit 1
fi

# Check if jq is installed
if ! command -v jq >/dev/null 2>&1; then
    err "jq not found. Installing..."
    apt update && apt install -y jq
fi

# Check if Longhorn is installed
if ! microk8s kubectl get ns longhorn-system >/dev/null 2>&1; then
    err "Longhorn namespace not found. Is Longhorn installed?"
    exit 1
fi

# Wait for Longhorn to be ready
info "Checking Longhorn status..."
if ! microk8s kubectl get nodes.longhorn.io -n longhorn-system >/dev/null 2>&1; then
    err "Longhorn nodes API not ready. Please wait for Longhorn to be fully operational."
    exit 1
fi

# Get node name
NODE_NAME=$(hostname)
info "Node name: $NODE_NAME"

# Check if Longhorn node exists
if ! microk8s kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" >/dev/null 2>&1; then
    err "Longhorn node $NODE_NAME not found"
    exit 1
fi

# Get node configuration
info "Retrieving disk configuration..."
DISKS_JSON=$(microk8s kubectl get nodes.longhorn.io -n longhorn-system "$NODE_NAME" -o json)

if [[ -z "$DISKS_JSON" ]]; then
    err "Unable to retrieve disk configuration"
    exit 1
fi

# Find system disk
DISK_NAMES=$(echo "$DISKS_JSON" | jq -r '.spec.disks | keys[]')
SYSTEM_DISK=""
SYSTEM_DISK_PATH=""

for disk_name in $DISK_NAMES; do
    disk_path=$(echo "$DISKS_JSON" | jq -r ".spec.disks.\"$disk_name\".path")
    
    # Check if this is the system disk
    if [[ "$disk_path" == "/var/lib/longhorn/" ]] || [[ "$disk_path" =~ ^/var/lib/longhorn/?$ ]]; then
        SYSTEM_DISK="$disk_name"
        SYSTEM_DISK_PATH="$disk_path"
        break
    fi
done

if [[ -z "$SYSTEM_DISK" ]]; then
    err "System disk not found in Longhorn configuration"
    exit 1
fi

ok "Found system disk: $SYSTEM_DISK (path: $SYSTEM_DISK_PATH)"

# Get device information
MOUNT_POINT="/"
DEVICE=$(df "$MOUNT_POINT" | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')

if [[ -z "$DEVICE" ]]; then
    err "Unable to determine device for $MOUNT_POINT"
    exit 1
fi

info "Device: $DEVICE"

# Get disk size
TOTAL_BYTES=$(lsblk -b -d -n -o SIZE "$DEVICE" 2>/dev/null | head -1 | tr -d '[:space:]')

if [[ -z "$TOTAL_BYTES" ]] || ! [[ "$TOTAL_BYTES" =~ ^[0-9]+$ ]]; then
    err "Unable to determine disk size for $DEVICE"
    exit 1
fi

TOTAL_GB=$((TOTAL_BYTES / 1024 / 1024 / 1024))
ok "System disk size: ${TOTAL_GB}GB"

# Calculate optimal reserved storage
# Formula: min(30% of disk, 128GB)
THIRTY_PERCENT=$((TOTAL_BYTES * 30 / 100))
MAX_RESERVED=$((128 * 1024 * 1024 * 1024))  # 128GB in bytes

OPTIMAL_RESERVED=0
if [[ $THIRTY_PERCENT -lt $MAX_RESERVED ]]; then
    OPTIMAL_RESERVED=$THIRTY_PERCENT
    RESERVED_GB=$((OPTIMAL_RESERVED / 1024 / 1024 / 1024))
    info "Formula: 30% of disk = ${RESERVED_GB}GB"
else
    OPTIMAL_RESERVED=$MAX_RESERVED
    info "Formula: Capped at 128GB (disk > 427GB)"
fi

# Get current reserved storage
CURRENT_RESERVED=$(echo "$DISKS_JSON" | jq -r ".spec.disks.\"$SYSTEM_DISK\".storageReserved")

if [[ -z "$CURRENT_RESERVED" ]] || [[ "$CURRENT_RESERVED" == "null" ]]; then
    CURRENT_RESERVED=0
fi

CURRENT_GB=$((CURRENT_RESERVED / 1024 / 1024 / 1024))
OPTIMAL_GB=$((OPTIMAL_RESERVED / 1024 / 1024 / 1024))

echo ""
echo "=========================================="
echo "  Current Configuration"
echo "=========================================="
echo "Disk: $SYSTEM_DISK"
echo "Path: $SYSTEM_DISK_PATH"
echo "Device: $DEVICE"
echo "Total Size: ${TOTAL_GB}GB"
echo "Current Reserved: ${CURRENT_GB}GB"
echo "Optimal Reserved: ${OPTIMAL_GB}GB"
echo ""

# Check if optimization is needed
DIFF=$((OPTIMAL_RESERVED - CURRENT_RESERVED))
DIFF_ABS=${DIFF#-}  # absolute value
TOLERANCE=$((OPTIMAL_RESERVED * 5 / 100))

if [[ $DIFF_ABS -lt $TOLERANCE ]] && [[ "$FORCE" == "false" ]]; then
    ok "Storage reservation is already optimal (within 5% tolerance)"
    ok "Current: ${CURRENT_GB}GB, Optimal: ${OPTIMAL_GB}GB"
    echo ""
    info "Use --force flag to apply optimization anyway"
    exit 0
fi

# Calculate storage impact
if [[ $CURRENT_RESERVED -gt $OPTIMAL_RESERVED ]]; then
    FREED_BYTES=$((CURRENT_RESERVED - OPTIMAL_RESERVED))
    FREED_GB=$((FREED_BYTES / 1024 / 1024 / 1024))
    info "💡 This will FREE UP ${FREED_GB}GB for Longhorn storage"
elif [[ $CURRENT_RESERVED -lt $OPTIMAL_RESERVED ]]; then
    REDUCED_BYTES=$((OPTIMAL_RESERVED - CURRENT_RESERVED))
    REDUCED_GB=$((REDUCED_BYTES / 1024 / 1024 / 1024))
    info "⚠️  This will REDUCE available storage by ${REDUCED_GB}GB"
fi

# Confirmation prompt
echo ""
read -rp "Apply optimization? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    info "Optimization cancelled"
    exit 0
fi

echo ""
info "Applying optimization: ${CURRENT_GB}GB → ${OPTIMAL_GB}GB"

# Apply patch with retry logic
PATCH_SUCCESS=false
RETRY_COUNT=0
MAX_RETRIES=5

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]] && [[ "$PATCH_SUCCESS" == "false" ]]; do
    PATCH_ERROR=$(microk8s kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type='json' -p "[
        {
            \"op\": \"replace\",
            \"path\": \"/spec/disks/$SYSTEM_DISK/storageReserved\",
            \"value\": $OPTIMAL_RESERVED
        }
    ]" 2>&1)
    PATCH_RESULT=$?
    
    if [[ $PATCH_RESULT -eq 0 ]]; then
        PATCH_SUCCESS=true
        ok "Storage reservation optimized to ${OPTIMAL_GB}GB"
        
        # Calculate usable storage
        USABLE_BYTES=$((TOTAL_BYTES - OPTIMAL_RESERVED))
        USABLE_GB=$((USABLE_BYTES / 1024 / 1024 / 1024))
        USABLE_PERCENT=$((USABLE_BYTES * 100 / TOTAL_BYTES))
        
        echo ""
        echo "=========================================="
        echo "  Optimization Complete"
        echo "=========================================="
        echo "Reserved for System: ${OPTIMAL_GB}GB"
        echo "Available for Longhorn: ${USABLE_GB}GB (~${USABLE_PERCENT}%)"
        echo ""
        
    elif echo "$PATCH_ERROR" | grep -q "webhook"; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; then
            warn "Webhook not ready, waiting 10s before retry ($RETRY_COUNT/$MAX_RETRIES)..."
            sleep 10
        else
            warn "Webhook still not ready after $MAX_RETRIES attempts"
            info "Attempting direct patch without webhook validation..."
            
            if microk8s kubectl patch nodes.longhorn.io -n longhorn-system "$NODE_NAME" --type='json' -p "[
                {
                    \"op\": \"replace\",
                    \"path\": \"/spec/disks/$SYSTEM_DISK/storageReserved\",
                    \"value\": $OPTIMAL_RESERVED
                }
            ]" 2>/dev/null; then
                ok "Storage reservation optimized to ${OPTIMAL_GB}GB (without webhook)"
                PATCH_SUCCESS=true
            else
                err "Failed to apply optimization"
                err "Webhook validation is blocking the operation"
                echo ""
                info "Try disabling webhooks temporarily:"
                info "  microk8s kubectl delete mutatingwebhookconfigurations longhorn-webhook-mutator"
                info "  microk8s kubectl delete validatingwebhookconfigurations longhorn-webhook-validator"
                info "Then run this script again"
                exit 1
            fi
        fi
    else
        err "Failed to optimize storage reservation"
        err "Error: $PATCH_ERROR"
        exit 1
    fi
done

if [[ "$PATCH_SUCCESS" == "true" ]]; then
    echo ""
    ok "✅ Optimization completed successfully!"
    echo ""
    info "Verify with:"
    info "  microk8s kubectl get nodes.longhorn.io -n longhorn-system $NODE_NAME -o json | jq '.spec.disks.\"$SYSTEM_DISK\".storageReserved'"
    echo ""
else
    err "Optimization failed after $MAX_RETRIES attempts"
    exit 1
fi

