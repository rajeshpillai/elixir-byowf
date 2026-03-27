"""Parse tutorial markdown files into the IR (flat sequence of typed blocks).

Handles the tutorial structure:
  # Title
  ## Section headers
  ### Subsections
  Prose paragraphs, code blocks, ASCII diagrams, blockquotes, tables, lists.
"""

import re
from pathlib import Path

from .ir import Block, BlockType, TutorialIR

# Characters that suggest an ASCII diagram rather than code
_DIAGRAM_CHARS = set("+-|/\\><=^v{}[]#")
_DIAGRAM_THRESHOLD = 0.15  # fraction of non-space chars that are diagram chars


def _is_ascii_diagram(text: str) -> bool:
    """Heuristic: a fenced block with no language tag is a diagram if it
    contains enough box-drawing / structural characters."""
    non_space = [c for c in text if not c.isspace()]
    if not non_space:
        return False
    diagram_count = sum(1 for c in non_space if c in _DIAGRAM_CHARS)
    return diagram_count / len(non_space) > _DIAGRAM_THRESHOLD


def _strip_markdown_inline(text: str) -> str:
    """Strip bold, italic, code, and link markdown for narration."""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)  # bold
    text = re.sub(r"\*(.+?)\*", r"\1", text)  # italic
    text = re.sub(r"`(.+?)`", r"\1", text)  # inline code
    text = re.sub(r"\[(.+?)\]\(.+?\)", r"\1", text)  # links
    return text.strip()


# Unicode symbols that TTS engines mispronounce — map to speakable text
_TTS_SYMBOL_MAP = {
    "→": " arrow ",
    "←": " left arrow ",
    "↔": " double arrow ",
    "∫": " integral ",
    "π": " pi ",
    "λ": " lambda ",
    "²": " squared ",
    "³": " cubed ",
    "√": " square root ",
    "≈": " approximately ",
    "≠": " not equal to ",
    "≤": " less than or equal to ",
    "≥": " greater than or equal to ",
    "×": " times ",
    "÷": " divided by ",
    "·": " dot ",
    "∞": " infinity ",
    "∑": " summation ",
    "∏": " product ",
    "∈": " in ",
    "∉": " not in ",
    "⊂": " subset of ",
    "⊆": " subset or equal to ",
    "∪": " union ",
    "∩": " intersection ",
    "∅": " empty set ",
    "∀": " for all ",
    "∃": " there exists ",
    "Δ": " delta ",
    "θ": " theta ",
    "α": " alpha ",
    "β": " beta ",
    "γ": " gamma ",
    "ε": " epsilon ",
    "σ": " sigma ",
    "μ": " mu ",
    "ω": " omega ",
    "φ": " phi ",
    "ψ": " psi ",
    "─": "-",
    "│": "|",
    "┌": "+",
    "┐": "+",
    "└": "+",
    "┘": "+",
    "├": "+",
    "┤": "+",
    "█": "",
    "░": "",
    "╱": "/",
    "╲": "\\",
}

# Maximum narration length before splitting (characters). Keeps TTS chunks manageable.
_MAX_NARRATION_CHARS = 500


def _sanitize_narration(text: str | None) -> str | None:
    """Clean narration text for TTS: replace symbols, cap length."""
    if not text:
        return text
    for symbol, replacement in _TTS_SYMBOL_MAP.items():
        text = text.replace(symbol, replacement)
    # Collapse multiple spaces
    text = re.sub(r"  +", " ", text).strip()
    # Cap very long narrations
    if len(text) > _MAX_NARRATION_CHARS:
        # Cut at sentence boundary
        truncated = text[:_MAX_NARRATION_CHARS]
        last_period = truncated.rfind(".")
        if last_period > _MAX_NARRATION_CHARS // 2:
            text = truncated[:last_period + 1]
        else:
            text = truncated.rstrip() + "."
    return text


def _derive_narration(block: Block, prev_prose: str | None = None) -> str | None:
    """Derive narration text from a block."""
    match block.type:
        case BlockType.TITLE:
            return block.content
        case BlockType.SECTION_HEADER:
            return block.content
        case BlockType.SUBSECTION:
            return block.content
        case BlockType.PROSE:
            return _strip_markdown_inline(block.content)
        case BlockType.BLOCKQUOTE:
            return _strip_markdown_inline(block.content)
        case BlockType.CODE:
            # Extract first comment line as context, or use generic intro
            lines = block.content.strip().split("\n")
            comments = [l.lstrip("# ").lstrip("// ").strip()
                        for l in lines if l.strip().startswith(("#", "//"))]
            if comments and len(comments[0]) > 10:
                lang = block.language or "code"
                return f"Here is the {lang} implementation. {comments[0]}"
            lang = block.language or "code"
            return f"Here is the {lang} implementation."
        case BlockType.ASCII_DIAGRAM:
            if prev_prose:
                # Use last sentence of preceding prose as context
                sentences = prev_prose.rstrip(".").split(".")
                context = sentences[-1].strip() if sentences else "the concept"
                return f"Here is a diagram illustrating {context.lower()}."
            return "Here is a diagram."
        case BlockType.LIST:
            return _strip_markdown_inline(block.content)
        case BlockType.TABLE:
            # Summarize rather than read cell-by-cell
            rows = block.content.strip().split("\n")
            if rows:
                return f"Here is a table with {len(rows)} rows."
            return None
        case BlockType.HORIZONTAL_RULE:
            return None
    return None


