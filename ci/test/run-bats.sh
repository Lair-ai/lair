#!/usr/bin/env bash

# Use -u to catch unset variables, but handle errors explicitly
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# 1. Check for bats and explicitly output to stderr
if ! command -v bats >/dev/null 2>&1; then
  echo "bats is not installed" >&2
  exit 1
fi

# 2. Check for tests directory
if [ ! -d "tests" ]; then
  echo "tests directory not found" >&2
  exit 1
fi

# 3. Execute tests
# Ensure the exit code of the final command is propagated
exec bats -r tests/unit tests/integration