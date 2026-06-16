#!/usr/bin/env bash

# region 27.5) Longhorn Multi-Disk Detection and Setup
info "🗄️  Detecting and configuring additional disks for Longhorn..."

# Function to detect disk type (SSD/HDD/NVME)
detect_disk_type() {
    local disk="$1"
    
    # Validate input
    if [[ -z "$disk" ]]; then
        echo "disk"
        return 1
    fi
    
    local device_name=$(basename "$disk" 2>/dev/null)
    if [[ -z "$device_name" ]]; then
        echo "disk"
        return 1
    fi
    
    # Check if it's NVMe
    if [[ "$device_name" =~ ^nvme ]]; then
        echo "nvme"
        return 0
    fi
    
    # Check rotational flag (0=SSD/NVMe, 1=HDD)
    if [ -f "/sys/block/$device_name/queue/rotational" ]; then
        local rotational=$(cat "/sys/block/$device_name/queue/rotational" 2>/dev/null | tr -d '[:space:]')
        if [[ "$rotational" == "0" ]]; then
            echo "ssd"
            return 0
        elif [[ "$rotational" == "1" ]]; then
            echo "hdd"
            return 0
        fi
    fi
    
    # Fallback: use lsblk
    local rota=$(lsblk -d -n -o ROTA "$disk" 2>/dev/null | head -1 | tr -d '[:space:]')
    if [[ "$rota" == "0" ]]; then
        echo "ssd"
    elif [[ "$rota" == "1" ]]; then
        echo "hdd"
    else
        # Unknown, default to "disk"
        echo "disk"
    fi
}

# Function to get disk size in GB
get_disk_size_gb() {
    local disk="$1"
    
    # Validate input
    if [[ -z "$disk" ]]; then
        echo "0"
        return 1
    fi
    
    local size_bytes=$(lsblk -b -d -n -o SIZE "$disk" 2>/dev/null | head -1 | tr -d '[:space:]')
    
    if [[ -n "$size_bytes" ]] && [[ "$size_bytes" =~ ^[0-9]+$ ]]; then
        # Convert to GB
        echo $((size_bytes / 1024 / 1024 / 1024))
    else
        echo "0"
    fi
}

# Function to detect available disks
detect_available_disks() {
    local available_disks=()
    
    # Get all block devices that are disks (not partitions)
    while IFS= read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        local type=$(echo "$line" | awk '{print $6}')
        local size=$(echo "$line" | awk '{print $4}')
        local mountpoint=$(echo "$line" | awk '{print $7}')
        
        # Skip if not a disk
        if [[ "$type" != "disk" ]]; then
            continue
        fi
        
        # Skip if disk itself is mounted (check more robustly)
        if [[ -n "$mountpoint" ]]; then
            debug "Skipping disk $device (mounted at $mountpoint)"
            continue
        fi
        
        # Additional check: use lsblk with full path to detect any mount
        if lsblk -no MOUNTPOINT "/dev/$device" 2>/dev/null | grep -q '^/'; then
            debug "Skipping disk $device (has mounted filesystem)"
            continue
        fi
        
        # Skip very small disks (less than 10GB)
        local size_num=$(echo "$size" | sed 's/[^0-9.]//g')
        local size_unit=$(echo "$size" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
        
        # Validate size_num is not empty
        if [[ -z "$size_num" ]]; then
            debug "Skipping disk $device (invalid size: $size)"
            continue
        fi
        
        # Convert to GB for comparison
        local size_gb=0
        case "$size_unit" in
            *T*) size_gb=$(echo "$size_num * 1000" | bc -l 2>/dev/null || echo "$(awk "BEGIN {print $size_num * 1000}" 2>/dev/null || echo "1000")") ;;
            *G*) size_gb=$(echo "$size_num" | bc -l 2>/dev/null || echo "$size_num") ;;
            *M*) size_gb=$(echo "$size_num / 1000" | bc -l 2>/dev/null || echo "$(awk "BEGIN {print $size_num / 1000}" 2>/dev/null || echo "0")") ;;
            *) size_gb=0 ;;
        esac
        
        # Ensure size_gb is numeric
        size_gb=$(echo "$size_gb" | tr -d '[:space:]')
        if ! [[ "$size_gb" =~ ^[0-9.]+$ ]]; then
            debug "Skipping disk $device (invalid size_gb: $size_gb)"
            continue
        fi
        
        if (( $(echo "$size_gb < 10" | bc -l 2>/dev/null || awk "BEGIN {print ($size_gb < 10 ? 1 : 0)}" 2>/dev/null || echo "1") )); then
            debug "Skipping small disk $device ($size)"
            continue
        fi
        
        # Check if disk has partitions in use
        local has_mounted_partitions=false
        while IFS= read -r part_line; do
            local part_mount=$(echo "$part_line" | awk '{print $7}')
            if [[ -n "$part_mount" ]]; then
                has_mounted_partitions=true
                break
            fi
        done < <(lsblk -ln "/dev/$device" 2>/dev/null | grep part || true)
        
        if [[ "$has_mounted_partitions" == "true" ]]; then
            debug "Skipping disk $device (has mounted partitions)"
            continue
        fi
        
        # This disk appears to be available
        available_disks+=("/dev/$device")
        debug "Found available disk: /dev/$device ($size)"
        
    done < <(lsblk -ln -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,MOUNTPOINT | grep disk)
    
    echo "${available_disks[@]}"
}

