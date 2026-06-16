#!/usr/bin/env bash

# region 9) Support functions
# region Trap for errors with more details
trap 'err "Error in ${BASH_SOURCE[0]} line ${LINENO}, command: ${BASH_COMMAND}, exit code $?"; echo "[$(date -Iseconds)] FATAL ERROR in ${BASH_SOURCE[0]} line ${LINENO}, command: ${BASH_COMMAND}, exit code $?" >> "$ERRLOG"; exit 1' ERR
# endregion Trap for errors with more details

# region Function to execute and log commands
# Function to execute and log commands
run_cmd() {
  local cmd="$1"
  local desc="${2:-Command execution}"
  
  debug "Execution: $cmd"
  echo "[$(timestamp)] CMD: $cmd" >> "$CMDLOG"
  
  local output
  local exit_code
  
  # Execute the command and capture output; prevent set -e from aborting here
  # so we can do our own error handling and logging.
  if ! output=$(eval "$cmd" 2>&1); then
    exit_code=$?
  else
    exit_code=0
  fi
  
  # Command output log
  echo "[$(timestamp)] OUTPUT ($exit_code):" >> "$CMDLOG"
  echo "$output" >> "$CMDLOG"
  echo "----------------------------------------" >> "$CMDLOG"
  
  # If debug, also show output
  if $DEBUG; then
    echo "$output"
  fi
  
  # Return exit code
  if [ $exit_code -ne 0 ]; then
    err "$desc failed (exit $exit_code): $cmd"
    echo "[$(timestamp)] FAILED CMD ($exit_code): $cmd" >> "$ERRLOG"
    echo "$output" >> "$ERRLOG"
    echo "----------------------------------------" >> "$ERRLOG"
  fi
  
  return $exit_code
}
# endregion Function to execute and log commands

# region Addon enable function with retry and wait for pods - with extended debug
# Addon enable function with retry and wait for pods - with extended debug
enable_addon(){
  local addon="$1"; shift
  local retries=${1:-5}
  local namespace=${2:-kube-system}
  
  # Longer timeout for Jetson
  local timeout=900
  if $IS_JETSON; then
    timeout=600 # 10 minutes for Jetson instead of 30
    info "Extended timeout to 10 minutes for Jetson"
  fi

  info "Enabling addon '$addon'..."
  debug "Attempting to enable addon '$addon' (retry: $retries, namespace: $namespace)"
  
  for i in $(seq 1 $retries); do
    debug "Attempt $i/$retries to enable addon '$addon'"
    if run_cmd "microk8s enable \"$addon\"" "Enabling addon $addon"; then
      ok "$addon enabled"
      # On Jetson, we don't wait for Ready pods to speed up
      if $IS_JETSON; then
        warn "Addon $addon enabled on Jetson - continuing without waiting for Ready pods"
        return 0
      fi
      debug "Waiting for pods in namespace $namespace"
      # Wait for pod readiness in namespace
      if run_cmd "microk8s kubectl wait --namespace \"$namespace\" --for=condition=Ready pod --all --timeout=${timeout}s" "Waiting for pods in namespace $namespace"; then
        debug "All pods in namespace $namespace are ready"
        return 0
      else
        # On Jetson, we continue even if not all pods are ready
        if $IS_JETSON; then
          warn "Pods in namespace $namespace not all ready, but continuing on Jetson"
          return 0
        else 
          warn "Pods in namespace $namespace not all ready, but addon $addon enabled"
          return 0
        fi
      fi
    else
      warn "Attempt $i for '$addon' failed, retrying..."
      sleep 5
    fi
  done
  
  # On Jetson we ignore errors and continue
  if $IS_JETSON; then
    warn "Unable to enable addon '$addon' after $retries attempts, but continuing on Jetson"
    return 0
  else
    err "Unable to enable addon '$addon' after $retries attempts"
    exit 1
  fi
}
# endregion Addon enable function with retry and wait for pods - with extended debug
# endregion 9) Support functions

