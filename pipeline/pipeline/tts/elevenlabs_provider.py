"""ElevenLabs TTS provider (stub — install elevenlabs package to use)."""

from pathlib import Path

from .base import TTSConfig, TTSProvider, TTSResult


class ElevenLabsTTSProvider(TTSProvider):
    def __init__(self, config: TTSConfig | None = None, api_key: str | None = None):
        super().__init__(config)
        self.api_key = api_key

    @property
    def name(self) -> str:
        return "elevenlabs"

    def is_available(self) -> bool:
        try:
            import elevenlabs  # noqa: F401
            return self.api_key is not None
        except ImportError:
            return False

    def synthesize(self, text: str, output_path: Path) -> TTSResult:
        raise NotImplementedError(
            "ElevenLabs provider not yet implemented. "
            "Use 'kokoro' or 'openai' for now."
        )
