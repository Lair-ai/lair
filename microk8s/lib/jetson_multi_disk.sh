#!/usr/bin/env bash

# region 24.5) Jetson Multi-Disk Detection and Setup for Hostpath Storage
info "🗄️  Jetson: Detecting and configuring additional disks for hostpath storage..."

# Function to detect available disks (reuse from longhorn_multi_disk.sh)
detect_available_disks_jetson() {
    local available_disks=()
    
    # Get all block devices that are disks (not partitions)
    while IFS= read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        local type=$(echo "$line" | awk '{print $6}')
        local size=$(echo "$line" | awk '{print $4}')
        local mountpoint=$(echo "$line" | awk '{print $7}')
        
        # Skip if not a disk or if already mounted
        if [[ "$type" != "disk" ]] || [[ -n "$mountpoint" ]]; then
            continue
        fi
        
        # Skip very small disks (less than 10GB)
        local size_num=$(echo "$size" | sed 's/[^0-9.]//g')
        local size_unit=$(echo "$size" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
        
        # Convert to GB for comparison
        local size_gb=0
        case "$size_unit" in
            *T*) size_gb=$(echo "$size_num * 1000" | bc -l 2>/dev/null || echo "1000") ;;
            *G*) size_gb=$(echo "$size_num" | bc -l 2>/dev/null || echo "$size_num") ;;
            *M*) size_gb=$(echo "$size_num / 1000" | bc -l 2>/dev/null || echo "0") ;;
            *) size_gb=0 ;;
        esac
        
        if (( $(echo "$size_gb < 10" | bc -l 2>/dev/null || echo "1") )); then
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

# Function to check if a disk is safe to use (reuse from longhorn_multi_disk.sh)
is_disk_safe_to_use_jetson() {
    local disk="$1"
    
    # Check if disk has any filesystem signatures
    if blkid "$disk" >/dev/null 2>&1; then
        local fs_type=$(blkid -s TYPE -o value "$disk" 2>/dev/null || echo "")
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
    
    # Check if disk is referenced in fstab
    if grep -q "$disk" /etc/fstab 2>/dev/null; then
        debug "Disk $disk referenced in fstab"
        return 1
    fi
    
    return 0
}

# Function to initialize a disk for hostpath storage
initialize_disk_for_hostpath() {
    local disk="$1"
    local mount_path="$2"
    local label="$3"
    
    info "Initializing disk $disk for hostpath storage..."
    
    # Create ext4 filesystem
    if run_cmd "mkfs.ext4 -F -L \"$label\" \"$disk\"" "Creating ext4 filesystem on $disk"; then
        ok "Filesystem created on $disk"
    else
        err "Failed to create filesystem on $disk"
        return 1
    fi
    
    # Create mount directory
    run_cmd "mkdir -p \"$mount_path\"" "Creating mount directory $mount_path"
    
    # Get UUID for fstab entry
    local uuid=$(blkid -s UUID -o value "$disk" 2>/dev/null)
    if [[ -z "$uuid" ]]; then
        err "Unable to get UUID for $disk"
        return 1
    fi
    
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
    
    # Prepare hostpath directory structure
    run_cmd "mkdir -p \"$mount_path/hostpath\"" "Creating hostpath directory"
    run_cmd "chown -R root:root \"$mount_path\"" "Setting ownership"
    run_cmd "chmod 755 \"$mount_path\"" "Setting permissions"
    
    ok "Disk $disk initialized and ready for hostpath storage"
    return 0
}

# Function to create additional hostpath storage classes
create_additional_hostpath_storageclass() {
    local mount_path="$1"
    local storage_class_name="$2"
    local disk_name="$3"
    
    info "Creating additional hostpath storage class: $storage_class_name"
    
    # Wait for MicroK8s to be ready
    local wait_count=0
    while ! microk8s kubectl get storageclass >/dev/null 2>&1; do
        wait_count=$((wait_count + 1))
        if [[ $wait_count -gt 30 ]]; then
            warn "MicroK8s not ready after 5 minutes, skipping storage class creation"
            return 1
        fi
        debug "Waiting for MicroK8s to be ready... ($wait_count/30)"
        sleep 10
    done
    
    # Create storage class YAML
    local sc_yaml="/tmp/hostpath-${storage_class_name}.yaml"
    cat > "$sc_yaml" << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $storage_class_name
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    description: "Additional hostpath storage on $disk_name"
provisioner: microk8s.io/hostpath
parameters:
  pvDir: $mount_path/hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF
    
    # Apply storage class
    if microk8s kubectl apply -f "$sc_yaml" >/dev/null 2>&1; then
        ok "Storage class $storage_class_name created successfully"
        rm -f "$sc_yaml"
        return 0
    else
        warn "Failed to create storage class $storage_class_name"
        rm -f "$sc_yaml"
        return 1
    fi
}

