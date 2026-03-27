"""Table slide scene — renders markdown tables as monospace text."""

from manim import (
    UP, WHITE,
    FadeIn, FadeOut, Scene, Text,
)

from ...parser.ir import Block

BG_COLOR = "#1a1a2e"
TABLE_COLOR = "#e8e8e8"
HEADER_COLOR = "#4ecdc4"


class TableSlideScene(Scene):
    """Renders a markdown table as styled monospace text."""

    def __init__(self, block: Block, duration: float = 6.0, **kwargs):
        super().__init__(**kwargs)
        self.block = block
        self.target_duration = duration

    def construct(self):
        self.camera.background_color = BG_COLOR

        lines = self.block.content.strip().split("\n")
        # Remove separator lines (e.g., |---|---|)
        display_lines = [l for l in lines if not all(c in "-|: " for c in l)]

        content = "\n".join(display_lines)
        text = Text(
            content,
            font="DejaVu Sans Mono",
            font_size=18,
            color=TABLE_COLOR,
            line_spacing=1.3,
        )
        # Scale to fit
        if text.width > 13:
            text.scale(13 / text.width)
        if text.height > 7:
            text.scale(7 / text.height)
        text.move_to([0, 0, 0])

        self.play(FadeIn(text, shift=UP * 0.2), run_time=0.5)
        self.wait(max(0.3, self.target_duration - 1.0))
        self.play(FadeOut(text), run_time=0.5)
