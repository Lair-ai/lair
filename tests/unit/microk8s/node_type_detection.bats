#!/usr/bin/env bats

load "../../helpers/test_helper.bash"

setup() {
  local root
  root="$(project_root)"
  eval "$(load_function_from_file "$root/microk8s/lib/node_type_detection.sh" validate_ip)"
}

@test "validate_ip accepts valid IPv4 address" {
  run validate_ip "192.168.1.10"
  [ "$status" -eq 0 ]
}

@test "validate_ip rejects octet greater than 255" {
  run validate_ip "192.168.300.10"
  [ "$status" -ne 0 ]
}

@test "validate_ip rejects non-IPv4 values" {
  run validate_ip "not-an-ip"
  [ "$status" -ne 0 ]
}