# Function to check if a disk is safe to use
is_disk_safe_to_use() {
    local disk="$1"
    
    # Validate input
    if [[ -z "$disk" ]]; then
        debug "Empty disk parameter"
        return 1
    fi
    
    # Check if disk is currently mounted  
    if mount | grep -qF "$disk "; then
        debug "Disk $disk is currently mounted"
        return 1
    fi
    
    # Check with lsblk for any mountpoint
    if lsblk -no MOUNTPOINT "$disk" 2>/dev/null | grep -q '^/'; then
        debug "Disk $disk has mounted filesystem"
        return 1
    fi
    
    # Check if disk has any filesystem signatures
    if blkid "$disk" >/dev/null 2>&1; then
        local fs_type=$(blkid -s TYPE -o value "$disk" 2>/dev/null | tr -d '[:space:]' || echo "")
        if [[ -n "$fs_type" ]]; then
            debug "Disk $disk has filesystem: $fs_type"
            return 1
        fi
    fi
    
    # Check if disk has partition table
    if sfdisk -l "$disk" 2>/dev/null | grep -q "Disklabel type:"; then
        debug "Disk $disk has partition table"
        return 1
    fi
    
    # Check if disk is referenced in fstab (use -F for fixed string)
    if grep -qF "$disk" /etc/fstab 2>/dev/null; then
        debug "Disk $disk referenced in fstab"
        return 1
    fi
    
    # Check if disk UUID is in fstab
    local disk_uuid=$(blkid -s UUID -o value "$disk" 2>/dev/null | tr -d '[:space:]' || echo "")
    if [[ -n "$disk_uuid" ]] && grep -qF "$disk_uuid" /etc/fstab 2>/dev/null; then
        debug "Disk $disk UUID ($disk_uuid) referenced in fstab"
        return 1
    fi
    
    return 0
}

# Function to initialize a disk for Longhorn
initialize_disk_for_longhorn() {
    local disk="$1"
    local mount_path="$2"
    local label="$3"
    
    info "Initializing disk $disk for Longhorn..."
    
    # Create ext4 filesystem
    if run_cmd "mkfs.ext4 -F -L \"$label\" \"$disk\"" "Creating ext4 filesystem on $disk"; then
        ok "Filesystem created on $disk"
    else
        err "Failed to create filesystem on $disk"
        return 1
    fi
    
    # Force kernel to refresh partition table
    debug "Refreshing partition table for $disk"
    partprobe "$disk" 2>/dev/null || true
    blockdev --rereadpt "$disk" 2>/dev/null || true
    udevadm settle 2>/dev/null || sleep 2
    
    # Create mount directory
    run_cmd "mkdir -p \"$mount_path\"" "Creating mount directory $mount_path"
    
    # Get UUID for fstab entry with retries
    local uuid=""
    local retry_count=0
    while [[ -z "$uuid" ]] && [[ $retry_count -lt 5 ]]; do
        sleep 1
        uuid=$(blkid -s UUID -o value "$disk" 2>/dev/null | tr -d '[:space:]' || true)
        retry_count=$((retry_count + 1))
        if [[ -z "$uuid" ]]; then
            debug "UUID not found, retrying ($retry_count/5)..."
        fi
    done
    
    if [[ -z "$uuid" ]]; then
        err "Unable to get UUID for $disk after $retry_count attempts"
        return 1
    fi
    
    ok "Retrieved UUID: $uuid"
    
    # Add to fstab if not present
    if ! grep -q "$uuid" /etc/fstab; then
        info "Adding fstab entry for $disk"
        echo "UUID=$uuid $mount_path ext4 defaults,noatime 0 2" >> /etc/fstab
        ok "Added fstab entry"
    else
        info "fstab entry already exists for $disk"
    fi
    
    # Mount the disk
    if run_cmd "mount \"$mount_path\"" "Mounting $disk at $mount_path"; then
        ok "Disk mounted successfully"
    else
        err "Failed to mount $disk"
        return 1
    fi
    
    # Prepare Longhorn directory structure
    # Note: Longhorn will create its own subdirectories, we just need the mount point
    run_cmd "chown -R root:root \"$mount_path\"" "Setting ownership"
    run_cmd "chmod 755 \"$mount_path\"" "Setting permissions"
    
    ok "Disk $disk initialized and ready for Longhorn"
    return 0
}

