#!/usr/bin/env bash

# region Hostname Setup for both Primary and Secondary nodes
info "Setting up hostname..."

CURRENT_HOSTNAME=$(hostname)
if $INTERACTIVE; then
  read -rp "📛 Enter new hostname [${CURRENT_HOSTNAME}]: " NEW_HOSTNAME
  # If empty, keep current one
  if [[ -z "$NEW_HOSTNAME" ]]; then
    NEW_HOSTNAME="$CURRENT_HOSTNAME"
    info "Hostname unchanged: '$NEW_HOSTNAME'"
  else
    hostnamectl set-hostname "$NEW_HOSTNAME"
    # Replace only the first occurrence in hosts file
    sed -i "0,/$CURRENT_HOSTNAME/s//$NEW_HOSTNAME/" /etc/hosts
    ok "Hostname updated: '$NEW_HOSTNAME'"
  fi
else
  # For non-interactive mode, generate different hostnames for primary vs secondary
  if [[ "${IS_PRIMARY_NODE:-false}" == "true" ]]; then
    NEW_HOSTNAME="microk8s-primary"
  else
    NEW_HOSTNAME="microk8s-secondary-$(date +%s | tail -c 4)" # Last 3 digits of timestamp for uniqueness
  fi
  info "Non-interactive: hostname set to '$NEW_HOSTNAME'"
  hostnamectl set-hostname "$NEW_HOSTNAME"
  sed -i "0,/$CURRENT_HOSTNAME/s//$NEW_HOSTNAME/" /etc/hosts
  ok "Hostname: '$NEW_HOSTNAME'"
fi

# Export for use in other modules
export NEW_HOSTNAME
# endregion Hostname Setup
