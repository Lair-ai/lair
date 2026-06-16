#!/usr/bin/env bash

# region Advanced logging to multiple files + console
LOGDIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOGDIR"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOGFILE="$LOGDIR/setup_k8s-managed_${TIMESTAMP}.log"
DEBUGLOG="$LOGDIR/setup_k8s-managed_debug_${TIMESTAMP}.log"
CMDLOG="$LOGDIR/setup_k8s-managed_commands_${TIMESTAMP}.log"
ERRLOG="$LOGDIR/setup_k8s-managed_errors_${TIMESTAMP}.log"

# Colori ANSI per il logger
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Prepare log files
echo -e "${BLUE}=== K8s Managed Setup Log $(date) ===${NC}" > "$LOGFILE"
echo -e "${BLUE}=== K8s Managed Debug Log $(date) ===${NC}" > "$DEBUGLOG"
echo -e "${BLUE}=== K8s Managed Commands Log $(date) ===${NC}" > "$CMDLOG"
echo -e "${BLUE}=== K8s Managed Errors Log $(date) ===${NC}" > "$ERRLOG"

timestamp() { date -Iseconds; }
log() { printf '[%s] %s: %s\n' "$(timestamp)" "$1" "$2"; }
info() { 
  local msg="$1"
  printf '%b' "$BLUE"
  log "INFO" "$msg"
  printf '%b' "$NC"
  log "INFO" "$msg" >> "$LOGFILE"
}
ok() {
  local msg="$1"
  printf '%b' "$GREEN"
  log "OK" "$msg"
  printf '%b' "$NC"
  log "OK" "$msg" >> "$LOGFILE"
}
warn() {
  local msg="$1"
  printf '%b' "$YELLOW"
  log "WARN" "$msg"
  printf '%b' "$NC"
  log "WARN" "$msg" >> "$LOGFILE"
}
err() {
  local msg="$1"
  printf '%b' "$RED"
  log "ERROR" "$msg"
  printf '%b' "$NC"
  log "ERROR" "$msg" >> "$LOGFILE"
  log "ERROR" "$msg" >> "$ERRLOG"
}
debug() { 
  local msg="$1"
  log "DEBUG" "$msg" >> "$DEBUGLOG"
  if [[ ${DEBUG:-false} == true ]]; then 
    printf '%b[DEBUG] %s%b\n' "$BLUE" "$msg" "$NC"
  fi
}
# endregion Advanced logging to multiple files + console