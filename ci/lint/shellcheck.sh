#!/usr/bin/env bash

set -euo pipefail

# 1. Controllo dipendenze
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed" >&2
  exit 1
fi

# 2. Determinazione sicura della Root
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

# 3. Raccolta script
scripts="$(git ls-files '*.sh' 2>/dev/null || find . -name '*.sh' -type f)"

if [ -z "$scripts" ]; then
  echo "No shell scripts found"
  exit 0
fi

# 4. Esecuzione lint
count="$(printf '%s\n' "$scripts" | wc -l | tr -d ' ')"
printf '%s\n' "$scripts" | xargs shellcheck -S error
echo "shellcheck passed on ${count} files"
