#!/usr/bin/env bash
set -euo pipefail

# add-ssd-to-longhorn.sh
# Formats (optional), mounts and registers a secondary SSD for Longhorn on this node.
# Usage examples:
#   sudo ./add-ssd-to-longhorn.sh --device /dev/sdb --mount-path /var/lib/longhorn/ssd2
#   sudo ./add-ssd-to-longhorn.sh --device /dev/nvme1n1 --filesystem ext4 --label LH2 --wipe --mount-path /var/lib/longhorn/ssd2
#   sudo ./add-ssd-to-longhorn.sh --device /dev/sdb --no-format --mount-path /var/lib/longhorn/ssd2

DEVICE=""
MOUNT_PATH="/var/lib/longhorn/ssd2"
FILESYSTEM="ext4"
LABEL="LH2"
NO_FORMAT=false
WIPE=false

log() { echo "[add-ssd-to-longhorn] $*"; }
err() { echo "[add-ssd-to-longhorn][ERROR] $*" >&2; }
usage() {
  cat <<EOF
Usage: $0 --device <block_device> [--mount-path <dir>] [--filesystem ext4|xfs] [--label <LBL>] [--no-format] [--wipe]

Options:
  --device        Block device path (e.g., /dev/sdb, /dev/nvme1n1) [required]
  --mount-path    Mount point directory (default: /var/lib/longhorn/ssd2)
  --filesystem    Filesystem to create if formatting (ext4 or xfs; default: ext4)
  --label         Filesystem label to set when formatting (default: LH2)
  --no-format     Do not format the device (assumes pre-formatted fs)
  --wipe          Wipe existing partition table (dangerous). Implies formatting.

Notes:
- Run as root (sudo)
- This script adds an additional Longhorn disk on this node only. Repeat on each node.
- The disk will be automatically added to Longhorn node configuration if possible.
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

# Prepare Longhorn directory structure and permissions
mkdir -p "$MOUNT_PATH/longhorn"
chown -R root:root "$MOUNT_PATH"
chmod 755 "$MOUNT_PATH"

log "Done. Mounted $TARGET_PART at $MOUNT_PATH and prepared $MOUNT_PATH/longhorn"

# Try to add to Longhorn automatically if MicroK8s is available
if command -v microk8s >/dev/null 2>&1; then
  log "Attempting to add disk to Longhorn node configuration..."
  
  NODE_NAME=$(hostname)
  DISK_NAME=$(basename "$MOUNT_PATH")
  
  # Wait a bit for Longhorn to be ready
  if microk8s kubectl get nodes.longhorn.io "$NODE_NAME" >/dev/null 2>&1; then
    log "Adding disk to Longhorn node $NODE_NAME"
    
    # Create disk configuration
    DISK_CONFIG=$(cat <<EOF
{
  "path": "$MOUNT_PATH/longhorn",
  "allowScheduling": true,
  "evictionRequested": false,
  "storageReserved": 10737418240,
  "tags": ["manual", "additional"]
}
EOF
)
    
    # Apply disk configuration
    if microk8s kubectl patch nodes.longhorn.io "$NODE_NAME" --type='merge' -p "{\"spec\":{\"disks\":{\"$DISK_NAME\":$DISK_CONFIG}}}" >/dev/null 2>&1; then
      log "✅ Disk $DISK_NAME successfully added to Longhorn node $NODE_NAME"
    else
      log "⚠️  Failed to add disk to Longhorn automatically"
      log "Manual configuration required:"
      log "  1. Access Longhorn UI"
      log "  2. Go to Node -> $NODE_NAME"
      log "  3. Add disk: $MOUNT_PATH/longhorn"
    fi
  else
    log "⚠️  Longhorn node $NODE_NAME not found"
    log "Disk prepared but not added to Longhorn. Add manually via Longhorn UI."
  fi
else
  log "MicroK8s not found. Disk prepared for manual Longhorn configuration."
fi

log "Repeat this script on each node to add the additional disk to Longhorn nodes."
