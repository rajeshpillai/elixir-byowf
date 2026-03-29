"""Intermediate representation for parsed tutorial markdown files.

The IR is a flat sequence of typed blocks — the contract between
the parser, TTS, visual scene generator, and composer stages.
"""

from dataclasses import dataclass, field
from enum import Enum, auto


class BlockType(Enum):
    TITLE = auto()
    SECTION_HEADER = auto()
    SUBSECTION = auto()
    PROSE = auto()
    CODE = auto()
    ASCII_DIAGRAM = auto()
    BLOCKQUOTE = auto()
    TABLE = auto()
    LIST = auto()
    HORIZONTAL_RULE = auto()


@dataclass
class Block:
    type: BlockType
    content: str
    language: str | None = None
    narration: str | None = None
    duration_hint: float | None = None
    metadata: dict = field(default_factory=dict)
    effects: dict = field(default_factory=dict)


@dataclass
class TutorialIR:
    source_path: str
    tutorial_id: str
    title: str
    blocks: list[Block] = field(default_factory=list)

    def narrated_blocks(self) -> list[Block]:
        """Return only blocks that have narration text."""
        return [b for b in self.blocks if b.narration]

    def blocks_of_type(self, *types: BlockType) -> list[Block]:
        return [b for b in self.blocks if b.type in types]
