"""Finished worktrees: swept in the background (docs/studio/hooks.md#sweep)."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .workspace import start_background


def start_sweep(workspace: Path, config: dict[str, Any], force: bool = False) -> bool:
    """Start `gds worktree sweep` in the background (it never blocks the hook), at most once every `[sweep]
    every_seconds` unless `force`; its report is appended to `[sweep] log`. The sweep takes its own lock, so two
    sessions starting at once run one. Returns whether a sweep was started."""
    rules = config.get("sweep", {})
    if not rules.get("enabled", True):
        return False
    return start_background(
        workspace,
        rules,
        ["worktree", "sweep", *rules.get("args", [])],
        "cache/worktree-sweep-started",
        "scratch/worktree-sweep.log",
        600,
        force,
    )
