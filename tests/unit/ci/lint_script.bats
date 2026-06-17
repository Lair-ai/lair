#!/usr/bin/env bats

setup() {
  ROOT="$(git rev-parse --show-toplevel)"
  TMPDIR_TEST="$(mktemp -d)"
  FAKEBIN="$TMPDIR_TEST/bin"
  mkdir -p "$FAKEBIN"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "lint script fails when shellcheck is missing" {
  cat >"$FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "rev-parse" ] && [ "$2" = "--show-toplevel" ]; then
  pwd
  exit 0
fi
if [ "$1" = "ls-files" ]; then
  printf '%s\n' "script.sh"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKEBIN/git"

  run env PATH="$FAKEBIN:/usr/bin:/bin" /bin/bash "$ROOT/ci/lint/shellcheck.sh" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"shellcheck is not installed"* ]]
}

@test "lint script reports success with fake shellcheck" {
  cat >"$FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "rev-parse" ] && [ "$2" = "--show-toplevel" ]; then
  pwd
  exit 0
fi
if [ "$1" = "ls-files" ]; then
  printf '%s\n' "a.sh" "b.sh"
  exit 0
fi
exit 1
EOF

  cat >"$FAKEBIN/shellcheck" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod +x "$FAKEBIN/git" "$FAKEBIN/shellcheck"

  run env PATH="$FAKEBIN:/usr/bin:/bin" /bin/bash "$ROOT/ci/lint/shellcheck.sh" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"shellcheck passed on 2 files"* ]]
}

@test "lint script exits cleanly when no shell scripts are found" {
  cat >"$FAKEBIN/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "rev-parse" ] && [ "$2" = "--show-toplevel" ]; then
  pwd
  exit 0
fi
if [ "$1" = "ls-files" ]; then
  exit 0
fi
exit 1
EOF

  cat >"$FAKEBIN/shellcheck" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

  chmod +x "$FAKEBIN/git" "$FAKEBIN/shellcheck"

  run env PATH="$FAKEBIN:/usr/bin:/bin" /bin/bash "$ROOT/ci/lint/shellcheck.sh" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"No shell scripts found"* ]]
}
