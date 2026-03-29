"""CLI entry point for the tutorial-to-video pipeline."""

from pathlib import Path

import click

from .config import PipelineConfig
from .parser.ir import TutorialIR
from .parser.markdown import parse_tutorial


def _find_tutorials(path: str) -> list[Path]:
    """Find all .md files under a path (file or directory)."""
    p = Path(path)
    if p.is_file() and p.suffix == ".md":
        return [p]
    elif p.is_dir():
        return sorted(p.rglob("*.md"))
    else:
        raise click.BadParameter(f"Not a file or directory: {path}")


@click.group()
def main():
    """Ignite tutorial-to-video pipeline."""
    pass


@main.command()
@click.argument("path")
def parse(path: str):
    """Parse a tutorial markdown file and print the IR blocks."""
    for tut_path in _find_tutorials(path):
        tut = parse_tutorial(tut_path)
        click.echo(f"\n{'='*60}")
        click.echo(f"Tutorial: {tut.title} [{tut.tutorial_id}]")
        click.echo(f"Source: {tut.source_path}")
        click.echo(f"Blocks: {len(tut.blocks)}")
        click.echo(f"{'='*60}")
        for i, block in enumerate(tut.blocks):
            narr = (block.narration[:60] + "...") if block.narration and len(block.narration) > 60 else block.narration
            lang = f" [{block.language}]" if block.language else ""
            click.echo(f"  [{i:3d}] {block.type.name:<16}{lang}  narration: {narr}")


@main.command()
@click.argument("path")
@click.option("--provider", "-p", default="auto", help="TTS provider name")
@click.option("--voice", "-v", default="default", help="Voice name")
@click.option("--output-dir", "-o", default="output", help="Output directory")
def tts(path: str, provider: str, voice: str, output_dir: str):
    """Generate TTS audio for a tutorial (no video)."""
    from .tts import get_provider

    tts_provider = get_provider(provider, voice=voice)
    click.echo(f"Using TTS provider: {tts_provider.name}")

    for tut_path in _find_tutorials(path):
        tut = parse_tutorial(tut_path)
        out_dir = Path(output_dir) / tut.tutorial_id / "audio"
        out_dir.mkdir(parents=True, exist_ok=True)

        click.echo(f"\nGenerating audio for: {tut.title}")
        for i, block in enumerate(tut.blocks):
            if not block.narration:
                continue
            out_file = out_dir / f"{i:03d}-{block.type.name.lower()}.wav"
            click.echo(f"  [{i:3d}] {block.type.name:<16} → {out_file.name}")
            result = tts_provider.synthesize(block.narration, out_file)
            click.echo(f"         duration: {result.duration_seconds:.1f}s")


@main.command()
@click.argument("path")
@click.option("--provider", "-p", default="auto", help="TTS provider name")
@click.option("--voice", "-v", default="default", help="Voice name")
@click.option("--quality", "-q", default="medium_quality", help="Manim quality")
@click.option("--output-dir", "-o", default="output", help="Output directory")
def generate(path: str, provider: str, voice: str, quality: str, output_dir: str):
    """Generate full video tutorial for a tutorial step."""
    from .composer.ffmpeg import compose
    from .composer.timeline import Timeline
    from .tts import get_provider
    from .visuals.scene_builder import build_all_scenes

    config = PipelineConfig(
        tts_provider=provider,
        tts_voice=voice,
        manim_quality=quality,
        output_dir=Path(output_dir),
    )

    tts_provider = get_provider(config.tts_provider, voice=config.tts_voice)
    click.echo(f"Using TTS provider: {tts_provider.name}")

    for tut_path in _find_tutorials(path):
        tut = parse_tutorial(tut_path)
        tut_out = Path(output_dir) / tut.tutorial_id
        segments_dir = tut_out / "segments"
        segments_dir.mkdir(parents=True, exist_ok=True)

        click.echo(f"\n{'='*60}")
        click.echo(f"Generating: {tut.title}")
        click.echo(f"{'='*60}")

        # Step 1: Generate TTS audio
        click.echo("\n[1/3] Generating audio narration...")
        audio_results = {}
        for i, block in enumerate(tut.blocks):
            if not block.narration:
                continue
            out_file = segments_dir / f"{i:03d}-{block.type.name.lower()}.wav"
            click.echo(f"  [{i:3d}] {block.type.name:<16}")
            result = tts_provider.synthesize(block.narration, out_file)
            audio_results[i] = result

        # Step 2: Render visual scenes (with audio-driven durations)
        click.echo("\n[2/3] Rendering visual scenes...")
        durations = {i: r.duration_seconds + 0.5 for i, r in audio_results.items()}
        visual_segments = build_all_scenes(
            tut, segments_dir, durations=durations, quality=config.manim_quality
        )
        click.echo(f"  Rendered {len(visual_segments)} scenes")

        # Step 3: Compose final video
        click.echo("\n[3/3] Composing final video...")
        timeline = Timeline.from_segments(tut, audio_results, visual_segments)
        final_path = tut_out / f"{tut.tutorial_id}.mp4"
        compose(timeline, final_path, resolution=config.resolution, fps=config.fps)

        click.echo(f"\nDone! Video saved to: {final_path}")
        click.echo(f"Duration: {timeline.total_duration:.1f}s")


@main.command("generate-all")
@click.option("--tutorials-dir", default="tutorial", help="Root tutorials directory")
@click.option("--provider", "-p", default="auto", help="TTS provider name")
@click.option("--output-dir", "-o", default="output", help="Output directory")
def generate_all(tutorials_dir: str, provider: str, output_dir: str):
    """Generate video tutorials for all tutorial steps."""
    import subprocess
    import sys

    tutorials = _find_tutorials(tutorials_dir)
    click.echo(f"Found {len(tutorials)} tutorials")
    for tut_path in tutorials:
        click.echo(f"\n--- {tut_path} ---")
        subprocess.run([
            sys.executable, "-m", "pipeline", "generate",
            str(tut_path),
            "-p", provider,
            "-o", output_dir,
        ])


@main.command()
@click.option("--tutorials-dir", default="tutorial", help="Root tutorials directory")
@click.option("--output-dir", "-o", default="output", help="Output directory")
def status(tutorials_dir: str, output_dir: str):
    """Show generation status for all tutorials."""
    tutorials = _find_tutorials(tutorials_dir)
    generated = 0
    for tut_path in tutorials:
        tut = parse_tutorial(tut_path)
        video = Path(output_dir) / tut.tutorial_id / f"{tut.tutorial_id}.mp4"
        mark = "done" if video.exists() else "    "
        click.echo(f"  [{mark}] {tut.tutorial_id}: {tut.title}")
        if video.exists():
            generated += 1
    click.echo(f"\n{generated}/{len(tutorials)} generated")
