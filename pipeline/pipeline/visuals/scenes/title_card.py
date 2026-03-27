"""Title card scene — tutorial title and section headers."""

from manim import (
    BLACK, BLUE, DOWN, GRAY_A, GREY_A, UP, WHITE,
    Create, FadeIn, FadeOut, Scene, Text, Underline, VGroup, Write,
    config as manim_config,
)

from ...parser.ir import Block, BlockType

# Dark background color
BG_COLOR = "#1a1a2e"
ACCENT_COLOR = "#e94560"
SECTION_COLORS = {
    "concepts": "#4ecdc4",
    "building": "#ffe66d",
    "code": "#ff6b6b",
}


class TitleCardScene(Scene):
    """Renders a title card for the tutorial or a section header."""

    def __init__(self, block: Block, duration: float = 3.0, **kwargs):
        super().__init__(**kwargs)
        self.block = block
        self.target_duration = duration

    def construct(self):
        self.camera.background_color = BG_COLOR

        if self.block.type == BlockType.TITLE:
            self._render_title()
        elif self.block.type == BlockType.SECTION_HEADER:
            self._render_section_header()
        else:
            self._render_subsection()

    def _render_title(self):
        title = Text(
            self.block.content,
            font="DejaVu Sans Mono",
            font_size=44,
            color=WHITE,
        )
        # Wrap long titles
        if len(self.block.content) > 40:
            title.font_size = 36

        underline = Underline(title, color=ACCENT_COLOR, buff=0.2)

        group = VGroup(title, underline)
        group.move_to([0, 0, 0])

        self.play(FadeIn(title, shift=UP * 0.3), run_time=0.8)
        self.play(Create(underline), run_time=0.5)
        self.wait(max(0.5, self.target_duration - 1.3))
        self.play(FadeOut(group), run_time=0.5)

    def _render_section_header(self):
        content = self.block.content
        # Detect section type for color
        color = WHITE
        for key, c in SECTION_COLORS.items():
            if key in content.lower():
                color = c
                break

        # Split on " — " or "(" to get main name and subtitle
        parts = content.replace("(", "— ").replace(")", "").split("—")
        main = parts[0].strip()
        subtitle = parts[1].strip() if len(parts) > 1 else ""

        main_text = Text(main, font="DejaVu Sans Mono", font_size=48, color=color)
        group = VGroup(main_text)

        if subtitle:
            sub_text = Text(subtitle, font="DejaVu Sans Mono", font_size=28, color=GREY_A)
            sub_text.next_to(main_text, DOWN, buff=0.4)
            group.add(sub_text)

        group.move_to([0, 0, 0])

        self.play(FadeIn(group, shift=UP * 0.3), run_time=0.7)
        self.wait(max(0.3, self.target_duration - 1.2))
        self.play(FadeOut(group), run_time=0.5)

    def _render_subsection(self):
        text = Text(
            self.block.content,
            font="DejaVu Sans Mono",
            font_size=36,
            color=GRAY_A,
        )
        text.move_to([0, 0, 0])

        self.play(FadeIn(text, shift=UP * 0.2), run_time=0.5)
        self.wait(max(0.3, self.target_duration - 1.0))
        self.play(FadeOut(text), run_time=0.5)
