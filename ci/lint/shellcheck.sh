#!/usr/bin/env bash

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck is not installed"
  exit 1
fi

scripts="$(git ls-files '*.sh')"

if [ -z "$scripts" ]; then
  echo "No shell scripts found"
  exit 0
fi

count="$(printf '%s\n' "$scripts" | wc -l | tr -d ' ')"
printf '%s\n' "$scripts" | xargs shellcheck -S error
echo "shellcheck passed on ${count} files"
