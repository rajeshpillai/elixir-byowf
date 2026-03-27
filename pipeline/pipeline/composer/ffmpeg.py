"""FFmpeg composer — concatenates visual + audio segments into final MP4."""

import subprocess
import tempfile
from pathlib import Path

from .timeline import Timeline


def _run_ffmpeg(args: list[str], check: bool = True):
    """Run an ffmpeg command."""
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "warning"] + args
    return subprocess.run(cmd, check=check, capture_output=True, text=True)


def _make_silence(duration: float, output_path: Path, sample_rate: int = 24000):
    """Generate a silent WAV file of given duration."""
    _run_ffmpeg([
        "-f", "lavfi",
        "-i", f"anullsrc=r={sample_rate}:cl=mono",
        "-t", str(duration),
        str(output_path),
    ])


def _make_black_video(duration: float, output_path: Path, width: int = 1920,
                       height: int = 1080, fps: int = 30):
    """Generate a black video of given duration."""
    _run_ffmpeg([
        "-f", "lavfi",
        "-i", f"color=c=black:s={width}x{height}:r={fps}:d={duration}",
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        str(output_path),
    ])


def compose(
    timeline: Timeline,
    output_path: Path,
    resolution: tuple[int, int] = (1920, 1080),
    fps: int = 30,
) -> Path:
    """Compose timeline entries into a final MP4.

    Strategy: for each entry, prepare a video clip + audio clip of matching duration,
    then concatenate all clips using ffmpeg concat demuxer.
    """
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    width, height = resolution

    with tempfile.TemporaryDirectory(prefix="kata_compose_") as tmpdir:
        tmpdir = Path(tmpdir)
        segment_paths = []

        for idx, entry in enumerate(timeline.entries):
            seg_video = tmpdir / f"seg_{idx:04d}.mp4"

            # Prepare video
            if entry.visual_path and entry.visual_path.exists():
                # Scale/pad visual to target resolution and set duration
                _run_ffmpeg([
                    "-i", str(entry.visual_path),
                    "-vf", f"scale={width}:{height}:force_original_aspect_ratio=decrease,"
                           f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=black",
                    "-c:v", "libx264",
                    "-pix_fmt", "yuv420p",
                    "-r", str(fps),
                    "-t", str(entry.duration),
                    str(seg_video),
                ])
            else:
                _make_black_video(entry.duration, seg_video, width, height, fps)

            # Prepare audio
            seg_audio = tmpdir / f"seg_{idx:04d}.wav"
            if entry.audio_path and entry.audio_path.exists():
                # Pad or trim audio to match duration
                _run_ffmpeg([
                    "-i", str(entry.audio_path),
                    "-af", f"apad=whole_dur={entry.duration}",
                    "-t", str(entry.duration),
                    "-ar", "24000",
                    "-ac", "1",
                    str(seg_audio),
                ])
            else:
                _make_silence(entry.duration, seg_audio)

            # Mux video + audio into segment
            seg_muxed = tmpdir / f"muxed_{idx:04d}.mp4"
            _run_ffmpeg([
                "-i", str(seg_video),
                "-i", str(seg_audio),
                "-c:v", "copy",
                "-c:a", "aac",
                "-b:a", "128k",
                "-shortest",
                str(seg_muxed),
            ])
            segment_paths.append(seg_muxed)

        # Build concat file list
        concat_file = tmpdir / "concat.txt"
        with open(concat_file, "w") as f:
            for p in segment_paths:
                f.write(f"file '{p}'\n")

        # Final concatenation
        _run_ffmpeg([
            "-f", "concat",
            "-safe", "0",
            "-i", str(concat_file),
            "-c:v", "libx264",
            "-c:a", "aac",
            "-b:a", "128k",
            "-movflags", "+faststart",
            str(output_path),
        ])

    return output_path