# Function to add disk to Longhorn node
add_disk_to_longhorn_node() {
    local mount_path="$1"
    local disk_name="$2"
    local disk_type="$3"
    local disk_size="$4"
    
    info "Adding disk to Longhorn node configuration..."
    
    # Wait for Longhorn to be ready (check both nodes and manager pods)
    local wait_count=0
    local max_wait=60  # 10 minutes total
    
    while [[ $wait_count -lt $max_wait ]]; do
        # Check if Longhorn nodes exist
        if ! microk8s kubectl get nodes.longhorn.io -n longhorn-system >/dev/null 2>&1; then
            debug "Waiting for Longhorn nodes to be created... ($wait_count/$max_wait)"
            wait_count=$((wait_count + 1))
            sleep 10
            continue
        fi
        
        # Check if Longhorn manager pods are ready
        local ready_managers=$(microk8s kubectl get pods -n longhorn-system -l app=longhorn-manager -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l | tr -d ' ')
        if [[ "$ready_managers" -ge 1 ]]; then
            ok "Longhorn is ready (manager pods: $ready_managers)"
            break
        fi
        
        debug "Waiting for Longhorn to be fully ready... ($wait_count/$max_wait, managers ready: $ready_managers)"
        wait_count=$((wait_count + 1))
        sleep 10
    done
    
    if [[ $wait_count -ge $max_wait ]]; then
        warn "Longhorn not fully ready after 10 minutes, skipping disk addition"
        info "You can add the disk manually later"
        return 1
    fi
    
    # Additional wait to ensure Longhorn node is fully initialized
    info "Waiting extra 30 seconds for Longhorn node initialization..."
    sleep 30
    
    # Get current node name
    local node_name=$(hostname)
    
    # Check if Longhorn node exists and is ready
    if ! microk8s kubectl get nodes.longhorn.io -n longhorn-system "$node_name" >/dev/null 2>&1; then
        warn "Longhorn node $node_name not found"
        return 1
    fi
    
    # Verify node is ready
    local node_ready=$(microk8s kubectl get nodes.longhorn.io -n longhorn-system "$node_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | tr -d '[:space:]')
    if [[ "$node_ready" != "True" ]]; then
        warn "Longhorn node $node_name is not ready yet (status: $node_ready)"
        return 1
    fi
    
    # Add disk to Longhorn node
    info "Adding disk $disk_name ($disk_type, ${disk_size}GB) to Longhorn node $node_name"
    
    # Build tags based on disk type
    local tags_json="[\"$disk_type\", \"additional\"]"
    
    # Calculate optimal storage reservation for additional disk
    # Formula: min(30% of disk, 128GB max)
    local disk_size_bytes=$((disk_size * 1024 * 1024 * 1024))
    local thirty_percent=$((disk_size_bytes * 30 / 100))
    local max_reserved=$((128 * 1024 * 1024 * 1024))  # 128GB in bytes
    
    local optimal_reserved
    if [[ $thirty_percent -lt $max_reserved ]]; then
        optimal_reserved=$thirty_percent
        local reserved_gb=$((optimal_reserved / 1024 / 1024 / 1024))
        debug "Additional disk reservation: 30% = ${reserved_gb}GB"
    else
        optimal_reserved=$max_reserved
        debug "Additional disk reservation: capped at 128GB"
    fi
    
    # Build JSON patch more carefully to avoid escaping issues
    local json_patch
    json_patch=$(cat <<EOF
{
  "spec": {
    "disks": {
      "$disk_name": {
        "path": "$mount_path",
        "allowScheduling": true,
        "evictionRequested": false,
        "storageReserved": $optimal_reserved,
        "tags": $tags_json
      }
    }
  }
}
EOF
)
    
    # Apply disk configuration using kubectl patch
    local patch_output="/tmp/longhorn-patch-output-$$.log"
    if echo "$json_patch" | microk8s kubectl patch nodes.longhorn.io -n longhorn-system "$node_name" --type='merge' --patch-file=/dev/stdin 2>&1 | tee "$patch_output" | grep -q "patched\|unchanged"; then
        ok "Disk $disk_name added to Longhorn node $node_name"
        
        # Verify the disk was added
        info "Verifying disk addition..."
        sleep 5
        
        # Check if jq is available for verification
        if command -v jq >/dev/null 2>&1; then
            # Use JSONPath with proper escaping for disk names with hyphens
            if microk8s kubectl get nodes.longhorn.io -n longhorn-system "$node_name" -o json 2>/dev/null | jq -e ".spec.disks.\"$disk_name\" // empty" >/dev/null 2>&1; then
                ok "Disk $disk_name verified in Longhorn configuration"
                rm -f "$patch_output" 2>/dev/null || true
                return 0
            else
                warn "Disk appears to be added but verification failed"
                rm -f "$patch_output" 2>/dev/null || true
                return 0
            fi
        else
            # Fallback: just trust the patch succeeded
            info "jq not available, skipping verification (disk should be added)"
            rm -f "$patch_output" 2>/dev/null || true
            return 0
        fi
    else
        warn "Failed to add disk to Longhorn node"
        info "Error output:"
        cat "$patch_output" 2>/dev/null || true
        rm -f "$patch_output" 2>/dev/null || true
        info "Manual configuration:"
        info "  1. Access Longhorn UI"
        info "  2. Go to Node -> $node_name"
        info "  3. Add disk: $mount_path"
        return 1
    fi
}

# Main multi-disk detection and setup
if [[ "${IS_PRIMARY_NODE:-false}" == "true" ]] || [[ "${IS_SECONDARY_NODE:-false}" == "true" ]]; then
    # Only run on nodes that will have Longhorn (skip if Jetson without Longhorn)
    if [[ "${IS_JETSON:-false}" == "true" ]]; then
        info "Jetson system detected - skipping multi-disk setup (Longhorn not installed on Jetson)"
    else
        info "Detecting additional disks for Longhorn storage..."
        
        # Detect available disks
        available_disks=($(detect_available_disks))
        
        if [[ ${#available_disks[@]} -eq 0 ]]; then
            info "No additional disks detected - using default Longhorn configuration"
        else
            info "Found ${#available_disks[@]} additional disk(s): ${available_disks[*]}"
            
            # Process each additional disk
            disk_counter=2
            disks_successfully_added=0
            for disk in "${available_disks[@]}"; do
                # Detect disk type and size
                disk_type=$(detect_disk_type "$disk")
                disk_size=$(get_disk_size_gb "$disk")
                
                info "Processing disk: $disk (Type: $disk_type, Size: ${disk_size}GB)"
                
                # Check if disk is safe to use
                if is_disk_safe_to_use "$disk"; then
                    info "Disk $disk appears to be unused and safe to initialize"
                    
                    # Ask for confirmation in interactive mode
                    if $INTERACTIVE; then
                        echo ""
                        warn "⚠️  About to initialize disk: $disk"
                        warn "Type: $disk_type | Size: ${disk_size}GB"
                        warn "This will DESTROY any existing data on the disk!"
                        echo ""
                        read -rp "Initialize $disk for Longhorn? [y/N]: " confirm
                        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
                            info "Skipping disk $disk"
                            continue
                        fi
                    else
                        info "Non-interactive mode: auto-initializing disk $disk"
                    fi
                    
                    # Initialize disk
                    mount_path="/var/lib/longhorn/disk$disk_counter"
                    label="LH$disk_counter"
                    # Create disk name with type prefix for clarity
                    disk_name="${disk_type}-disk${disk_counter}"
                    
                    if initialize_disk_for_longhorn "$disk" "$mount_path" "$label"; then
                        ok "Disk $disk initialized successfully"
                        
                        # Add to Longhorn immediately (for primary nodes)
                        if [[ "${IS_PRIMARY_NODE:-false}" == "true" ]]; then
                            info "Adding disk to Longhorn now..."
                            if add_disk_to_longhorn_node "$mount_path" "$disk_name" "$disk_type" "$disk_size"; then
                                ok "Disk successfully added to Longhorn"
                                disks_successfully_added=$((disks_successfully_added + 1))
                            else
                                warn "Could not add disk to Longhorn automatically"
                                info "You can add it manually later via Longhorn UI or kubectl"
                            fi
                        fi
                        
                        disk_counter=$((disk_counter + 1))
                    else
                        err "Failed to initialize disk $disk"
                    fi
                else
                    warn "Disk $disk appears to have data or is in use - skipping for safety"
                    info "If you want to use this disk, manually run:"
                    info "  sudo wipefs -a $disk"
                    info "  sudo ./add-ssd-to-longhorn.sh --device $disk --mount-path /var/lib/longhorn/disk$disk_counter"
                fi
            done
            
            if [[ $disks_successfully_added -gt 0 ]]; then
                ok "Successfully added $disks_successfully_added additional disk(s) to Longhorn"
                info "Longhorn will use multiple disks for improved performance and redundancy"
                info "Each disk can store replicas independently"
            elif [[ $disk_counter -gt 2 ]]; then
                info "Initialized $((disk_counter - 2)) disk(s) but could not add them to Longhorn automatically"
                info "You may need to add them manually via Longhorn UI"
            fi
        fi
    fi
else
    debug "Skipping multi-disk setup (not a cluster node)"
fi

# endregion 27.5) Longhorn Multi-Disk Detection and Setup
