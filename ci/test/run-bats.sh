#!/usr/bin/env bash

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if ! command -v bats >/dev/null 2>&1; then
  echo "bats is not installed"
  exit 1
fi

if [ ! -d "tests" ]; then
  echo "tests directory not found"
  exit 1
fi

bats -r tests/unit tests/integration
