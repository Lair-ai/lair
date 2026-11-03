#!/usr/bin/env bats

ROOT="$(git rev-parse --show-toplevel)"

setup() {
  source "$ROOT/tests/helpers/package_helper.bash"
  # BATS_TEST_TMPDIR only exists in bats >= 1.3; fall back to mktemp on older versions
  BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
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
  policy:virtual-package)
    printf 'Installed: (none)\n  Candidate: (none)\n  Version table:\n'
    ;;
  show:virtual-package)
    ;;
  showpkg:virtual-package)
    printf 'Package: virtual-package\nVersions: \n\nReverse Provides: \nreal-provider 1:9.20.24-1ubuntu0.4 (= )\n'
    ;;
  policy:real-provider)
    printf '500 http://archive.ubuntu.com/ubuntu noble/universe amd64 Packages\n'
    ;;
  policy:virtual-orphan)
    printf 'Installed: (none)\n  Candidate: (none)\n  Version table:\n'
    ;;
  show:virtual-orphan)
    ;;
  showpkg:virtual-orphan)
    printf 'Package: virtual-orphan\nVersions: \n\nDependencies: \n'
    ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/apt-cache"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

cleanup() {
  # Only needed when bats did not provide BATS_TEST_TMPDIR itself
  rm -rf "${BATS_TEST_TMPDIR:-}"
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

@test "package component resolves virtual package through provider" {
  run package_in_main_or_universe virtual-package
  [ "$status" -eq 0 ]
}

@test "package component fails for virtual package without provider" {
  run package_in_main_or_universe virtual-orphan
  [ "$status" -eq 1 ]
}
