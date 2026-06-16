#!/usr/bin/env bash

# region 8) Advanced logging on multiple files + console
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGDIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOGDIR"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
LOGFILE="$LOGDIR/setup_microk8s_${TIMESTAMP}.log"
DEBUGLOG="$LOGDIR/setup_microk8s_debug_${TIMESTAMP}.log"
CMDLOG="$LOGDIR/setup_microk8s_commands_${TIMESTAMP}.log"
ERRLOG="$LOGDIR/setup_microk8s_errors_${TIMESTAMP}.log"

# Prepare log files
echo -e "${BLUE}=== MicroK8s Setup Log $(date) ===${NC}" > "$LOGFILE"
echo -e "${BLUE}=== MicroK8s Debug Log $(date) ===${NC}" > "$DEBUGLOG"
echo -e "${BLUE}=== MicroK8s Commands Log $(date) ===${NC}" > "$CMDLOG"
echo -e "${BLUE}=== MicroK8s Errors Log $(date) ===${NC}" > "$ERRLOG"

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
  if $DEBUG; then 
    printf '%b[DEBUG] %s%b\n' "$BLUE" "$msg" "$NC"
  fi
}
# endregion 8) Advanced logging on multiple files + console
