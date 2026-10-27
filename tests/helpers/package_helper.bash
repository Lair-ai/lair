#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC2034
# Packages installed by deployment scripts (excluding NVIDIA, dynamic kernel, docs-only)
UBUNTU_PACKAGES=(
  avahi-daemon
  avahi-utils
  bc
  containernetworking-plugins
  curl
  dnsutils
  dnsmasq
  gdisk
  ipset
  iptables
  iptables-persistent
  iputils-ping
  jq
  kmod
  libnss-mdns
  linux-generic
  nfs-common
  open-iscsi
  policycoreutils
  python3-yaml
  tar
  util-linux
  yq
  bats
  shellcheck
)

# shellcheck disable=SC2034
# Packages from external NVIDIA repository (only existence check, no section check)
NVIDIA_PACKAGES=(
  nvidia-container-toolkit
  nvidia-container-runtime
  nvidia-driver-535-server
)

# Verify that a package is available via apt-cache
# Returns 0 if package exists, 1 otherwise
package_exists() {
  local pkg="$1"
  apt-cache show "$pkg" >/dev/null 2>&1
}

# Verify that a package belongs to the main or universe component of an APT repository.
# apt-cache policy formats repository and release information differently across
# apt versions, so check both the repository line and its release metadata. Fall
# back to the package index Filename when policy output has no component details.
# Returns 0 if found, 1 otherwise.
package_in_main_or_universe() {
  local pkg="$1"
  local policy
  policy="$(apt-cache policy "$pkg" 2>/dev/null || true)"

  if awk '
    $NF == "Packages" {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /\/(main|universe)$/) {
          found = 1
          exit
        }
      }
    }
    /(^|[, ])c=(main|universe)([, ]|$)/ { found = 1; exit }
    END { if (found) exit 0; else exit 1 }
  ' <<< "$policy"; then
    return 0
  fi

  apt-cache show "$pkg" 2>/dev/null | awk '
    /^Filename: (.*\/)?pool\/(main|universe)\// { found = 1; exit }
    END { if (found) exit 0; else exit 1 }
  '
}
