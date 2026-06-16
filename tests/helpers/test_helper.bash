#!/usr/bin/env bash

set -euo pipefail

project_root() {
  git rev-parse --show-toplevel
}

assert_file_exists() {
  local path="$1"
  [ -f "$path" ]
}

load_function_from_file() {
  local file_path="$1"
  local function_name="$2"

  awk -v fn="$function_name" '
    BEGIN { in_func=0; depth=0 }
    {
      if (!in_func && $0 ~ "^" fn "\\(\\)[[:space:]]*\\{") {
        in_func=1
      }

      if (in_func) {
        print
        opens=gsub(/\{/, "{", $0)
        closes=gsub(/\}/, "}", $0)
        depth += opens - closes
        if (depth == 0) {
          exit
        }
      }
    }
  ' "$file_path"
}
