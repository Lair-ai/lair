#!/usr/bin/env bash

# region Support functions
# region Error trap with more details
trap 'err "Error in ${BASH_SOURCE[0]} line ${LINENO}, command: ${BASH_COMMAND}, exit code $?"; echo "[$(date -Iseconds)] FATAL ERROR in ${BASH_SOURCE[0]} line ${LINENO}, command: ${BASH_COMMAND}, exit code $?" >> "$ERRLOG"; exit 1' ERR
# endregion Error trap with more details

# region Function to execute and log commands
# Function to execute and log commands
run_cmd() {
  local cmd="$1"
  local desc="${2:-Command execution}"
  
  debug "Executing: $cmd"
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
  
  # Log command output
  echo "[$(timestamp)] OUTPUT ($exit_code):" >> "$CMDLOG"
  echo "$output" >> "$CMDLOG"
  echo "----------------------------------------" >> "$CMDLOG"
  
  # If debug, also show output
  if [[ ${DEBUG:-false} == true ]]; then
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
# endregion 9) Support functions
