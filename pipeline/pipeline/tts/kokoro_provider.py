"""Kokoro local TTS provider."""

from pathlib import Path

from .base import TTSConfig, TTSProvider, TTSResult


class KokoroTTSProvider(TTSProvider):
    """Local TTS using the Kokoro library."""

    def __init__(self, config: TTSConfig | None = None):
        super().__init__(config)
        self._pipeline = None

    @property
    def name(self) -> str:
        return "kokoro"

    def is_available(self) -> bool:
        try:
            import kokoro  # noqa: F401
            return True
        except ImportError:
            return False

    def _get_pipeline(self):
        if self._pipeline is None:
            from kokoro import KPipeline
            lang = "a"  # American English
            self._pipeline = KPipeline(lang_code=lang)
        return self._pipeline

    def synthesize(self, text: str, output_path: Path) -> TTSResult:
        import soundfile as sf

        pipeline = self._get_pipeline()
        output_path = Path(output_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)

        voice = self.config.voice if self.config.voice != "default" else "af_heart"

        # Kokoro generates audio in chunks — collect all samples
        all_samples = []
        sample_rate = self.config.sample_rate

        for result in pipeline(text, voice=voice, speed=self.config.speed):
            if result.audio is not None:
                all_samples.append(result.audio)
                sample_rate = sample_rate  # kokoro uses 24000 by default

        if not all_samples:
            # Generate a short silence if no audio produced
            import numpy as np
            all_samples = [np.zeros(int(sample_rate * 0.5), dtype="float32")]

        import numpy as np
        audio = np.concatenate(all_samples)
        duration = len(audio) / sample_rate

        sf.write(str(output_path), audio, sample_rate)

        return TTSResult(audio_path=output_path, duration_seconds=duration)
