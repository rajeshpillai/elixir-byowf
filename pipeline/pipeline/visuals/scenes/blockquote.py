"""Blockquote scene — styled invariant/sutra callout box."""

import textwrap

from manim import (
    DOWN, LEFT, RIGHT, UP, WHITE,
    FadeIn, FadeOut, Line, Rectangle, RoundedRectangle, Scene, Text, VGroup,
)

from ...parser.ir import Block

BG_COLOR = "#1a1a2e"
QUOTE_BG = "#2a2a4e"
ACCENT = "#e94560"


class BlockquoteScene(Scene):
    """Renders a blockquote (invariant/sutra) as a styled callout box."""

    def __init__(self, block: Block, duration: float = 5.0, **kwargs):
        super().__init__(**kwargs)
        self.block = block
        self.target_duration = duration

    def construct(self):
        self.camera.background_color = BG_COLOR

        content = self.block.content.strip()
        wrapped = textwrap.fill(content, width=55)

        text = Text(
            wrapped,
            font="DejaVu Sans Mono",
            font_size=22,
            color=WHITE,
            line_spacing=1.5,
        )

        # Background box
        box = RoundedRectangle(
            width=text.width + 1.2,
            height=text.height + 0.8,
            corner_radius=0.15,
            fill_color=QUOTE_BG,
            fill_opacity=0.9,
            stroke_color=ACCENT,
            stroke_width=2,
        )

        # Left accent bar
        accent_bar = Line(
            start=box.get_left() + RIGHT * 0.1 + UP * (box.height / 2 - 0.2),
            end=box.get_left() + RIGHT * 0.1 + DOWN * (box.height / 2 - 0.2),
            color=ACCENT,
            stroke_width=4,
        )

        group = VGroup(box, accent_bar, text)
        group.move_to([0, 0, 0])

        self.play(FadeIn(box, run_time=0.3))
        self.play(FadeIn(accent_bar, run_time=0.2))
        self.play(FadeIn(text, shift=UP * 0.1), run_time=0.5)
        self.wait(max(0.3, self.target_duration - 1.5))
        self.play(FadeOut(group), run_time=0.5)
