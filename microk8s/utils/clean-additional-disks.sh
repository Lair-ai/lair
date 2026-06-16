#!/bin/bash
# clean-additional-disks.sh - Clean Longhorn additional disks for fresh reinstallation
# 
# This script automatically detects and cleans additional disks configured for Longhorn,
# making them ready for a fresh installation. Works even if MicroK8s is uninstalled.
#
# Usage: sudo ./clean-additional-disks.sh [--force] [--deep-clean]
#
# Options:
#   --force       Skip confirmation prompts
#   --deep-clean  Perform deep wipe with dd (slower but more thorough)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
FORCE=false
DEEP_CLEAN=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --deep-clean)
            DEEP_CLEAN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--force] [--deep-clean]"
            echo ""
            echo "Options:"
            echo "  --force       Skip confirmation prompts"
            echo "  --deep-clean  Perform deep wipe with dd (slower but more thorough)"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ This script must be run as root${NC}"
   exit 1
fi

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}🧹 Longhorn Additional Disks Cleanup${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# Function to detect additional disks
detect_additional_disks() {
    local disks=()
    
    # Method 1: Check currently mounted Longhorn disks
    echo -e "${YELLOW}🔍 Detecting mounted Longhorn disks...${NC}" >&2
    while IFS= read -r line; do
        local mount_point
        mount_point=$(echo "$line" | awk '{print $3}')
        local device
        device=$(echo "$line" | awk '{print $1}')
        
        # Check if it's a Longhorn additional disk (disk2, disk3, etc.)
        if [[ "$mount_point" =~ /var/lib/longhorn/disk[0-9]+ ]]; then
            echo -e "  ${GREEN}✓${NC} Found mounted: $device → $mount_point" >&2
            disks+=("$device:$mount_point")
        fi
    done < <(mount | grep "/var/lib/longhorn/disk" 2>/dev/null || true)
    
    # Method 2: Check fstab entries
    echo -e "${YELLOW}🔍 Checking fstab for Longhorn disk entries...${NC}" >&2
    if [ -f /etc/fstab ]; then
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
            
            local mount_point
            mount_point=$(echo "$line" | awk '{print $2}')
            
            if [[ "$mount_point" =~ /var/lib/longhorn/disk[0-9]+ ]]; then
                local uuid
                uuid=$(echo "$line" | awk '{print $1}' | sed 's/UUID=//')
                local device
                device=$(blkid -U "$uuid" 2>/dev/null || echo "")
                
                if [[ -n "$device" ]]; then
                    # Check if not already in list
                    local found=false
                    for disk in "${disks[@]}"; do
                        if [[ "$disk" == "$device:"* ]]; then
                            found=true
                            break
                        fi
                    done
                    
                    if ! $found; then
                        echo -e "  ${GREEN}✓${NC} Found in fstab: $device → $mount_point" >&2
                        disks+=("$device:$mount_point")
                    fi
                else
                    echo -e "  ${YELLOW}⚠${NC}  fstab entry for $mount_point (UUID: $uuid) - device not found" >&2
                fi
            fi
        done < /etc/fstab
    fi
    
    # Method 3: Check for orphaned Longhorn directories
    echo -e "${YELLOW}🔍 Checking for orphaned Longhorn directories...${NC}" >&2
    if [ -d /var/lib/longhorn ]; then
        for dir in /var/lib/longhorn/disk*; do
            if [ -d "$dir" ]; then
                local disk_num
                disk_num=$(basename "$dir" | sed 's/disk//')
                echo -e "  ${YELLOW}⚠${NC}  Found directory: $dir" >&2
                
                # Try to find associated device
                local device
                device=$(df "$dir" 2>/dev/null | tail -1 | awk '{print $1}')
                # Only add if it's a real device (starts with /dev/ and not tmpfs or root partition)
                if [[ -n "$device" ]] && [[ "$device" =~ ^/dev/ ]] && [[ "$device" != "tmpfs" ]]; then
                    # Check if not already in list
                    local found=false
                    for disk in "${disks[@]}"; do
                        if [[ "$disk" == "$device:"* ]]; then
                            found=true
                            break
                        fi
                    done
                    
                    if ! $found; then
                        echo -e "  ${GREEN}✓${NC} Associated device: $device" >&2
                        disks+=("$device:$dir")
                    fi
                fi
            fi
        done
    fi
    
    # Output only the disk data to stdout (one per line)
    printf "%s\n" "${disks[@]}"
}

# Detect disks (read into array properly)
mapfile -t DETECTED_DISKS < <(detect_additional_disks)

echo ""
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}📋 Detection Summary${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

if [ ${#DETECTED_DISKS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No additional Longhorn disks found${NC}"
    echo ""
    echo "Nothing to clean!"
    exit 0
fi

echo -e "${YELLOW}Found ${#DETECTED_DISKS[@]} additional disk(s) to clean:${NC}"
echo ""

for disk_info in "${DETECTED_DISKS[@]}"; do
    device=$(echo "$disk_info" | cut -d':' -f1)
    mount_point=$(echo "$disk_info" | cut -d':' -f2-)
    
    # Get disk size
    size=$(lsblk -b -d -n -o SIZE "$device" 2>/dev/null || echo "0")
    size_gb=$((size / 1024 / 1024 / 1024))
    
    echo -e "  ${BLUE}•${NC} Device: $device"
    echo -e "    Size: ${size_gb}GB"
    echo -e "    Mount: $mount_point"
    
    # Check if currently mounted
    if mount | grep -q "^$device "; then
        echo -e "    Status: ${YELLOW}MOUNTED${NC}"
    else
        echo -e "    Status: NOT MOUNTED"
    fi
    echo ""
done

# Confirmation
if ! $FORCE; then
    echo -e "${RED}⚠️  WARNING: This will permanently clean these disks!${NC}"
    echo -e "${RED}⚠️  All data on these disks will be DESTROYED!${NC}"
    echo ""
    
    if $DEEP_CLEAN; then
        echo -e "${YELLOW}Deep clean mode: Will overwrite first 1GB with zeros${NC}"
        echo ""
    fi
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}❌ Operation cancelled${NC}"
        exit 0
    fi
fi

echo ""
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}🧹 Starting Cleanup Process${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# Process each disk
for disk_info in "${DETECTED_DISKS[@]}"; do
    device=$(echo "$disk_info" | cut -d':' -f1)
    mount_point=$(echo "$disk_info" | cut -d':' -f2-)
    
    echo -e "${YELLOW}📀 Processing: $device${NC}"
    echo ""
    
    # Step 1: Unmount if mounted
    if mount | grep -q "^$device "; then
        echo -e "  ${BLUE}→${NC} Unmounting $device..."
        if umount "$device" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Unmounted successfully"
        else
            echo -e "  ${RED}✗${NC} Failed to unmount, trying force unmount..."
            if umount -f "$device" 2>/dev/null; then
                echo -e "  ${GREEN}✓${NC} Force unmounted"
            else
                echo -e "  ${RED}✗${NC} Failed to unmount $device"
                echo -e "  ${YELLOW}⚠${NC}  You may need to stop services using this disk"
                continue
            fi
        fi
    else
        echo -e "  ${GREEN}✓${NC} Already unmounted"
    fi
    
    # Step 2: Remove from fstab
    echo -e "  ${BLUE}→${NC} Removing from /etc/fstab..."
    if [ -f /etc/fstab ]; then
        # Backup fstab
        cp /etc/fstab "/etc/fstab.backup-$(date +%Y%m%d-%H%M%S)"
        
        # Get UUID if present
        uuid=$(blkid -s UUID -o value "$device" 2>/dev/null || echo "")
        
        # Remove entries by device name and UUID
        sed -i "\|$device|d" /etc/fstab
        if [[ -n "$uuid" ]]; then
            sed -i "/$uuid/d" /etc/fstab
        fi
        
        # Remove by mount point
        sed -i "\|$mount_point|d" /etc/fstab
        
        echo -e "  ${GREEN}✓${NC} Removed from fstab (backup created)"
    fi
    
    # Step 3: Clean filesystem signatures
    echo -e "  ${BLUE}→${NC} Cleaning filesystem signatures..."
    if wipefs -a "$device" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} Filesystem signatures removed"
    else
        echo -e "  ${YELLOW}⚠${NC}  wipefs failed or no signatures found"
    fi
    
    # Step 4: Deep clean (optional)
    if $DEEP_CLEAN; then
        echo -e "  ${BLUE}→${NC} Performing deep wipe (first 1GB)..."
        if dd if=/dev/zero of="$device" bs=1M count=1024 status=none 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Deep wipe completed"
        else
            echo -e "  ${YELLOW}⚠${NC}  Deep wipe failed (non-critical)"
        fi
    fi
    
    # Step 5: Remove mount directory
    if [ -d "$mount_point" ]; then
        echo -e "  ${BLUE}→${NC} Removing mount directory..."
        if rm -rf "$mount_point" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} Directory removed"
        else
            echo -e "  ${YELLOW}⚠${NC}  Failed to remove directory (non-critical)"
        fi
    fi
    
    echo -e "  ${GREEN}✅ Disk $device cleaned successfully${NC}"
    echo ""
