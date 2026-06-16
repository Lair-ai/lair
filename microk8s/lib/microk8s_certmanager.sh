#!/usr/bin/env bash

# region 23) Enabling cert-manager
for addon in "${CORE_ADDONS[@]}"; do
  if [[ "$addon" == "cert-manager" ]]; then
    enable_addon "$addon" 5 cert-manager
  else
    enable_addon "$addon" 5 kube-system
  fi
done
# endregion 23) Enabling cert-manager