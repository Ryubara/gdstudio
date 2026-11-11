"""The learning loop: what the maintainer corrects is written into the docs in the same session
(docs/studio/hooks.md#learning)."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from .disk import disk_note, start_disk_guard
from .workspace import KIT, workspace_of


def lesson_text(kind: str, config: dict[str, Any], workspace: Path | None) -> str:
    """One of the learning-loop texts of hooks.toml (`prompt`, `session`, `subagent`) with its paths filled in."""
    rules = config.get("lessons", {})
    text = rules.get(kind, "")
    if not text:
        return ""
    queue = Path(rules.get("queue", "scratch/kit-lessons-queue"))
    kit = workspace / "repos" / "gdstudio" if workspace and (workspace / "repos" / "gdstudio").is_dir() else KIT
    return text.format(
        corrections=(kit / "docs" / "studio" / "maintainer-corrections.md").as_posix(),
        lessons=(kit / "docs" / "lessons" / "index.md").as_posix(),
        rules=(kit / "docs" / "studio" / "rules.md").as_posix(),
        queue=((workspace / queue) if workspace else queue).as_posix(),
    )


def user_prompt_submit(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """The short reminder added to every message in a GDStudio workspace: a correction becomes a row in this session."""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    return lesson_text("prompt", config, workspace) if workspace else ""


def subagent_start(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """What a starting agent is told: read the sections its prompt's `Read:` lines name (the Agent guard made sure
    there are some, and that they exist), and how a mistake updates a section. Read-only helpers (and the forks that
    carry the parent's context) are left alone."""
    if payload.get("agent_type") in config.get("agents", {}).get("helpers", []):
        return ""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if not workspace:
        return ""
    start_disk_guard(workspace, config)
    return "\n\n".join(t for t in (lesson_text("subagent", config, workspace), disk_note(workspace, config)) if t)


def pending_lessons(workspace: Path, config: dict[str, Any]) -> list[Path]:
    """Queued lesson rows that are neither published (moved to `published/`) nor waiting on a cause (`Waiting on:`)."""
    rules = config.get("lessons", {})
    folder = workspace / rules.get("queue", "scratch/kit-lessons-queue")
    if not folder.is_dir():
        return []
    waiting = re.compile(rules.get("waiting", r"(?im)^\s*waiting on:\s*\S"))
    return [
        path
        for path in sorted(folder.glob("*.md"))
        if path.name.lower() != "readme.md" and not waiting.search(path.read_text(encoding="utf-8", errors="replace"))
    ]


def stop_queue(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """The learning gate: queued corrections whose cause is known are published first (a rule and a log line)."""
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    pending = pending_lessons(workspace, config) if workspace else []
    if not pending:
        return None
    names = ", ".join(p.name for p in pending[:6]) + ("..." if len(pending) > 6 else "")
    return (
        f"Corrections are queued in {pending[0].parent.as_posix()} and not published: {names}. Publish each as an "
        f"entry in the topic section it belongs to (docs/studio/rules.md) and a line on the corrections log, in a kit "
        f"pull request, then move its file to published/; or, if its cause is not known yet, add a `Waiting on: #N` "
        f"line naming the issue. Ones that are not yours: say so and finish."
    )
