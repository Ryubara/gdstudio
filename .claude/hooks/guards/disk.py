"""The disk guard (docs/studio/hooks.md#disk): a background `gds disk guard`, and no new agent or worktree under the
hard limit."""

from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

from .workspace import start_background, workspace_of

GB = 1024**3


def free_bytes(path: Path) -> int | None:
    """Free bytes of the disk holding `path`; None when it cannot be read (a guard that cannot look lets it pass)."""
    try:
        return shutil.disk_usage(path).free
    except OSError:
        return None


def disk_status(workspace: Path, config: dict[str, Any]) -> dict[str, Any]:
    """The last `gds disk guard` run's status file; empty when there is none."""
    path = workspace / config.get("disk", {}).get("status", "cache/disk-guard.json")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def disk_level(workspace: Path, config: dict[str, Any]) -> tuple[str, float | None]:
    """(`hard` | `soft` | `ok`, free GB) of the workspace's disk; `ok` when the guard is off or the disk unreadable."""
    rules = config.get("disk", {})
    free = free_bytes(workspace)
    if not rules.get("enabled", True) or free is None:
        return "ok", None if free is None else free / GB
    gb = free / GB
    if gb < float(rules.get("hard_gb", 10)):
        return "hard", gb
    if gb < float(rules.get("soft_gb", 40)):
        return "soft", gb
    return "ok", gb


def disk_refusal(cwd: Path, config: dict[str, Any], what: str) -> str | None:
    """Why `what` may not start: the workspace's disk is under `[disk] hard_gb`. None outside a workspace or above."""
    workspace = workspace_of(cwd)
    if workspace is None:
        return None
    state, gb = disk_level(workspace, config)
    if state != "hard" or gb is None:
        return None
    hard = config.get("disk", {}).get("hard_gb", 10)
    biggest = disk_status(workspace, config).get("biggest", [])[:5]
    names = "; ".join(f"{b.get('path')} {b.get('gb')} GB" for b in biggest if isinstance(b, dict))
    return (
        f"{what} is refused: the disk has {gb:.1f} GB free, under the hard limit of {hard} GB "
        f"(docs/studio/hooks.md#disk). "
        f"Nothing new starts until space is back. `gds disk guard` frees what the rules allow (finished worktrees, "
        f"idle import caches, scratch downloads past their pull request); report what is left to the coordinator and "
        f"the maintainer." + (f" The biggest folders: {names}." if names else "")
    )


def check_disk_agent(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """A task agent does not start under the hard limit; helpers (read-only) and `[disk] exempt` agents do."""
    kind = (payload.get("tool_input") or {}).get("subagent_type") or "general-purpose"
    exempt = [*config.get("agents", {}).get("helpers", []), *config.get("disk", {}).get("exempt", [])]
    if kind in exempt:
        return []
    refused = disk_refusal(Path(payload.get("cwd") or "."), config, f"starting a {kind} agent")
    return [refused] if refused else []


def disk_note(workspace: Path, config: dict[str, Any]) -> str:
    """The line an agent or a session is told when the disk is under the soft limit."""
    state, gb = disk_level(workspace, config)
    if state == "ok" or gb is None:
        return ""
    line = disk_status(workspace, config).get("line", "")
    return (
        f"Disk {state.upper()}: {gb:.1f} GB free{f' ({line})' if line else ''}. Keep what you write small: reduce "
        f"downloaded CI artifacts to their numbers and delete them in the same task, delete raw captures once a clip "
        f"or sheet is made, and name what can go in your scratch topic's SCRATCH.md (docs/studio/workspace.md#disk)."
    )


def start_disk_guard(workspace: Path, config: dict[str, Any], force: bool = False) -> bool:
    """Start `gds disk guard` in the background at most once every `[disk] every_seconds` (unless `force`); its report
    is appended to `[disk] log`. The guard takes its own lock. Returns whether it was started."""
    rules = config.get("disk", {})
    if not rules.get("enabled", True):
        return False
    return start_background(
        workspace, rules, ["disk", "guard"], "cache/disk-guard-started", "scratch/disk-guard.log", 300, force
    )
