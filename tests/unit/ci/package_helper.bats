#!/usr/bin/env bats

ROOT="$(git rev-parse --show-toplevel)"

setup() {
  source "$ROOT/tests/helpers/package_helper.bash"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/apt-cache" <<'EOF'
#!/usr/bin/env bash
case "$1:$2" in
  policy:repository-line)
    printf '500 http://archive.ubuntu.com/ubuntu noble/universe amd64 Packages\n'
    ;;
  policy:release-metadata)
    printf 'release v=24.04,o=Ubuntu,n=noble,l=Ubuntu,c=main,b=amd64\n'
    ;;
  policy:filename-fallback)
    ;;
  show:filename-fallback)
    printf 'Filename: pool/universe/e/example/example_1.0_amd64.deb\n'
    ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/apt-cache"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "package component recognizes apt policy repository lines" {
  run package_in_main_or_universe repository-line
  [ "$status" -eq 0 ]
}

@test "package component recognizes apt release metadata" {
  run package_in_main_or_universe release-metadata
  [ "$status" -eq 0 ]
}

@test "package component falls back to package index filename" {
  run package_in_main_or_universe filename-fallback
  [ "$status" -eq 0 ]
}
