#!/usr/bin/env python3
"""Generate sidecar override YAML files for all tutorials.

Produces improved narration for:
- TITLE blocks: contextual welcome intro
- CODE blocks: derives context from preceding prose instead of generic
  "Here is the elixir implementation."
- First SECTION_HEADER: adds transition phrasing

Also adds line_highlight effects on code blocks preceded by explanatory prose.

Usage:
    python generate_sidecars.py ../tutorial/
"""

import re
import sys
from pathlib import Path

# Add pipeline to path
sys.path.insert(0, str(Path(__file__).parent))

from pipeline.parser.markdown import parse_tutorial
from pipeline.parser.ir import BlockType

# Step descriptions for richer title narration
STEP_INTROS = {
    "00": "Welcome to step zero. Let's set up the Elixir project from scratch using Mix.",
    "01": "Welcome to Step 1. In this lesson, we'll build a TCP server from scratch using only Elixir's standard library. By the end, you'll have a working HTTP server that responds to browser requests.",
    "02": "Welcome to Step 2. We'll create a Conn struct to represent HTTP requests and responses, and build a parser to turn raw TCP data into structured Elixir data.",
    "03": "Welcome to Step 3. Now we'll build a router using Elixir macros. This is where metaprogramming shines — we'll create a DSL that feels like Phoenix's router.",
    "04": "Welcome to Step 4. Let's add response helpers like text and render. These turn our Conn struct into a proper HTTP response with headers and status codes.",
    "05": "Welcome to Step 5. We'll add dynamic routes with URL parameters. When someone visits slash users slash 42, we need to extract that 42 and pass it to the handler.",
    "06": "Welcome to Step 6. Time for OTP — the heart of Elixir. We'll wrap our server in a GenServer and add supervision so it restarts automatically on failure.",
    "07": "Welcome to Step 7. We'll add EEx templates — Elixir's built-in templating system. This lets us render HTML with embedded Elixir code, like ERB in Ruby.",
    "08": "Welcome to Step 8. Let's build a middleware pipeline, similar to Plug in Phoenix. Each middleware transforms the connection struct before and after the handler.",
    "09": "Welcome to Step 9. We need to handle POST requests with form data. We'll build a body parser that decodes URL-encoded form submissions.",
    "10": "Welcome to Step 10. We'll swap our hand-built TCP server for Cowboy, a production-grade HTTP server. This is the adapter pattern in action.",
    "11": "Welcome to Step 11. Let's add proper error handling. When something goes wrong, our framework should show a helpful 500 error page instead of crashing.",
    "12": "Welcome to Step 12. This is a big one — we're building LiveView. A WebSocket-powered system that lets us build interactive UIs without writing JavaScript.",
    "13": "Welcome to Step 13. We need client-side JavaScript to connect the browser to our LiveView WebSocket. Let's build the frontend glue code.",
    "14": "Welcome to Step 14. LiveView sends full HTML on every update — wasteful. Let's build a diffing engine that only sends what changed.",
    "15": "Welcome to Step 15. Let's add hot code reloading. When you save a file, the browser updates automatically — no manual refresh needed.",
    "16": "Welcome to Step 16. Instead of replacing the entire DOM, let's use morphdom to efficiently patch only the elements that changed.",
    "17": "Welcome to Step 17. We'll build PubSub — a publish-subscribe system that lets LiveView processes broadcast messages to each other.",
    "18": "Welcome to Step 18. Let's add live navigation so clicking links doesn't cause a full page reload. The browser stays connected via WebSocket.",
    "19": "Welcome to Step 19. We'll build LiveComponents — reusable, stateful UI components that can be embedded inside LiveView pages.",
    "20": "Welcome to Step 20. JavaScript Hooks let us run custom client-side code tied to specific DOM elements. Perfect for charts, maps, or animations.",
    "21": "Welcome to Step 21. Let's add a JSON API helper. Sometimes you need your routes to return JSON instead of HTML.",
    "22": "Welcome to Step 22. We'll add support for PUT, PATCH, and DELETE HTTP methods. This completes our RESTful routing system.",
    "23": "Welcome to Step 23. Scoped routes let us group related routes under a common prefix, like slash admin or slash API.",
    "24": "Welcome to Step 24. We'll build a custom EEx engine that separates static HTML from dynamic parts at compile time, enabling fine-grained diffs.",
    "25": "Welcome to Step 25. Streams let LiveView efficiently render large lists without keeping all items in memory on the server.",
    "26": "Welcome to Step 26. Let's handle file uploads. We'll parse multipart form data and support WebSocket-based uploads for LiveView.",
    "27": "Welcome to Step 27. Path helpers generate URL paths from route names at compile time, so you never have to hardcode URLs.",
    "28": "Welcome to Step 28. Flash messages show one-time notifications after redirects. We'll implement them using signed cookie sessions.",
    "29": "Welcome to Step 29. Presence tracking shows who's online in real time. We'll use process monitoring and GenServer to track connected users.",
    "30": "Welcome to Step 30. Let's integrate Ecto for database persistence. We'll add SQLite, define schemas, and write changesets.",
    "31": "Welcome to Step 31. CSRF protection prevents cross-site request forgery attacks. We'll add token generation and validation to all forms.",
    "32": "Welcome to Step 32. Content Security Policy headers tell browsers which resources are allowed to load, preventing XSS attacks.",
    "33": "Welcome to Step 33. Let's build a Mix task that prints all registered routes — handy for debugging and documentation.",
    "34": "Welcome to Step 34. When an error occurs in development, we want a rich debug page with the stacktrace, request details, and source code.",
    "35": "Welcome to Step 35. Logger metadata lets us attach request IDs and timing information to every log line for better observability.",
    "36": "Welcome to Step 36. A health check endpoint lets load balancers and monitoring systems verify that our application is running.",
    "37": "Welcome to Step 37. We'll build a static asset pipeline with content-based cache busting. Change a CSS file, and the URL changes automatically.",
    "38": "Welcome to Step 38. Test helpers make it easy to write integration tests for our framework. We'll build a ConnTest module inspired by Phoenix.",
    "39": "Welcome to Step 39. Let's add SSL and TLS support so our server can handle HTTPS connections securely.",
    "40": "Welcome to Step 40. Time to prepare for production. We'll configure a Mix release and add an ETS-based rate limiter.",
    "41": "Welcome to Step 41. We'll enhance streams with upsert support and client-side limits for efficient list rendering.",
    "42": "Welcome to Step 42. FEEx templates bring a new sigil syntax with at-sign shorthand for assigns, blocks, and auto-escaping.",
    "43": "Welcome to Step 43. This is the capstone project — a full Todo application using LiveView, Streams, Ecto, and FEEx templates.",
    "44": "Welcome to Step 44. Let's harden our LiveView for production with automatic reconnection, scoped events, and a status UI.",
}