# Function to create hostpath provisioner for additional disks
setup_additional_hostpath_provisioner() {
    local mount_path="$1"
    local provisioner_name="$2"
    
    info "Setting up hostpath provisioner for $mount_path"
    
    # Create provisioner deployment YAML
    local prov_yaml="/tmp/hostpath-provisioner-${provisioner_name}.yaml"
    cat > "$prov_yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hostpath-provisioner-$provisioner_name
  namespace: kube-system
  labels:
    app: hostpath-provisioner-$provisioner_name
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hostpath-provisioner-$provisioner_name
  template:
    metadata:
      labels:
        app: hostpath-provisioner-$provisioner_name
    spec:
      serviceAccountName: microk8s-hostpath
      containers:
      - name: hostpath-provisioner
        image: k8s.gcr.io/sig-storage/hostpath-provisioner:v3.0.0
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        volumeMounts:
        - name: pv-volume
          mountPath: $mount_path/hostpath
        command:
        - /hostpath-provisioner
        args:
        - -v=5
        - -provisioner=microk8s.io/hostpath-$provisioner_name
        - -pv-dir=$mount_path/hostpath
      volumes:
      - name: pv-volume
        hostPath:
          path: $mount_path/hostpath
          type: DirectoryOrCreate
      nodeSelector:
        kubernetes.io/hostname: $(hostname)
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: hostpath-$provisioner_name
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    description: "Hostpath storage on additional disk $provisioner_name"
provisioner: microk8s.io/hostpath-$provisioner_name
parameters:
  pvDir: $mount_path/hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF
    
    # Apply provisioner
    if microk8s kubectl apply -f "$prov_yaml" >/dev/null 2>&1; then
        ok "Hostpath provisioner for $provisioner_name created successfully"
        rm -f "$prov_yaml"
        return 0
    else
        warn "Failed to create hostpath provisioner for $provisioner_name"
        rm -f "$prov_yaml"
        return 1
    fi
}

# Main Jetson multi-disk detection and setup
if [[ "$IS_JETSON" == "true" ]]; then
    info "Jetson system: Detecting additional disks for hostpath storage..."
    
    # Detect available disks
    available_disks=($(detect_available_disks_jetson))
    
    if [[ ${#available_disks[@]} -eq 0 ]]; then
        info "No additional disks detected - using default hostpath configuration"
    else
        info "Found ${#available_disks[@]} additional disk(s): ${available_disks[*]}"
        
        # Process each additional disk
        disk_counter=2
        for disk in "${available_disks[@]}"; do
            info "Processing disk: $disk"
            
            # Check if disk is safe to use
            if is_disk_safe_to_use_jetson "$disk"; then
                info "Disk $disk appears to be unused and safe to initialize"
                
                # Ask for confirmation in interactive mode
                if $INTERACTIVE; then
                    echo ""
                    warn "⚠️  About to initialize disk: $disk"
                    warn "This will DESTROY any existing data on the disk!"
                    echo ""
                    read -rp "Initialize $disk for hostpath storage? [y/N]: " confirm
                    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
                        info "Skipping disk $disk"
                        continue
                    fi
                else
                    info "Non-interactive mode: auto-initializing disk $disk"
                fi
                
                # Initialize disk
                mount_path="/var/lib/hostpath/disk$disk_counter"
                label="HP$disk_counter"
                storage_class_name="hostpath-disk$disk_counter"
                
                if initialize_disk_for_hostpath "$disk" "$mount_path" "$label"; then
                    ok "Disk $disk initialized successfully"
                    
                    # Create storage class for this disk (only for primary nodes or after cluster join)
                    if [[ "${IS_PRIMARY_NODE:-false}" == "true" ]] || [[ "${IS_SECONDARY_NODE:-false}" == "true" ]]; then
                        # Schedule storage class creation after MicroK8s is fully ready
                        info "Storage class will be created after MicroK8s setup completes"
                        
                        # Create a script to add the storage class later
                        cat > "/tmp/add-hostpath-storage-$disk_counter.sh" << EOF
#!/bin/bash
# Auto-generated script to add hostpath storage class
sleep 30  # Wait for MicroK8s to be fully ready
echo "Creating hostpath storage class for disk$disk_counter..."

# Create storage class
cat > /tmp/hostpath-disk$disk_counter-sc.yaml << 'SCEOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $storage_class_name
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    description: "Hostpath storage on additional disk $disk_counter"
provisioner: microk8s.io/hostpath
parameters:
  pvDir: $mount_path/hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
SCEOF

if microk8s kubectl apply -f /tmp/hostpath-disk$disk_counter-sc.yaml; then
    echo "Storage class $storage_class_name created successfully"
    rm -f /tmp/hostpath-disk$disk_counter-sc.yaml
else
    echo "Failed to create storage class, manual configuration required"
fi
EOF
                        chmod +x "/tmp/add-hostpath-storage-$disk_counter.sh"
                    fi
                    
                    disk_counter=$((disk_counter + 1))
                else
                    err "Failed to initialize disk $disk"
                fi
            else
                warn "Disk $disk appears to have data or is in use - skipping for safety"
                info "If you want to use this disk, manually run:"
                info "  sudo wipefs -a $disk"
                info "  sudo ./add-ssd-to-hostpath.sh --device $disk --mount-path /var/lib/hostpath/disk$disk_counter"
            fi
        done
        
        if [[ $disk_counter -gt 2 ]]; then
            ok "Configured $((disk_counter - 2)) additional disk(s) for hostpath storage"
            info "Multiple hostpath storage classes will be available"
            info "Each disk provides independent storage capacity"
        fi
    fi
else
    debug "Not a Jetson system, skipping Jetson multi-disk setup"
fi

# endregion 24.5) Jetson Multi-Disk Detection and Setup for Hostpath Storage
