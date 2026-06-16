#!/usr/bin/env bats

load "../../helpers/test_helper.bash"

@test "helm chart setup script exists" {
  local root
  root="$(project_root)"
  run assert_file_exists "$root/helm-chart/setup.sh"
  [ "$status" -eq 0 ]
}
