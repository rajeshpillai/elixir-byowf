#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for script in "${SCRIPT_DIR}"/[0-9][0-9]-*.sh; do
  echo "=== $(basename "$script" .sh) ==="
  bash "$script"
done
