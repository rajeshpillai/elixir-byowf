"""List slide scene — renders markdown lists as styled bullet points."""

import textwrap

from manim import (
    DOWN, LEFT, UP, WHITE,
    FadeIn, FadeOut, Scene, Text, VGroup,
)

from ...parser.ir import Block

BG_COLOR = "#1a1a2e"
BULLET_COLOR = "#4ecdc4"
TEXT_COLOR = WHITE
MAX_ITEMS_PER_PAGE = 10


class ListSlideScene(Scene):
    """Renders a list block as styled bullet points."""

    def __init__(self, block: Block, duration: float = 5.0, **kwargs):
        super().__init__(**kwargs)
        self.block = block
        self.target_duration = duration

    def construct(self):
        self.camera.background_color = BG_COLOR

        lines = [l.strip() for l in self.block.content.strip().split("\n") if l.strip()]

        # Paginate if needed
        pages = [lines[i:i+MAX_ITEMS_PER_PAGE]
                 for i in range(0, len(lines), MAX_ITEMS_PER_PAGE)]
        time_per_page = self.target_duration / len(pages)

        for page_lines in pages:
            items = VGroup()
            for line in page_lines:
                # Clean up markdown list markers
                clean = line.lstrip("-*•0123456789.) ")
                wrapped = textwrap.fill(clean, width=60)
                item = Text(
                    f"  •  {wrapped}",
                    font="DejaVu Sans Mono",
                    font_size=20,
                    color=TEXT_COLOR,
                    line_spacing=1.2,
                )
                items.add(item)

            items.arrange(DOWN, aligned_edge=LEFT, buff=0.25)
            # Scale to fit
            if items.width > 12:
                items.scale(12 / items.width)
            if items.height > 6.5:
                items.scale(6.5 / items.height)
            items.move_to([0, 0, 0])

            self.play(FadeIn(items, shift=UP * 0.2), run_time=0.5)
            self.wait(max(0.3, time_per_page - 1.0))
            self.play(FadeOut(items), run_time=0.5)
