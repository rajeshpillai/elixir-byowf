"""OpenAI TTS provider (stub — install openai package to use)."""

from pathlib import Path

from .base import TTSConfig, TTSProvider, TTSResult


class OpenAITTSProvider(TTSProvider):
    def __init__(self, config: TTSConfig | None = None, api_key: str | None = None):
        super().__init__(config)
        self.api_key = api_key

    @property
    def name(self) -> str:
        return "openai"

    def is_available(self) -> bool:
        try:
            import openai  # noqa: F401
            return self.api_key is not None
        except ImportError:
            return False

    def synthesize(self, text: str, output_path: Path) -> TTSResult:
        from openai import OpenAI
        import struct
        import wave

        client = OpenAI(api_key=self.api_key)
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        voice = self.config.voice if self.config.voice != "default" else "nova"

        response = client.audio.speech.create(
            model="tts-1",
            voice=voice,
            input=text,
            response_format="wav",
            speed=self.config.speed,
        )

        response.stream_to_file(str(output_path))

        # Read duration from wav file
        with wave.open(str(output_path), "rb") as wf:
            frames = wf.getnframes()
            rate = wf.getframerate()
            duration = frames / rate

        return TTSResult(audio_path=output_path, duration_seconds=duration)
