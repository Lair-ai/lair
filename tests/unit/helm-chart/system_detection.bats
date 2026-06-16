#!/usr/bin/env bats

load "../../helpers/test_helper.bash"

setup() {
  local root
  root="$(project_root)"

  BLUE=""
  GREEN=""
  YELLOW=""
  NC=""

  eval "$(load_function_from_file "$root/helm-chart/lib/system-detection.sh" calculate_longhorn_replicas)"
}

@test "calculate_longhorn_replicas defaults to 1 when node count is empty" {
  NODES_COUNT=""
  calculate_longhorn_replicas
  [ "$?" -eq 0 ]
  [ "$LONGHORN_REPLICAS_COUNT" -eq 1 ]
}

@test "calculate_longhorn_replicas matches node count up to three" {
  NODES_COUNT=2
  calculate_longhorn_replicas
  [ "$?" -eq 0 ]
  [ "$LONGHORN_REPLICAS_COUNT" -eq 2 ]
}

@test "calculate_longhorn_replicas caps replicas at three" {
  NODES_COUNT=5
  calculate_longhorn_replicas
  [ "$?" -eq 0 ]
  [ "$LONGHORN_REPLICAS_COUNT" -eq 3 ]
}