def _extract_tutorial_id(path: str) -> str:
    """Extract tutorial ID like '01' from path like 'tutorial/01-tcp-socket.md'."""
    stem = Path(path).stem
    m = re.match(r"(\d+)", stem)
    if m:
        return m.group(1)
    return stem


def parse_tutorial(filepath: str | Path) -> TutorialIR:
    """Parse a tutorial markdown file into a TutorialIR."""
    filepath = Path(filepath)
    text = filepath.read_text(encoding="utf-8")
    lines = text.split("\n")

    blocks: list[Block] = []
    title = ""
    i = 0

    while i < len(lines):
        line = lines[i]

        # --- Horizontal rule ---
        if re.match(r"^---+\s*$", line):
            blocks.append(Block(type=BlockType.HORIZONTAL_RULE, content="---"))
            i += 1
            continue

        # --- Headers ---
        header_match = re.match(r"^(#{1,3})\s+(.+)$", line)
        if header_match:
            level = len(header_match.group(1))
            text_content = header_match.group(2).strip()
            if level == 1:
                title = text_content
                blocks.append(Block(type=BlockType.TITLE, content=text_content))
            elif level == 2:
                blocks.append(Block(type=BlockType.SECTION_HEADER, content=text_content))
            else:
                blocks.append(Block(type=BlockType.SUBSECTION, content=text_content))
            i += 1
            continue

        # --- Fenced code block ---
        fence_match = re.match(r"^```(\w*)$", line)
        if fence_match:
            language = fence_match.group(1) or None
            code_lines = []
            i += 1
            while i < len(lines) and not re.match(r"^```\s*$", lines[i]):
                code_lines.append(lines[i])
                i += 1
            i += 1  # skip closing ```
            content = "\n".join(code_lines)
            if language is None and _is_ascii_diagram(content):
                blocks.append(Block(type=BlockType.ASCII_DIAGRAM, content=content))
            else:
                blocks.append(Block(type=BlockType.CODE, content=content, language=language))
            continue

        # --- Blockquote ---
        if line.startswith(">"):
            quote_lines = []
            while i < len(lines) and lines[i].startswith(">"):
                quote_lines.append(lines[i].lstrip("> ").strip())
                i += 1
            blocks.append(Block(type=BlockType.BLOCKQUOTE, content=" ".join(quote_lines)))
            continue

        # --- Table (lines with | separators) ---
        if "|" in line and re.match(r"^\s*\|", line):
            table_lines = []
            while i < len(lines) and "|" in lines[i]:
                # Skip separator rows (|---|---|)
                if not re.match(r"^\s*\|[\s\-:]+\|\s*$", lines[i]):
                    table_lines.append(lines[i].strip())
                i += 1
            if table_lines:
                blocks.append(Block(type=BlockType.TABLE, content="\n".join(table_lines)))
            continue

        # --- Ordered/unordered list ---
        list_match = re.match(r"^(\d+\.|[-*])\s+", line)
        if list_match:
            list_lines = []
            while i < len(lines) and (re.match(r"^(\d+\.|[-*])\s+", lines[i]) or
                                       (lines[i].startswith("   ") and list_lines)):
                list_lines.append(lines[i].strip())
                i += 1
            blocks.append(Block(
                type=BlockType.LIST,
                content="\n".join(list_lines),
                metadata={"ordered": bool(re.match(r"^\d+\.", list_lines[0]))}
            ))
            continue

        # --- Prose paragraph ---
        if line.strip():
            para_lines = []
            while i < len(lines) and lines[i].strip() and not any([
                re.match(r"^#{1,3}\s+", lines[i]),
                re.match(r"^```", lines[i]),
                lines[i].startswith(">"),
                re.match(r"^---+\s*$", lines[i]),
                re.match(r"^(\d+\.|[-*])\s+", lines[i]),
                re.match(r"^\s*\|", lines[i]),
            ]):
                para_lines.append(lines[i])
                i += 1
            blocks.append(Block(type=BlockType.PROSE, content=" ".join(para_lines)))
            continue

        # Skip blank lines
        i += 1

    # Remove empty blocks
    blocks = [b for b in blocks if b.content.strip()]

    # Derive narration for all blocks
    prev_prose = None
    for block in blocks:
        block.narration = _sanitize_narration(_derive_narration(block, prev_prose))
        if block.type == BlockType.PROSE:
            prev_prose = block.content

    tutorial_id = _extract_tutorial_id(str(filepath))

    return TutorialIR(
        source_path=str(filepath),
        tutorial_id=tutorial_id,
        title=title or filepath.stem,
        blocks=blocks,
    )
