#!/usr/bin/env bash

# region 15) OS update (split & fix)
info "Package update: apt update"
if ! apt update; then
  err "apt update failed"; exit 1
fi

info "Applying upgrade: apt upgrade -y"
if ! apt upgrade -y; then
  err "apt upgrade failed"; exit 1
fi

info "Fixing any broken packages: apt --fix-broken install -y"
if ! apt --fix-broken install -y; then
  warn "Fix-broken had issues, continuing anyway"
fi

# (optional) autoremove disabled: avoids issues in automatic provisioning
# info "System cleanup: apt autoremove --purge -y"
# if ! apt autoremove --purge -y; then
#   warn "autoremove failed, ignored"
# fi

ok "OS updated and system stabilized"
# endregion 15) OS update (split & fix)

# region 16) Install policycoreutils for matchpathcon
info "Installing essential packages (policycoreutils, bc, gdisk)"
if ! (apt update && apt install -y policycoreutils bc gdisk); then
  warn "Some packages failed to install, trying individually..."
  apt install -y policycoreutils || warn "policycoreutils installation failed"
  apt install -y bc || warn "bc installation failed"
  apt install -y gdisk || warn "gdisk installation failed"
fi
ok "Essential packages installed"

info "Disabling SELinux to avoid issues"
if command -v setenforce &>/dev/null; then
  run_cmd "setenforce 0" "Disabling SELinux temporarily"
fi
run_cmd "echo 'SELINUX=disabled' > /etc/selinux/config" "Disabling SELinux permanently"
# endregion 16) Install policycoreutils for matchpathcon

# region 16.5) Installation of YAML parsing dependencies for configuration scripts
info "Installing YAML parsing dependencies for configuration scripts"
if ! run_cmd "apt update -y && apt install -y python3-yaml yq" "Installing python3-yaml and yq"; then
  warn "Installation of python3-yaml or yq failed, trying separate installations..."
  
  # Try python3-yaml installation
  if ! run_cmd "apt install -y python3-yaml" "Installing python3-yaml"; then
    warn "Unable to install python3-yaml"
    
    # Fallback: try installation via pip
    if command -v pip3 >/dev/null 2>&1; then
      info "Attempting PyYAML installation via pip3..."
      if ! run_cmd "pip3 install --break-system-packages PyYAML" "Installing PyYAML via pip3"; then
        warn "PyYAML installation via pip3 failed"
      else
        ok "PyYAML installed via pip3"
      fi
    else
      warn "pip3 not available, YAML parser installation failed"
    fi
  else
    ok "python3-yaml installed"
  fi
  
  # Try yq installation
  if ! run_cmd "apt install -y yq" "Installing yq"; then
    warn "Unable to install yq from standard repository"
    
    # Fallback: yq installation via snap
    if command -v snap >/dev/null 2>&1; then
      info "Attempting yq installation via snap..."
      if ! run_cmd "snap install yq" "Installing yq via snap"; then
        warn "yq installation via snap failed"
      else
        ok "yq installed via snap"
      fi
    else
      warn "snap not available, yq installation failed"
    fi
  else
    ok "yq installed"
  fi
else
  ok "YAML parsing dependencies installed correctly"
fi

# Final verification of available YAML parsers
info "Checking available YAML parsers..."
YAML_PARSERS_AVAILABLE=0

if command -v yq >/dev/null 2>&1; then
  ok "yq parser available"
  YAML_PARSERS_AVAILABLE=1
fi

if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import yaml" >/dev/null 2>&1; then
    ok "python3 with yaml module available"
    YAML_PARSERS_AVAILABLE=1
  else
    warn "python3 available but without yaml module"
  fi
fi

if [ $YAML_PARSERS_AVAILABLE -eq 0 ]; then
  warn "No YAML parser available - configuration scripts will use interactive mode"
else
  ok "At least one YAML parser is available"
fi
# endregion 16.5) Installation of YAML parsing dependencies for configuration scripts