def _last_sentence(text: str) -> str:
    """Extract the last meaningful sentence from prose."""
    text = text.strip().rstrip(".")
    sentences = [s.strip() for s in text.split(".") if s.strip()]
    if sentences:
        return sentences[-1]
    return text


def _first_sentence(text: str) -> str:
    """Extract the first sentence from prose."""
    m = re.match(r"^(.+?\.)\s", text)
    if m:
        return m.group(1)
    return text[:200]


def _strip_markdown(text: str) -> str:
    """Strip markdown formatting for clean TTS narration."""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)  # bold
    text = re.sub(r"\*(.+?)\*", r"\1", text)  # italic
    text = re.sub(r"`(.+?)`", r"\1", text)  # inline code
    text = re.sub(r"\[(.+?)\]\(.+?\)", r"\1", text)  # links
    text = re.sub(r"[`]", "", text)  # stray backticks
    return text.strip()


def _context_from_prose(prose: str, lang: str) -> str:
    """Generate code block narration from preceding prose context."""
    prose = _strip_markdown(prose.strip())
    # If prose ends with a colon, it's introducing the code
    if prose.rstrip().endswith(":"):
        intro = prose.rstrip().rstrip(":")
        last = _last_sentence(intro)
        return f"Let's look at the code. {last}."

    # Use the first sentence for cleaner context (last sentence often has
    # markdown artifacts or is a sentence fragment)
    first = _first_sentence(prose)
    if len(first) > 15 and len(first) < 200:
        return f"Here's how this looks in {lang}. {first}"

    return f"Let's see the {lang} code for this."


