"""ASCII diagram scene — render monospace ASCII art as Manim Text."""

from manim import (
    UP, WHITE,
    FadeIn, FadeOut, Scene, Text,
)

from ...parser.ir import Block

BG_COLOR = "#1a1a2e"
DIAGRAM_COLOR = "#4ecdc4"
MAX_LINES = 24


class AsciiDiagramScene(Scene):
    """Renders an ASCII diagram as styled monospace text."""

    def __init__(self, block: Block, duration: float = 6.0, **kwargs):
        super().__init__(**kwargs)
        self.block = block
        self.target_duration = duration

    def construct(self):
        self.camera.background_color = BG_COLOR

        lines = self.block.content.split("\n")

        # Paginate if needed
        pages = [lines[i:i+MAX_LINES] for i in range(0, len(lines), MAX_LINES)]
        time_per_page = self.target_duration / len(pages)

        for page_lines in pages:
            content = "\n".join(page_lines)
            text = Text(
                content,
                font="DejaVu Sans Mono",
                font_size=18,
                color=DIAGRAM_COLOR,
                line_spacing=1.1,
            )
            # Scale to fit
            if text.width > 13:
                text.scale(13 / text.width)
            if text.height > 7:
                text.scale(7 / text.height)
            text.move_to([0, 0, 0])

            self.play(FadeIn(text, shift=UP * 0.2), run_time=0.5)
            self.wait(max(0.3, time_per_page - 1.0))
            self.play(FadeOut(text), run_time=0.5)
