#!/usr/bin/env bash

# region Support functions
# region Function to redact secrets from commands and outputs
redact_secrets() {
  local input="$1"
  printf "%s\n" "$input" | sed -E \
    -e "s/(aws_secret_access_key[[:space:]]*=[[:space:]]*['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/(aws_access_key_id[[:space:]]*=[[:space:]]*['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/(--from-literal=[^'\"[:space:]=]+=['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/(--from-literal=['\"]?[^'\"[:space:]=]+=[[:space:]]*)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/((token|password|secret|key|passwd)[[:space:]]*=[[:space:]]*['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI" \
    -e "s/(--?(token|password|secret|key|passwd)[[:space:]]+['\"]?)[^'\"[:space:]]+/\1[REDACTED]/gI"
}
# endregion Function to redact secrets from commands and outputs

# region Error trap with more details
trap 'err "Error in ${BASH_SOURCE[0]} line ${LINENO}, command: $(redact_secrets "${BASH_COMMAND}"), exit code $?"; echo "[$(date -Iseconds)] FATAL ERROR in ${BASH_SOURCE[0]} line ${LINENO}, command: $(redact_secrets "${BASH_COMMAND}"), exit code $?" >> "$ERRLOG"; exit 1' ERR
# endregion Error trap with more details

# region Function to execute and log commands
# Function to execute and log commands
run_cmd() {
  local cmd="$1"
  local desc="${2:-Command execution}"
  
  local redacted_cmd
  redacted_cmd=$(redact_secrets "$cmd")
  
  debug "Executing: $redacted_cmd"
  echo "[$(timestamp)] CMD: $redacted_cmd" >> "$CMDLOG"
  
  local output
  local exit_code
  
  # Execute the command and capture output; prevent set -e from aborting here
  # so we can do our own error handling and logging.
  if ! output=$(eval "$cmd" 2>&1); then
    exit_code=$?
  else
    exit_code=0
  fi
  
  local redacted_output
  redacted_output=$(redact_secrets "$output")
  
  # Log command output
  echo "[$(timestamp)] OUTPUT ($exit_code):" >> "$CMDLOG"
  echo "$redacted_output" >> "$CMDLOG"
  echo "----------------------------------------" >> "$CMDLOG"
  
  # If debug, also show output
  if [[ ${DEBUG:-false} == true ]]; then
    echo "$redacted_output"
  fi
  
  # Return exit code
  if [ $exit_code -ne 0 ]; then
    err "$desc failed (exit $exit_code): $redacted_cmd"
    echo "[$(timestamp)] FAILED CMD ($exit_code): $redacted_cmd" >> "$ERRLOG"
    echo "$redacted_output" >> "$ERRLOG"
    echo "----------------------------------------" >> "$ERRLOG"
  fi
  
  return $exit_code
}
# endregion Function to execute and log commands
# endregion 9) Support functions
