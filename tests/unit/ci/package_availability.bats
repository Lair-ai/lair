#!/usr/bin/env bats

ROOT="$(git rev-parse --show-toplevel)"
source "$ROOT/tests/helpers/package_helper.bash"

@test "ubuntu packages exist in apt repository" {
  local failed=()
  for pkg in "${UBUNTU_PACKAGES[@]}"; do
    if ! package_exists "$pkg"; then
      failed+=("$pkg")
    fi
  done
  if [ ${#failed[@]} -gt 0 ]; then
    echo "Packages not found in apt repository: ${failed[*]}"
    return 1
  fi
}

@test "ubuntu packages belong to main or universe repository" {
  local failed=()
  for pkg in "${UBUNTU_PACKAGES[@]}"; do
    if ! package_in_main_or_universe "$pkg"; then
      failed+=("$pkg")
    fi
  done
  if [ ${#failed[@]} -gt 0 ]; then
    echo "Packages NOT in main/universe: ${failed[*]}"
    return 1
  fi
}

@test "nvidia packages exist in apt repository (external repo)" {
  local failed=()
  for pkg in "${NVIDIA_PACKAGES[@]}"; do
    if ! package_exists "$pkg"; then
      failed+=("$pkg")
    fi
  done
  if [ ${#failed[@]} -gt 0 ]; then
    echo "NVIDIA packages not found: ${failed[*]}"
    return 1
  fi
}
