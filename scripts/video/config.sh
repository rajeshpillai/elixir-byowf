#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# Shared configuration for all tutorial video scripts.
# Change voice, quality, provider etc. here — every script picks it up.
# ─────────────────────────────────────────────────────────────

# TTS provider: auto | kokoro | openai
TTS_PROVIDER="${TTS_PROVIDER:-auto}"

# Voice ID (kokoro: am_adam, af_bella, bf_emma, …  openai: nova, alloy, …)
TTS_VOICE="${TTS_VOICE:-am_adam}"

# Manim render quality: low_quality | medium_quality | high_quality
MANIM_QUALITY="${MANIM_QUALITY:-medium_quality}"

# Output root (videos land in OUTPUT_DIR/<tutorial-id>/)
OUTPUT_DIR="${OUTPUT_DIR:-output}"

# ─────────────────────────────────────────────────────────────
# Paths (auto-detected relative to repo root)
# ─────────────────────────────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PIPELINE_DIR="${REPO_ROOT}/pipeline"
TUTORIALS_DIR="${REPO_ROOT}/tutorial"

# Activate the pipeline virtualenv if present
if [ -d "${PIPELINE_DIR}/.venv" ]; then
  source "${PIPELINE_DIR}/.venv/bin/activate"
fi
