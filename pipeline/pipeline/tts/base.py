"""Abstract base for TTS providers."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path


@dataclass
class TTSConfig:
    voice: str = "default"
    speed: float = 1.0
    sample_rate: int = 24000
    output_format: str = "wav"


@dataclass
class TTSResult:
    audio_path: Path
    duration_seconds: float


class TTSProvider(ABC):
    """Abstract interface for text-to-speech providers."""

    def __init__(self, config: TTSConfig | None = None):
        self.config = config or TTSConfig()

    @abstractmethod
    def synthesize(self, text: str, output_path: Path) -> TTSResult:
        """Convert text to speech, write to output_path. Returns result with duration."""
        ...

    @abstractmethod
    def is_available(self) -> bool:
        """Check if this provider is installed and ready to use."""
        ...

    @property
    @abstractmethod
    def name(self) -> str:
        ...