def generate_sidecar(tutorial_path: Path) -> dict | None:
    """Generate sidecar overrides for a tutorial."""
    tut = parse_tutorial(tutorial_path)
    stem = tutorial_path.stem
    step_num = re.match(r"(\d+)", stem)
    step_id = step_num.group(1) if step_num else stem

    blocks_overrides = {}

    # Title block — add welcoming intro
    if step_id in STEP_INTROS:
        blocks_overrides[0] = {"narration": STEP_INTROS[step_id]}

    # Walk blocks and improve code narration
    prev_prose = None
    first_section = True
    for i, block in enumerate(tut.blocks):
        if block.type == BlockType.PROSE:
            prev_prose = block.content
            continue

        if block.type == BlockType.SECTION_HEADER and first_section:
            first_section = False
            # Add a transitional intro to the first section
            blocks_overrides[i] = {
                "narration": f"Let's start with: {block.content}."
            }
            continue

        if block.type == BlockType.CODE and block.language:
            lang = block.language
            auto_narration = block.narration or ""

            # Only override generic narrations
            if auto_narration.startswith("Here is the") and prev_prose:
                narration = _context_from_prose(prev_prose, lang)
                override = {"narration": narration}

                # Add highlight effect for significant code blocks (>3 lines)
                code_lines = block.content.strip().split("\n")
                if len(code_lines) >= 3:
                    # Highlight first few meaningful lines
                    highlight = []
                    for li, line in enumerate(code_lines[:15], 1):
                        stripped = line.strip()
                        if stripped and not stripped.startswith(("#", "//", "/*", "*")):
                            highlight.append(li)
                            if len(highlight) >= 3:
                                break
                    if highlight:
                        override["effect"] = "line_highlight"
                        override["highlight_lines"] = highlight

                blocks_overrides[i] = override

        if block.type == BlockType.ASCII_DIAGRAM and prev_prose:
            context = _last_sentence(_strip_markdown(prev_prose))
            if len(context) > 10:
                blocks_overrides[i] = {
                    "narration": f"Take a look at this diagram. It illustrates {context.lower()}."
                }

    if not blocks_overrides:
        return None

    return blocks_overrides


def write_sidecar(tutorial_path: Path, overrides_dir: Path):
    """Generate and write a sidecar YAML file."""
    stem = tutorial_path.stem
    out_path = overrides_dir / f"{stem}.yaml"

    # Skip if already exists (don't overwrite hand-crafted sidecars)
    if out_path.exists():
        print(f"  SKIP {stem} (sidecar exists)")
        return

    blocks = generate_sidecar(tutorial_path)
    if blocks is None:
        print(f"  SKIP {stem} (no overrides needed)")
        return

    # Write YAML manually to control formatting
    lines = [
        f"# Sidecar overrides for {stem}",
        f"# Generated — edit freely to customize narration and effects.",
        f"# Use `python -m pipeline parse ../tutorial/{stem}.md` to see block indices.",
        "",
        "blocks:",
    ]

    for idx in sorted(blocks.keys()):
        override = blocks[idx]
        lines.append(f"  {idx}:")
        for key, value in override.items():
            if key == "narration":
                # Use YAML folded scalar for narration
                lines.append(f"    narration: >")
                # Word-wrap at ~76 chars
                words = value.split()
                current_line = "      "
                for word in words:
                    if len(current_line) + len(word) + 1 > 78:
                        lines.append(current_line)
                        current_line = f"      {word}"
                    else:
                        if current_line.strip():
                            current_line += f" {word}"
                        else:
                            current_line = f"      {word}"
                if current_line.strip():
                    lines.append(current_line)
            elif key == "highlight_lines":
                lines.append(f"    highlight_lines: {value}")
            elif key == "effect":
                lines.append(f'    effect: "{value}"')
            else:
                lines.append(f"    {key}: {value}")

    content = "\n".join(lines) + "\n"
    out_path.write_text(content, encoding="utf-8")
    print(f"  WROTE {out_path} ({len(blocks)} block overrides)")


def main():
    if len(sys.argv) < 2:
        print("Usage: python generate_sidecars.py <tutorials-dir>")
        sys.exit(1)

    tutorials_dir = Path(sys.argv[1])
    overrides_dir = Path("overrides")
    overrides_dir.mkdir(exist_ok=True)

    md_files = sorted(tutorials_dir.glob("*.md"))
    print(f"Found {len(md_files)} tutorials\n")

    for md_path in md_files:
        write_sidecar(md_path, overrides_dir)

    print(f"\nDone. Sidecars are in {overrides_dir}/")


if __name__ == "__main__":
    main()