# region 17) Check and install kernel modules required for Calico (ipset/iptables)
info "Checking and installing networking dependencies"
if ! run_cmd "apt update -y" "Repository update"; then
  warn "Repository update failed, continuing with installation"
fi

if ! run_cmd "apt install -y ipset iptables kmod" "Installing ipset/iptables/kmod dependencies"; then
  warn "Installation partially failed, some modules might not be available"
fi

# Check if it's an NVIDIA Jetson
if grep -q NVIDIA /proc/device-tree/model 2>/dev/null || [ "$(uname -r | grep -c tegra)" -gt 0 ]; then
  info "NVIDIA Jetson system detected, applying specific fixes"
  
  # Complete iptables fixes for Jetson
  info "Applying complete iptables fixes for Jetson"
  
  # Backup xtables directory
  if [ -d "/usr/lib/xtables" ]; then
    if ! run_cmd "cp -r /usr/lib/xtables /usr/lib/xtables.bak" "Backup xtables directory"; then
      warn "xtables backup failed, continuing without backup"
    fi
  fi
  
  # Install specific iptables versions
  info "Installing iptables and persistence (non-interactive)..."
  run_cmd "DEBIAN_FRONTEND=noninteractive apt install -y iptables iptables-persistent" "Non-interactive iptables and persistence installation"
  
  # Switch to iptables-legacy which works better on Jetson
  if ! run_cmd "update-alternatives --set iptables /usr/sbin/iptables-legacy" "Set iptables-legacy"; then
    warn "Setting iptables-legacy failed, continuing with standard configuration"
  fi
  if ! run_cmd "update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy" "Set ip6tables-legacy"; then
    warn "Setting ip6tables-legacy failed, continuing with standard configuration"  
  fi
  
  # Disable nftables to avoid conflicts
  if systemctl is-active nftables >/dev/null 2>&1; then
    run_cmd "systemctl stop nftables && systemctl disable nftables" "Stop and disable nftables"
  fi
  
  # Check if arptables and ebtables are available
  if command -v arptables >/dev/null 2>&1; then
    if ! run_cmd "update-alternatives --set arptables /usr/sbin/arptables-legacy" "Set arptables-legacy"; then
      debug "arptables-legacy not available"
    fi
  fi
  if command -v ebtables >/dev/null 2>&1; then
    if ! run_cmd "update-alternatives --set ebtables /usr/sbin/ebtables-legacy" "Set ebtables-legacy"; then
      debug "ebtables-legacy not available"
    fi
  fi
  
  # Create empty iptables initialization file to ensure rules are loaded at boot
  run_cmd "mkdir -p /etc/iptables" "Creating iptables directory"
  run_cmd "touch /etc/iptables/rules.v4" "Creating iptables rules file"
  run_cmd "touch /etc/iptables/rules.v6" "Creating ip6tables rules file"
  
  # For Jetson, use flannel instead of calico
  info "Configuring to use flannel instead of calico on Jetson"
  CUSTOM_CNI="flannel"
else
  # Non-Jetson system, loading standard modules
  if ! run_cmd "modprobe ip_set" "Loading ip_set module"; then
    warn "ip_set module not available, there might be issues with Calico"
  fi
  if ! run_cmd "modprobe ip_set_hash_ip" "Loading ip_set_hash_ip module"; then
    warn "ip_set_hash_ip module not available"
  fi
  if ! run_cmd "modprobe ip_set_hash_net" "Loading ip_set_hash_net module"; then
    warn "ip_set_hash_net module not available"
  fi
  
  # Add modules to boot
  if ! grep -q "ip_set" /etc/modules; then
    run_cmd "echo 'ip_set' >> /etc/modules" "Adding ip_set to automatic loading"
    run_cmd "echo 'ip_set_hash_ip' >> /etc/modules" "Adding ip_set_hash_ip to automatic loading"
    run_cmd "echo 'ip_set_hash_net' >> /etc/modules" "Adding ip_set_hash_net to automatic loading"
  fi
  
  # Non-Jetson system, use calico (default)
  CUSTOM_CNI=""
fi
# endregion 17) Check and install kernel modules required for Calico (ipset/iptables)
