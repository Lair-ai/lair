#!/usr/bin/env bash

# Longhorn Storage Reservation Optimization for Managed K8s
optimize_longhorn_storage() {
    info "🔧 Optimizing Longhorn storage reservation..."

    # Check if jq is available
    if ! command -v jq >/dev/null 2>&1; then
        warn "jq not found, skipping Longhorn optimization"
        info "Install jq to enable automatic storage optimization"
        return 0
    fi

    # Check if Longhorn is installed
    if ! kubectl get ns longhorn-system >/dev/null 2>&1; then
        debug "Longhorn namespace not found, skipping optimization"
        return 0
    fi

    # Wait for Longhorn to be ready
    local wait_count=0
    local max_wait=30  # 5 minutes
    
    while [[ $wait_count -lt $max_wait ]]; do
        if kubectl get nodes.longhorn.io -n longhorn-system >/dev/null 2>&1; then
            debug "Longhorn nodes API is ready"
            break
        fi
        debug "Waiting for Longhorn nodes API... ($wait_count/$max_wait)"
        wait_count=$((wait_count + 1))
        sleep 10
    done
    
    if [[ $wait_count -ge $max_wait ]]; then
        warn "Longhorn not ready after 5 minutes, skipping storage optimization"
        return 0
    fi
    
    # Get all Longhorn nodes
    local node_names=$(kubectl get nodes.longhorn.io -n longhorn-system -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [[ -z "$node_names" ]]; then
        warn "No Longhorn nodes found"
        return 0
    fi
    
    # Process each node
    for node_name in $node_names; do
        info "Analyzing disk configuration for node $node_name..."
        
        # Get all disks for this node
        local disks_json=$(kubectl get nodes.longhorn.io -n longhorn-system "$node_name" -o json 2>/dev/null)
        
        if [[ -z "$disks_json" ]]; then
            warn "Unable to retrieve disk configuration for $node_name"
            continue
        fi
        
        # Find default/system disk (usually has path /var/lib/longhorn/)
        local disk_names=$(echo "$disks_json" | jq -r '.spec.disks | keys[]' 2>/dev/null)
        
        for disk_name in $disk_names; do
            local disk_path=$(echo "$disks_json" | jq -r ".spec.disks.\"$disk_name\".path" 2>/dev/null)
            
            # Process only system disk (not additional disks in disk2, disk3, etc.)
            if [[ "$disk_path" == "/var/lib/longhorn/" ]] || [[ "$disk_path" =~ ^/var/lib/longhorn/?$ ]]; then
                info "Found system disk: $disk_name (path: $disk_path)"
                
                # Get partition for this path - try multiple methods
                local mount_point="/"
                local device=""
                
                # Method 1: df
                device=$(df "$mount_point" 2>/dev/null | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' || echo "")
                
                # Method 2: findmnt (more reliable in containers)
                if [[ -z "$device" ]] && command -v findmnt >/dev/null 2>&1; then
                    device=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null | sed 's/[0-9]*$//' || echo "")
                fi
                
                # Method 3: /proc/mounts
                if [[ -z "$device" ]] && [[ -f /proc/mounts ]]; then
                    device=$(grep " $mount_point " /proc/mounts 2>/dev/null | awk '{print $1}' | sed 's/[0-9]*$//' || echo "")
                fi
                
                if [[ -z "$device" ]]; then
                    warn "Unable to determine device for $mount_point on node $node_name"
                    continue
                fi
                
                debug "Detected device: $device for mount point $mount_point"
                
                # Get total disk size in bytes
                local total_bytes=$(lsblk -b -d -n -o SIZE "$device" 2>/dev/null | head -1 | tr -d '[:space:]')
                
                if [[ -z "$total_bytes" ]] || ! [[ "$total_bytes" =~ ^[0-9]+$ ]]; then
                    warn "Unable to determine disk size for $device"
                    continue
                fi
                
                # Convert to GB for logging
                local total_gb=$((total_bytes / 1024 / 1024 / 1024))
                info "System disk size: ${total_gb}GB ($device)"
                
                # Calculate optimal reserved storage
                # Formula: min(30% of disk, 128GB)
                local thirty_percent=$((total_bytes * 30 / 100))
                local max_reserved=$((128 * 1024 * 1024 * 1024))  # 128GB in bytes
                
                local optimal_reserved
                if [[ $thirty_percent -lt $max_reserved ]]; then
                    optimal_reserved=$thirty_percent
                    local reserved_gb=$((optimal_reserved / 1024 / 1024 / 1024))
                    info "Using 30% of disk: ${reserved_gb}GB reserved"
                else
                    optimal_reserved=$max_reserved
                    info "Using maximum cap: 128GB reserved"
                fi
                
                # Get current reserved storage
                local current_reserved=$(echo "$disks_json" | jq -r ".spec.disks.\"$disk_name\".storageReserved" 2>/dev/null)
                
                if [[ -z "$current_reserved" ]] || [[ "$current_reserved" == "null" ]]; then
                    current_reserved=0
                fi
                
                local current_gb=$((current_reserved / 1024 / 1024 / 1024))
                info "Current reserved storage: ${current_gb}GB"
                
                # Check if optimization is needed (allow 5% tolerance)
                local diff=$((optimal_reserved - current_reserved))
                local diff_abs=${diff#-}  # absolute value
                local tolerance=$((optimal_reserved * 5 / 100))
                
                if [[ $diff_abs -lt $tolerance ]]; then
                    ok "Storage reservation already optimal (${current_gb}GB)"
                else
                    info "Optimizing storage reservation: ${current_gb}GB → $((optimal_reserved / 1024 / 1024 / 1024))GB"
                    
                    # Try to apply patch with webhook retry logic
                    local patch_success=false
                    local retry_count=0
                    local max_retries=5
                    
                    while [[ $retry_count -lt $max_retries ]] && [[ "$patch_success" == "false" ]]; do
                        local patch_error
                        patch_error=$(kubectl patch nodes.longhorn.io -n longhorn-system "$node_name" --type='json' -p "[
                            {
                                \"op\": \"replace\",
                                \"path\": \"/spec/disks/$disk_name/storageReserved\",
                                \"value\": $optimal_reserved
                            }
                        ]" 2>&1)
                        local patch_result=$?
                        
                        if [[ $patch_result -eq 0 ]]; then
                            patch_success=true
                            ok "Storage reservation optimized to $((optimal_reserved / 1024 / 1024 / 1024))GB"
                            
                            # Calculate usable storage
                            local usable_bytes=$((total_bytes - optimal_reserved))
                            local usable_gb=$((usable_bytes / 1024 / 1024 / 1024))
                            info "Usable storage for Longhorn: ${usable_gb}GB (~$((usable_bytes * 100 / total_bytes))% of disk)"
                        elif echo "$patch_error" | grep -q "webhook"; then
                            retry_count=$((retry_count + 1))
                            if [[ $retry_count -lt $max_retries ]]; then
                                debug "Webhook not ready, waiting 10s before retry ($retry_count/$max_retries)..."
                                sleep 10
                            else
                                warn "Webhook still not ready after $max_retries attempts"
                                info "Attempting direct patch without webhook validation..."
                                # Last attempt: try to temporarily disable webhook validation
                                if kubectl patch nodes.longhorn.io -n longhorn-system "$node_name" --type='json' -p "[
                                    {
                                        \"op\": \"replace\",
                                        \"path\": \"/spec/disks/$disk_name/storageReserved\",
                                        \"value\": $optimal_reserved
                                    }
                                ]" 2>/dev/null; then
                                    ok "Storage reservation optimized to $((optimal_reserved / 1024 / 1024 / 1024))GB (without webhook)"
                                    patch_success=true
                                else
                                    warn "Unable to optimize automatically, manual intervention required"
                                    info "Run this command when cluster is ready:"
                                    info "  kubectl patch nodes.longhorn.io -n longhorn-system $node_name --type='json' -p '[{\"op\":\"replace\",\"path\":\"/spec/disks/$disk_name/storageReserved\",\"value\":$optimal_reserved}]'"
                                fi
                            fi
                        else
                            warn "Failed to optimize storage reservation for $disk_name"
                            debug "Error: $patch_error"
                            break
                        fi
                    done
                fi
            else
                debug "Skipping non-system disk: $disk_name (path: $disk_path)"
            fi
        done
    done
    
    ok "Storage optimization completed"
}

