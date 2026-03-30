#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

exec python -m pipeline generate "${TUTORIALS_DIR}/11-error-handler.md" \
  -p "${TTS_PROVIDER}" \
  -v "${TTS_VOICE}" \
  -q "${MANIM_QUALITY}" \
  -o "${OUTPUT_DIR}"
