#!/usr/bin/env bash
set -euo pipefail

# add-ssd-to-hostpath.sh
# Formats (optional), mounts and registers a secondary SSD for hostpath storage on Jetson nodes.
# Usage examples:
#   sudo ./add-ssd-to-hostpath.sh --device /dev/sdb --mount-path /var/lib/hostpath/ssd2
#   sudo ./add-ssd-to-hostpath.sh --device /dev/nvme1n1 --filesystem ext4 --label HP2 --wipe --mount-path /var/lib/hostpath/ssd2
#   sudo ./add-ssd-to-hostpath.sh --device /dev/sdb --no-format --mount-path /var/lib/hostpath/ssd2

DEVICE=""
MOUNT_PATH="/var/lib/hostpath/ssd2"
FILESYSTEM="ext4"
LABEL="HP2"
NO_FORMAT=false
WIPE=false

log() { echo "[add-ssd-to-hostpath] $*"; }
err() { echo "[add-ssd-to-hostpath][ERROR] $*" >&2; }
usage() {
  cat <<EOF
Usage: $0 --device <block_device> [--mount-path <dir>] [--filesystem ext4|xfs] [--label <LBL>] [--no-format] [--wipe]

Options:
  --device        Block device path (e.g., /dev/sdb, /dev/nvme1n1) [required]
  --mount-path    Mount point directory (default: /var/lib/hostpath/ssd2)
  --filesystem    Filesystem to create if formatting (ext4 or xfs; default: ext4)
  --label         Filesystem label to set when formatting (default: HP2)
  --no-format     Do not format the device (assumes pre-formatted fs)
  --wipe          Wipe existing partition table (dangerous). Implies formatting.

Notes:
- Run as root (sudo)
- This script adds an additional hostpath disk on this Jetson node only. Repeat on each node.
- The disk will be automatically configured as a new hostpath storage class if possible.
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2;;
    --mount-path) MOUNT_PATH="$2"; shift 2;;
    --filesystem) FILESYSTEM="$2"; shift 2;;
    --label) LABEL="$2"; shift 2;;
    --no-format) NO_FORMAT=true; shift;;
    --wipe) WIPE=true; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown argument: $1"; usage; exit 1;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  err "--device is required"
  usage
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root (sudo)"
  exit 1
fi

if [[ ! -b "$DEVICE" ]]; then
  err "Device not found or not a block device: $DEVICE"
  exit 1
fi

# Ensure dependencies
need_bins=(lsblk blkid mkfs.ext4 mkdir mount grep sed awk tee)
if [[ "$FILESYSTEM" == "xfs" ]]; then
  need_bins+=(mkfs.xfs)
fi

for b in "${need_bins[@]}"; do
  if ! command -v "$b" >/dev/null 2>&1; then
    err "Missing dependency: $b"
    exit 1
  fi
done

# Optionally wipe existing partition table
if [[ "$WIPE" == true ]]; then
  log "Wiping existing partition table on $DEVICE (sgdisk -Z)"
  if command -v sgdisk >/dev/null 2>&1; then
    sgdisk -Z "$DEVICE"
  else
    err "sgdisk not found; install gdisk or run wipefs/parted manually"
    exit 1
  fi
  NO_FORMAT=false
fi

# Detect a suitable partition to use (prefer the device itself if it is not a whole-disk with partitions)
TARGET_PART="$DEVICE"

# If device has partitions, prefer first partition
if lsblk -no TYPE "$DEVICE" | grep -q disk; then
  first_part=$(lsblk -ln "$DEVICE" | awk '$2 ~ /part/ {print "/dev/"$1; exit}') || true
  if [[ -n "${first_part:-}" ]]; then
    TARGET_PART="$first_part"
  fi
fi

log "Target block: $TARGET_PART (mount -> $MOUNT_PATH)"

# Create filesystem if needed
if [[ "$NO_FORMAT" == false ]]; then
  if [[ "$FILESYSTEM" == "ext4" ]]; then
    log "Creating ext4 filesystem on $TARGET_PART (label=$LABEL)"
    mkfs.ext4 -F -L "$LABEL" "$TARGET_PART"
  elif [[ "$FILESYSTEM" == "xfs" ]]; then
    log "Creating xfs filesystem on $TARGET_PART (label=$LABEL)"
    mkfs.xfs -f -L "$LABEL" "$TARGET_PART"
  else
    err "Unsupported filesystem: $FILESYSTEM (use ext4 or xfs)"
    exit 1
  fi
