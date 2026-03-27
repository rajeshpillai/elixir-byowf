from .base import TTSProvider, TTSConfig, TTSResult


def get_provider(name: str = "auto", **kwargs) -> TTSProvider:
    """Factory to get a TTS provider by name.

    Args:
        name: "kokoro", "openai", "elevenlabs", or "auto" (tries local first).
        **kwargs: Passed to the provider constructor (e.g. api_key, voice).
    """
    config = TTSConfig(**{k: v for k, v in kwargs.items() if k in TTSConfig.__dataclass_fields__})

    if name == "auto":
        for try_name in ("kokoro", "openai", "elevenlabs"):
            try:
                provider = get_provider(try_name, **kwargs)
                if provider.is_available():
                    return provider
            except ImportError:
                continue
        raise RuntimeError("No TTS provider available. Install kokoro: pip install kokoro")

    if name == "kokoro":
        from .kokoro_provider import KokoroTTSProvider
        return KokoroTTSProvider(config)
    elif name == "openai":
        from .openai_provider import OpenAITTSProvider
        return OpenAITTSProvider(config, api_key=kwargs.get("api_key"))
    elif name == "elevenlabs":
        from .elevenlabs_provider import ElevenLabsTTSProvider
        return ElevenLabsTTSProvider(config, api_key=kwargs.get("api_key"))
    else:
        raise ValueError(f"Unknown TTS provider: {name}")
