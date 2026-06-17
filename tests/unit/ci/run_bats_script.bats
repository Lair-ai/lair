#!/usr/bin/env bats

setup() {
  ROOT="$(git rev-parse --show-toplevel)"
  TMPDIR_TEST="$(mktemp -d)"
  FAKEBIN="$TMPDIR_TEST/bin"
  mkdir -p "$FAKEBIN"

  # Forniamo al FAKEBIN solo i comandi di sistema essenziali per interpretare lo script
  # Questo previene l'errore 127 senza esporre il "bats" reale di sistema
  ln -s "$(command -v bash)" "$FAKEBIN/bash"
  ln -s "$(command -v dirname)" "$FAKEBIN/dirname"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

@test "run-bats script fails when bats is missing" {
  cat >"$FAKEBIN/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "rev-parse" ] && [ "\$2" = "--show-toplevel" ]; then
  echo "$TMPDIR_TEST"
  exit 0
fi
exit 1
EOF
  chmod +x "$FAKEBIN/git"

  # Esecuzione in puro isolamento: vede solo bash, dirname e il finto git
  run bash -c "PATH=\"$FAKEBIN\" $ROOT/ci/test/run-bats.sh 2>&1"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "bats is not installed" ]]
}

@test "run-bats script fails when tests directory is missing" {
  cat >"$FAKEBIN/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "rev-parse" ] && [ "\$2" = "--show-toplevel" ]; then
  echo "$TMPDIR_TEST"
  exit 0
fi
exit 1
EOF

  cat >"$FAKEBIN/bats" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKEBIN/git" "$FAKEBIN/bats"

  run bash -c "PATH=\"$FAKEBIN\" $ROOT/ci/test/run-bats.sh 2>&1"
  
  [ "$status" -eq 1 ]
  [[ "$output" =~ "tests directory not found" ]]
}

@test "run-bats script executes bats with expected directories" {
  mkdir -p "$TMPDIR_TEST/tests/unit" "$TMPDIR_TEST/tests/integration"

  cat >"$FAKEBIN/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "rev-parse" ] && [ "\$2" = "--show-toplevel" ]; then
  echo "$TMPDIR_TEST"
  exit 0
fi
exit 1
EOF

  cat >"$FAKEBIN/bats" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$TMPDIR_TEST/bats_args.txt"
exit 0
EOF
  chmod +x "$FAKEBIN/git" "$FAKEBIN/bats"

  run bash -c "PATH=\"$FAKEBIN\" $ROOT/ci/test/run-bats.sh 2>&1"
  
  [ "$status" -eq 0 ]
  
  # run cat qui userà il PATH nativo di BATS per leggere il file temporaneo
  run cat "$TMPDIR_TEST/bats_args.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tests/unit tests/integration"* ]]
}