else
  log "Skipping format (no-format)"
fi

# Create mount directory
mkdir -p "$MOUNT_PATH"

# Get UUID for fstab entry
UUID=$(blkid -s UUID -o value "$TARGET_PART") || true
if [[ -z "${UUID:-}" ]]; then
  err "Unable to get UUID for $TARGET_PART"
  exit 1
fi

# Add to /etc/fstab if not present
if ! grep -q "$UUID" /etc/fstab; then
  log "Adding fstab entry"
  if [[ "$FILESYSTEM" == "xfs" ]]; then
    echo "UUID=$UUID $MOUNT_PATH xfs defaults,noatime 0 2" | tee -a /etc/fstab >/dev/null
  else
    echo "UUID=$UUID $MOUNT_PATH ext4 defaults,noatime 0 2" | tee -a /etc/fstab >/dev/null
  fi
else
  log "fstab entry already present for UUID=$UUID"
fi

# Mount now
log "Mounting $MOUNT_PATH"
mount -a

# Prepare hostpath directory structure and permissions
mkdir -p "$MOUNT_PATH/hostpath"
chown -R root:root "$MOUNT_PATH"
chmod 755 "$MOUNT_PATH"

log "Done. Mounted $TARGET_PART at $MOUNT_PATH and prepared $MOUNT_PATH/hostpath"

# Try to create hostpath storage class automatically if MicroK8s is available
if command -v microk8s >/dev/null 2>&1; then
  log "Attempting to create hostpath storage class..."
  
  STORAGE_CLASS_NAME="hostpath-$(basename "$MOUNT_PATH")"
  
  # Wait a bit for MicroK8s to be ready
  if microk8s kubectl get storageclass >/dev/null 2>&1; then
    log "Creating hostpath storage class: $STORAGE_CLASS_NAME"
    
    # Create storage class YAML
    SC_YAML="/tmp/${STORAGE_CLASS_NAME}-sc.yaml"
    cat > "$SC_YAML" << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS_NAME
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    description: "Hostpath storage on additional disk $(basename "$MOUNT_PATH")"
provisioner: microk8s.io/hostpath
parameters:
  pvDir: $MOUNT_PATH/hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF
    
    # Apply storage class
    if microk8s kubectl apply -f "$SC_YAML" >/dev/null 2>&1; then
      log "✅ Storage class $STORAGE_CLASS_NAME created successfully"
      rm -f "$SC_YAML"
    else
      log "⚠️  Failed to create storage class automatically"
      log "Manual configuration required:"
      log "  1. Apply the storage class manually:"
      log "     microk8s kubectl apply -f $SC_YAML"
      log "  2. Or create via Kubernetes dashboard"
    fi
  else
    log "⚠️  MicroK8s not ready yet"
    log "Storage class will need to be created manually after MicroK8s is ready"
    
    # Create the YAML file for later use
    SC_YAML="/tmp/${STORAGE_CLASS_NAME}-sc.yaml"
    cat > "$SC_YAML" << EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $STORAGE_CLASS_NAME
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    description: "Hostpath storage on additional disk $(basename "$MOUNT_PATH")"
provisioner: microk8s.io/hostpath
parameters:
  pvDir: $MOUNT_PATH/hostpath
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF
    log "Storage class YAML saved to: $SC_YAML"
    log "Apply it later with: microk8s kubectl apply -f $SC_YAML"
  fi
else
  log "MicroK8s not found. Disk prepared for manual hostpath configuration."
fi

log "Repeat this script on each Jetson node to add additional hostpath storage."

# Show usage example
log ""
log "Usage example in PVC:"
log "---"
log "apiVersion: v1"
log "kind: PersistentVolumeClaim"
log "metadata:"
log "  name: my-pvc"
log "spec:"
log "  accessModes:"
log "    - ReadWriteOnce"
log "  storageClassName: $STORAGE_CLASS_NAME"
log "  resources:"
log "    requests:"
log "      storage: 10Gi"
