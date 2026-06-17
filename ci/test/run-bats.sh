#!/usr/bin/env bash
set -uo pipefail

if ! command -v bats >/dev/null 2>&1; then
  echo "bats is not installed" >&2
  exit 1
fi

set -e

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd))"
cd "$ROOT"

if [ ! -d "tests" ]; then
  echo "tests directory not found" >&2
  exit 1
fi

exec bats -r tests/unit tests/integration