#!/usr/bin/env bash

# region 28) Community & monitoring addons
info "Enabling community and metrics-server..."
enable_addon community 5 kube-system
enable_addon metrics-server 5 kube-system
# endregion 28) Community & monitoring addons