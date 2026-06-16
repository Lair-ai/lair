#!/usr/bin/env bats

load "../../helpers/test_helper.bash"

@test "microk8s setup script exists" {
  local root
  root="$(project_root)"
  run assert_file_exists "$root/microk8s/setup.sh"
  [ "$status" -eq 0 ]
}
