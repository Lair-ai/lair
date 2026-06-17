#!/usr/bin/env bash

set -euo pipefail

# 1. Controllo dipendenze prima di qualsiasi operazione di file system
if ! command -v bats >/dev/null 2>&1; then
  echo "bats is not installed" >&2
  exit 1
fi

# Se git fallisce (ambiente test), usiamo la posizione dello script
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || (cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd))"
cd "$ROOT"

# 3. Verifica esistenza directory
if [ ! -d "tests" ]; then
  echo "tests directory not found" >&2
  exit 1
fi

# 4. Esecuzione
exec bats -r tests/unit tests/integration