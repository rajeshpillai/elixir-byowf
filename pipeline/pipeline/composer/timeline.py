"""Timeline — aligns TTS audio segments with visual scene segments."""

from dataclasses import dataclass
from pathlib import Path

from ..parser.ir import BlockType, TutorialIR
from ..tts.base import TTSResult
from ..visuals.scene_builder import SceneSegment


@dataclass
class TimelineEntry:
    block_index: int
    visual_path: Path | None
    audio_path: Path | None
    duration: float
    start_time: float


class Timeline:
    """Sequence of aligned audio + visual segments for compositing."""

    def __init__(self):
        self.entries: list[TimelineEntry] = []

    @property
    def total_duration(self) -> float:
        if not self.entries:
            return 0.0
        last = self.entries[-1]
        return last.start_time + last.duration

    @classmethod
    def from_segments(
        cls,
        tutorial: TutorialIR,
        audio_results: dict[int, TTSResult],
        visual_segments: list[SceneSegment],
    ) -> "Timeline":
        """Build a timeline from TTS results and rendered scenes.

        Audio drives timing: if a block has audio, its duration is the audio length.
        Visual segments are matched by block_index.
        """
        timeline = cls()
        visual_map = {s.block_index: s for s in visual_segments}
        current_time = 0.0

        for i, block in enumerate(tutorial.blocks):
            if block.type == BlockType.HORIZONTAL_RULE:
                # Small gap
                timeline.entries.append(TimelineEntry(
                    block_index=i,
                    visual_path=None,
                    audio_path=None,
                    duration=0.5,
                    start_time=current_time,
                ))
                current_time += 0.5
                continue

            audio = audio_results.get(i)
            visual = visual_map.get(i)

            if audio is None and visual is None:
                continue

            # Audio drives duration; fall back to visual duration
            if audio:
                duration = audio.duration_seconds + 0.5  # small padding
            elif visual:
                duration = visual.duration
            else:
                duration = 2.0

            timeline.entries.append(TimelineEntry(
                block_index=i,
                visual_path=visual.video_path if visual else None,
                audio_path=audio.audio_path if audio else None,
                duration=duration,
                start_time=current_time,
            ))
            current_time += duration

        return timeline
