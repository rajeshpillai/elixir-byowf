# Kata-to-Video Pipeline

Automated video tutorial generator for cs-minds katas.

## Architecture

```
kata.md → Parser → IR blocks → ┬→ TTS Provider → audio clips (.wav)
                                └→ Scene Builder → video clips (.mp4)
                                        ↓
                                Timeline (align audio + visuals)
                                        ↓
                                FFmpeg Composer → final video.mp4
```

## Quick Start

```bash
cd pipeline
python3 -m venv .venv
source .venv/bin/activate
pip install -e .

# Parse a kata (inspect the IR — no deps needed beyond click)
python -m pipeline parse ../katas/05-graphics-text/01-framebuffers.md

# Generate TTS audio only
python -m pipeline tts ../katas/00-first-light/01-thinking-in-steps.md

# Generate full video (TTS + Manim visuals + FFmpeg compose)
python -m pipeline generate ../katas/05-graphics-text/01-framebuffers.md

# Generate all katas
python -m pipeline generate-all --katas-dir ../katas

# Check status
python -m pipeline status --katas-dir ../katas
```

## Pipeline Stages

### 1. Parser (`pipeline/parser/`)
Converts kata markdown into a flat IR (intermediate representation) of typed blocks:
- TITLE, SECTION_HEADER, SUBSECTION
- PROSE, CODE, ASCII_DIAGRAM, BLOCKQUOTE, TABLE, LIST

Each block gets auto-derived narration text (what the TTS should say).

### 2. TTS (`pipeline/tts/`)
Swappable text-to-speech providers behind a common interface:

| Provider | Status | Install |
|----------|--------|---------|
| Kokoro | Default (local, free) | `pip install kokoro` |
| OpenAI TTS | Ready | `pip install openai` + API key |
| ElevenLabs | Stub | `pip install elevenlabs` + API key |

Switch providers via CLI flag: `--provider kokoro` / `--provider openai`

### 3. Visuals (`pipeline/visuals/`)
Manim-based scene rendering per block type:

| Block Type | Scene | Style |
|------------|-------|-------|
| TITLE / SECTION_HEADER | Title card | Animated text with accent colors |
| PROSE | Prose slide | Word-wrapped text on dark background |
| CODE | Code block | Syntax-highlighted, paginated for long blocks |
| BLOCKQUOTE | Callout box | Styled box with accent bar (invariants/sutras) |
| ASCII_DIAGRAM | Diagram | Monospace text in diagram color |

### 4. Composer (`pipeline/composer/`)
- **Timeline**: Aligns audio + visual segments. Audio drives timing.
- **FFmpeg**: Concatenates segments, mixes audio, outputs final MP4 (1920x1080 H.264 + AAC).

## Configuration

Global defaults in `pipeline/config.py`. Per-kata overrides in `overrides/<kata-id>.yaml`:

```yaml
# overrides/05-01.yaml
tts_voice: "af_heart"
tts_speed: 0.9
```

## Dependencies

- Python 3.12+
- FFmpeg (system)
- manim >= 0.18
- kokoro >= 0.9 (default TTS)
- click, pyyaml, soundfile

## Phased Roadmap

### Phase 1 (MVP) — Done
Narrated slideshow: title cards + prose slides + code display + blockquotes + voice narration.

### Phase 2 — Animated code + tables
- Line-by-line code reveal with highlight
- Truth table and markdown table rendering
- Crossfade transitions

### Phase 3 — Template-based diagram animations
- Tree diagrams (ASCII trees → Manim Graph)
- Memory layout grids with highlighted cells
- 2D pixel grids (framebuffers)
- Auto-classify ASCII diagram type

### Phase 4 — Cloud TTS + polish
- OpenAI / ElevenLabs full implementation
- Content-hash caching (skip unchanged segments)
- Background music support
- Per-kata custom Manim scene overrides
- Parallel segment rendering
