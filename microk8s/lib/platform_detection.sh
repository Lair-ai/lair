#!/usr/bin/env bash

# region 7) Platform detection
IS_JETSON=false

# More specific check for NVIDIA Jetson
if [ -f /proc/device-tree/model ]; then
  MODEL_INFO=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
  if echo "$MODEL_INFO" | grep -qi "jetson\|xavier\|nano\|orin\|agx"; then
    IS_JETSON=true
  fi
fi

# Alternative check via Tegra in kernel (specific for Jetson)
if [ "$(uname -r | grep -c tegra)" -gt 0 ]; then
  IS_JETSON=true
fi

# Additional check via /sys/firmware/devicetree/base/model
if [ -f /sys/firmware/devicetree/base/model ]; then
  DT_MODEL=$(cat /sys/firmware/devicetree/base/model 2>/dev/null | tr -d '\0')
  if echo "$DT_MODEL" | grep -qi "jetson\|xavier\|nano\|orin\|agx"; then
    IS_JETSON=true
  fi
fi

if $IS_JETSON; then
  echo -e "${YELLOW}[INFO]${NC} Detected NVIDIA Jetson system - specific fixes will be applied"
fi
# endregion 7) Platform detection
