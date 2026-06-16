#!/usr/bin/env bash

# region 21) Core addons
info "Enabling core addons..."
run_cmd "microk8s enable ingress helm3" "Enabling core base addons"
ok "Core base addons enabled"
# endregion 21) Core addons