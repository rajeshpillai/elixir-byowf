"""Sidecar override loader — applies per-block narration and effects from YAML."""

from pathlib import Path

from .parser.ir import TutorialIR


def sidecar_path_for(tutorial_path: Path) -> Path:
    """Return the sidecar YAML path for a tutorial markdown file.

    Example: ../tutorial/01-tcp-socket.md → overrides/01-tcp-socket.yaml
    """
    return Path("overrides") / f"{Path(tutorial_path).stem}.yaml"


def apply_overrides(tutorial: TutorialIR, sidecar: Path | None = None) -> TutorialIR:
    """Apply sidecar overrides to a parsed tutorial's blocks.

    The sidecar YAML has this structure:

        blocks:
          0:                          # block index
            narration: "Custom text"  # override auto-derived narration
            effect: "line_highlight"  # visual effect name
            highlight_lines: [3, 5]   # effect-specific params
            pause_after: 1.5          # extra pause after block
          4:
            narration: "Another override"

    Any key other than 'narration' is stored in block.effects.
    """
    if sidecar is None:
        sidecar = sidecar_path_for(tutorial.source_path)
    else:
        sidecar = Path(sidecar)

    if not sidecar.exists():
        return tutorial

    import yaml

    with open(sidecar) as f:
        data = yaml.safe_load(f) or {}

    block_overrides = data.get("blocks", {})
    for idx, overrides in block_overrides.items():
        idx = int(idx)
        if idx < 0 or idx >= len(tutorial.blocks):
            continue

        block = tutorial.blocks[idx]

        # Override narration if provided
        if "narration" in overrides:
            block.narration = overrides["narration"]

        # Override duration hint if provided
        if "duration" in overrides:
            block.duration_hint = float(overrides["duration"])

        # Everything else goes into effects
        reserved = {"narration", "duration"}
        effects = {k: v for k, v in overrides.items() if k not in reserved}
        if effects:
            block.effects.update(effects)

    return tutorial
