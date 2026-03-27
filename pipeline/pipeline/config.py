"""Pipeline configuration."""

from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class PipelineConfig:
    tts_provider: str = "auto"
    tts_voice: str = "default"
    tts_speed: float = 1.0
    tts_api_key: str | None = None
    resolution: tuple[int, int] = (1920, 1080)
    fps: int = 30
    output_dir: Path = Path("output")
    manim_quality: str = "medium_quality"
    font_family: str = "DejaVu Sans Mono"

    @classmethod
    def load(cls, override_path: Path | None = None) -> "PipelineConfig":
        """Load config, optionally merging a per-tutorial YAML override."""
        config = cls()
        if override_path and override_path.exists():
            import yaml
            with open(override_path) as f:
                overrides = yaml.safe_load(f) or {}
            for key, value in overrides.items():
                if hasattr(config, key):
                    setattr(config, key, value)
        return config

    def override_path_for_tutorial(self, tutorial_id: str) -> Path:
        """Return the override YAML path for a tutorial ID like '01'."""
        return Path("overrides") / f"{tutorial_id}.yaml"
