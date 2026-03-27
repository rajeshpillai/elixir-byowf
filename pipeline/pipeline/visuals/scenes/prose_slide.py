"""Prose slide scene — narration text displayed on screen."""

import textwrap

from manim import (
    DOWN, GREY_A, UP, WHITE,
    FadeIn, FadeOut, Scene, Text, VGroup,
)

from ...parser.ir import Block

BG_COLOR = "#1a1a2e"
MAX_LINE_WIDTH = 60


class ProseSlideScene(Scene):
    """Renders a prose paragraph as readable text on a dark background."""

    def __init__(self, block: Block, duration: float = 5.0, **kwargs):
        super().__init__(**kwargs)
        self.block = block
        self.target_duration = duration

    def construct(self):
        self.camera.background_color = BG_COLOR

        content = self.block.content.strip()
        # Word-wrap to fit screen
        wrapped = textwrap.fill(content, width=MAX_LINE_WIDTH)

        # Split into chunks if too long for one screen
        lines = wrapped.split("\n")
        if len(lines) > 12:
            # Paginate: show first 12 lines, then rest
            chunks = ["\n".join(lines[i:i+12]) for i in range(0, len(lines), 12)]
        else:
            chunks = [wrapped]

        time_per_chunk = self.target_duration / len(chunks)

        for chunk in chunks:
            text = Text(
                chunk,
                font="DejaVu Sans Mono",
                font_size=24,
                color=WHITE,
                line_spacing=1.4,
            )
            # Scale down if still too wide
            if text.width > 12:
                text.scale(12 / text.width)
            text.move_to([0, 0, 0])

            self.play(FadeIn(text, shift=UP * 0.2), run_time=0.5)
            self.wait(max(0.3, time_per_chunk - 1.0))
            self.play(FadeOut(text), run_time=0.5)
