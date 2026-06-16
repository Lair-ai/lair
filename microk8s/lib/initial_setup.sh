#!/usr/bin/env bash

# region 3) Verify root execution
echo -e "${PRE_BLUE}[INFO]${PRE_NC} Pre-startup checks completed."
if [ "$(id -u)" -ne 0 ]; then
  echo -e "\e[31m[ERROR]\e[0m This script must be run as root"
  exit 1
fi
# endregion 3) Verify root execution

# region 4) Verbose mode
VERBOSE=false
DEBUG=false
MICROK8S_GROUP_REEXEC=${MICROK8S_GROUP_REEXEC:-0}  # Numeric initialization to avoid unbound variable error
if [[ "${1-}" =~ ^-(-verbose|v)$ ]]; then
  VERBOSE=true; shift
fi
if [[ "${1-}" =~ ^-(-debug|d)$ ]]; then
  DEBUG=true; VERBOSE=true; shift
fi
# endregion 4) Verbose mode

# region 5) Fail-fast and debug
set -Eeuo pipefail
$VERBOSE && set -x
# endregion 5) Fail-fast and debug

# region 6) ANSI colors for logger
BLUE="\e[94m"; GREEN="\e[32m"; YELLOW="\e[33m"; RED="\e[31m"; NC="\e[0m"
# endregion 6) ANSI colors for logger
