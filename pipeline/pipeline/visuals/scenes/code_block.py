"""Code block scene — syntax-highlighted code display."""

from manim import (
    DOWN, LEFT, UP, UL, WHITE,
    Code, FadeIn, FadeOut, Scene, Text,
)

from ...parser.ir import Block

BG_COLOR = "#1a1a2e"
CODE_THEME = "monokai"
MAX_LINES_PER_PAGE = 28
MAX_LINE_LENGTH = 85


class CodeBlockScene(Scene):
    """Renders a syntax-highlighted code block, paginated if needed."""

    def __init__(self, block: Block, duration: float = 8.0, **kwargs):
        super().__init__(**kwargs)
        self.block = block
        self.target_duration = duration

    def construct(self):
        self.camera.background_color = BG_COLOR

        lines = self.block.content.split("\n")
        language = self.block.language or "text"

        # Truncate very long lines
        lines = [l[:MAX_LINE_LENGTH] for l in lines]

        # Paginate long code blocks
        pages = [lines[i:i+MAX_LINES_PER_PAGE]
                 for i in range(0, len(lines), MAX_LINES_PER_PAGE)]

        time_per_page = self.target_duration / len(pages)

        for page_idx, page_lines in enumerate(pages):
            code_text = "\n".join(page_lines)

            # Language label
            lang_label = Text(
                language,
                font="DejaVu Sans Mono",
                font_size=16,
                color="#888888",
            )
            lang_label.to_corner(UL, buff=0.3)

            code = Code(
                code_string=code_text,
                language=language,
                tab_width=4,
                formatter_style=CODE_THEME,
                background="rectangle",
                background_config={
                    "stroke_color": "#333355",
                    "stroke_width": 1,
                },
                paragraph_config={
                    "font": "DejaVu Sans Mono",
                    "font_size": 16,
                },
            )
            # Scale to fit screen
            if code.width > 13:
                code.scale(13 / code.width)
            if code.height > 7:
                code.scale(7 / code.height)
            code.move_to([0, 0, 0])

            self.play(FadeIn(lang_label, run_time=0.3))
            self.play(FadeIn(code, shift=UP * 0.2), run_time=0.5)
            self.wait(max(0.3, time_per_page - 1.3))
            self.play(FadeOut(code), FadeOut(lang_label), run_time=0.5)
