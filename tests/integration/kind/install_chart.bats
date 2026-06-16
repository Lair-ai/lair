#!/usr/bin/env bats

load "../../helpers/test_helper.bash"

@test "helm chart folder exists for integration tests" {
  local root
  root="$(project_root)"
  [ -d "$root/helm-chart" ]
}