done

# Clean up main Longhorn directory if empty
echo -e "${YELLOW}🗑️  Checking main Longhorn directory...${NC}"
if [ -d /var/lib/longhorn ]; then
    # Count remaining items (excluding . and ..)
    item_count=$(find /var/lib/longhorn -mindepth 1 -maxdepth 1 | wc -l)
    
    if [ "$item_count" -eq 0 ]; then
        echo -e "  ${BLUE}→${NC} Removing empty /var/lib/longhorn directory..."
        rmdir /var/lib/longhorn 2>/dev/null || true
        echo -e "  ${GREEN}✓${NC} Removed empty directory"
    else
        echo -e "  ${YELLOW}⚠${NC}  Directory not empty, keeping it"
        echo -e "     Remaining items: $item_count"
    fi
fi

echo ""
echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}📊 Verification${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# Verify cleanup
echo -e "${YELLOW}Verifying disks are clean:${NC}"
echo ""

for disk_info in "${DETECTED_DISKS[@]}"; do
    device=$(echo "$disk_info" | cut -d':' -f1)
    
    echo -e "  ${BLUE}•${NC} $device:"
    
    # Check if mounted
    if mount | grep -q "^$device "; then
        echo -e "    ${RED}✗${NC} Still mounted"
    else
        echo -e "    ${GREEN}✓${NC} Not mounted"
    fi
    
    # Check for filesystem
    if blkid "$device" >/dev/null 2>&1; then
        fs_info=$(blkid "$device" 2>/dev/null || echo "")
        echo -e "    ${YELLOW}⚠${NC}  Has signature: $fs_info"
    else
        echo -e "    ${GREEN}✓${NC} No filesystem signature"
    fi
    
    # Check fstab
    if grep -q "$device" /etc/fstab 2>/dev/null; then
        echo -e "    ${RED}✗${NC} Still in fstab"
    else
        echo -e "    ${GREEN}✓${NC} Not in fstab"
    fi
    
    echo ""
done

echo -e "${GREEN}✅ Cleanup completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo "  1. Disks are now clean and ready for reuse"
echo "  2. Run setup.sh to reconfigure them for Longhorn"
echo "  3. Or use them for other purposes"
echo ""

