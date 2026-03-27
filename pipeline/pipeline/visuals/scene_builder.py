"""Scene builder — dispatches IR blocks to Manim scene classes and renders them."""

import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from manim import config as manim_config

from ..parser.ir import Block, BlockType, TutorialIR

# Map of block types to their scene module + class
_SCENE_MAP = {
    BlockType.TITLE: ("title_card", "TitleCardScene"),
    BlockType.SECTION_HEADER: ("title_card", "TitleCardScene"),
    BlockType.SUBSECTION: ("title_card", "TitleCardScene"),
    BlockType.PROSE: ("prose_slide", "ProseSlideScene"),
    BlockType.CODE: ("code_block", "CodeBlockScene"),
    BlockType.BLOCKQUOTE: ("blockquote", "BlockquoteScene"),
    BlockType.ASCII_DIAGRAM: ("ascii_diagram", "AsciiDiagramScene"),
    BlockType.LIST: ("list_slide", "ListSlideScene"),
    BlockType.TABLE: ("table_slide", "TableSlideScene"),
}

# Default durations per block type when there's no audio to drive timing
DEFAULT_DURATIONS = {
    BlockType.TITLE: 3.0,
    BlockType.SECTION_HEADER: 2.5,
    BlockType.SUBSECTION: 2.0,
    BlockType.PROSE: 5.0,
    BlockType.CODE: 8.0,
    BlockType.BLOCKQUOTE: 5.0,
    BlockType.ASCII_DIAGRAM: 6.0,
    BlockType.LIST: 5.0,
    BlockType.TABLE: 5.0,
    BlockType.HORIZONTAL_RULE: 1.0,
}


@dataclass
class SceneSegment:
    video_path: Path
    duration: float
    block_index: int
    block_type: BlockType


def _get_scene_class(block_type: BlockType):
    """Dynamically import the scene class for a block type."""
    if block_type not in _SCENE_MAP:
        return None
    module_name, class_name = _SCENE_MAP[block_type]
    import importlib
    mod = importlib.import_module(f".scenes.{module_name}", package="pipeline.visuals")
    return getattr(mod, class_name)


def render_scene(
    block: Block,
    block_index: int,
    output_dir: Path,
    duration: float | None = None,
    quality: str = "medium_quality",
    fps: int = 30,
) -> SceneSegment | None:
    """Render a single block to a video file using Manim.

    Returns None for block types that don't have visual scenes (e.g. HORIZONTAL_RULE).
    """
    scene_cls = _get_scene_class(block.type)
    if scene_cls is None:
        return None

    dur = duration or block.duration_hint or DEFAULT_DURATIONS.get(block.type, 3.0)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Configure Manim output
    filename = f"{block_index:03d}-{block.type.name.lower()}"
    manim_config.output_file = filename
    manim_config.media_dir = str(output_dir / "manim_media")
    manim_config.quality = quality
    manim_config.frame_rate = fps
    manim_config.disable_caching = True

    # Instantiate and render
    scene = scene_cls(block, duration=dur)
    scene.render()

    # Find the rendered file
    video_dir = Path(manim_config.media_dir) / "videos"
    # Manim puts files under videos/<quality>/
    candidates = list(video_dir.rglob(f"{filename}.*"))
    if not candidates:
        # Try alternate location
        candidates = list(Path(manim_config.media_dir).rglob(f"{filename}.*"))

    if not candidates:
        raise FileNotFoundError(f"Manim did not produce output for block {block_index}")

    video_path = candidates[0]

    return SceneSegment(
        video_path=video_path,
        duration=dur,
        block_index=block_index,
        block_type=block.type,
    )


def build_all_scenes(
    tutorial: TutorialIR,
    output_dir: Path,
    durations: dict[int, float] | None = None,
    quality: str = "medium_quality",
) -> list[SceneSegment]:
    """Render all blocks in a tutorial to video segments.

    Args:
        tutorial: Parsed tutorial IR.
        output_dir: Where to put rendered video files.
        durations: Optional map of block_index -> duration (from TTS audio).
        quality: Manim quality setting.

    Returns:
        List of rendered SceneSegments, in order.
    """
    durations = durations or {}
    segments = []

    for i, block in enumerate(tutorial.blocks):
        if block.type == BlockType.HORIZONTAL_RULE:
            continue

        dur = durations.get(i)
        segment = render_scene(block, i, output_dir, duration=dur, quality=quality)
        if segment:
            segments.append(segment)

    return segments
