# Video Generation Guide

Generate narrated video tutorials from markdown files using local TTS (Kokoro) + Manim visuals + FFmpeg composition. No LLM credits are used — everything runs locally.

## Quick Start

```bash
cd pipeline
source .venv/bin/activate

# Generate a single tutorial video
python -m pipeline generate ../tutorial/01-tcp-socket.md -o output

# Generate with options
python -m pipeline generate ../tutorial/01-tcp-socket.md \
  --voice am_adam \
  --quality medium_quality \
  -o output

# Generate all tutorials
python -m pipeline generate-all --tutorials-dir ../tutorial

# Check which tutorials have videos
python -m pipeline status --tutorials-dir ../tutorial
```

## Pipeline Stages

```
tutorial.md → Parser → IR blocks → ┬→ TTS (Kokoro) → audio clips (.wav)
                                    └→ Manim        → video clips (.mp4)
                                            ↓
                                    Timeline (align audio + visuals)
                                            ↓
                                    FFmpeg Composer → final {id}.mp4
```

### Stage 1: Parse Markdown

The parser converts tutorial markdown into typed IR blocks:

| Block Type | Source | Narration |
|------------|--------|-----------|
| TITLE | `# heading` | Heading text |
| SECTION_HEADER | `## heading` | Heading text |
| SUBSECTION | `### heading` | Heading text |
| PROSE | Paragraphs | Text with markdown stripped |
| CODE | Fenced code blocks | First comment line or generic description |
| BLOCKQUOTE | `> quoted text` | Quoted text |
| ASCII_DIAGRAM | Code blocks with diagram chars | "Here is a diagram illustrating..." |
| LIST | Bullet/numbered lists | List text |
| TABLE | Pipe-delimited tables | "Here is a table with N rows." |
| HORIZONTAL_RULE | `---` | None (visual separator) |

### Stage 2: TTS Audio

Each block's narration text is synthesized to a `.wav` file. The default provider is **Kokoro** (runs locally, no API key needed).

**Default voice**: `am_adam` (American male)

Available voice prefixes:
- `af_` — American female (e.g., `af_heart`, `af_bella`, `af_sarah`)
- `am_` — American male (e.g., `am_adam`, `am_michael`)
- `bf_` — British female (e.g., `bf_emma`)
- `bm_` — British male (e.g., `bm_george`)

Other providers:
- `--provider openai` — Uses OpenAI TTS API (requires `OPENAI_API_KEY`)
- `--provider elevenlabs` — Stub, not yet implemented

### Stage 3: Render Visuals

Each block is rendered as a Manim scene. Audio duration drives scene length (+ 0.5s padding).

| Block Type | Visual Style |
|------------|-------------|
| TITLE / SECTION_HEADER | Animated title card with accent colors |
| PROSE | Word-wrapped text, paginated if >12 lines |
| CODE | Syntax-highlighted, paginated if >28 lines |
| BLOCKQUOTE | Styled box with left accent bar |
| ASCII_DIAGRAM | Monospace cyan text |
| LIST | Bulleted items, paginated if >10 items |
| TABLE | Monospace table layout |

Quality settings (affects render time):
- `--quality low_quality` — Fast, low-res (good for testing)
- `--quality medium_quality` — Default (1920x1080, 30fps)
- `--quality high_quality` — Slow, highest quality

### Stage 4: Compose Final Video

FFmpeg combines all segments:
1. Scale/pad each visual to 1920x1080
2. Mux each video segment with its audio (or silence)
3. Concatenate all muxed segments
4. Encode final MP4 (H.264 + AAC, faststart)

## CLI Reference

```
python -m pipeline <command> [options]
```

| Command | Description |
|---------|-------------|
| `parse <path>` | Parse markdown and print IR blocks (dry run) |
| `tts <path>` | Generate TTS audio only |
| `generate <path>` | Full video: TTS + visuals + compose |
| `generate-all` | Generate videos for all tutorials |
| `status` | Show which tutorials have generated videos |

### Common Options

| Flag | Default | Description |
|------|---------|-------------|
| `--provider / -p` | `auto` | TTS provider (`kokoro`, `openai`) |
| `--voice / -v` | `default` | Voice ID (e.g., `am_adam`) |
| `--quality / -q` | `medium_quality` | Manim render quality |
| `--output-dir / -o` | `output` | Output directory |

## Sidecar Overrides

Each tutorial can have a sidecar YAML file in `overrides/` that customizes narration and visual effects per block — without modifying the tutorial markdown.

**File naming**: `overrides/{tutorial-stem}.yaml` matches the markdown filename.
- `tutorial/01-tcp-socket.md` → `overrides/01-tcp-socket.yaml`

### How It Works

1. Run `python -m pipeline parse ../tutorial/01-tcp-socket.md` to see block indices
2. Create a sidecar YAML targeting specific blocks by index
3. The pipeline auto-loads the sidecar during `parse`, `tts`, and `generate`

### Sidecar Format

```yaml
# overrides/01-tcp-socket.yaml
blocks:
  0:
    narration: >
      Welcome to Step 1. In this lesson, we'll build a TCP server
      from scratch using only Elixir's standard library.
  9:
    narration: >
      Here's a basic Elixir module. The defmodule keyword defines
      a named container for your functions.
    effect: "line_highlight"
    highlight_lines: [1, 2, 3]
  13:
    effect: "line_highlight"
    highlight_lines: [1]
    pause_after: 1.5
  20:
    duration: 10.0
```

### Supported Override Keys

| Key | Type | Description |
|-----|------|-------------|
| `narration` | string | Override auto-derived TTS narration text |
| `duration` | float | Override block duration in seconds |
| `effect` | string | Visual effect name (e.g., `line_highlight`, `zoom_in`, `pause`) |
| `highlight_lines` | list[int] | Lines to highlight in CODE blocks |
| `pause_after` | float | Extra pause in seconds after the block |
| `transition` | string | Transition style (`crossfade`, `wipe`) — future use |

Only blocks that need customization need entries — all other blocks use auto-derived narration and default visuals.

## Output Structure

```
output/
└── 01-tcp-socket/
    ├── segments/           # Intermediate TTS + Manim files (git-ignored)
    │   ├── 000-title.wav
    │   ├── 001-prose.wav
    │   ├── manim_media/    # Manim render output (git-ignored)
    │   └── ...
    └── 01-tcp-socket.mp4   # Final video (committed to git)
```

## Dependencies

- Python 3.12+
- FFmpeg (system package)
- manim >= 0.18
- kokoro >= 0.9 (default TTS, runs locally)
- click, pyyaml, soundfile

## Tips

- First run downloads the Kokoro model (~300MB) from HuggingFace — subsequent runs are instant.
- Use `--quality low_quality` for fast test renders.
- Use `parse` command first to inspect how your markdown is interpreted.
- Final `.mp4` files are committed to git; intermediate files under `segments/` and `manim_media/` are git-ignored.
