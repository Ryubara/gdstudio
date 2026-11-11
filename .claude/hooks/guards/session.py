"""SessionStart: where this session is and the rules it works under."""

from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any

from .disk import disk_note, start_disk_guard
from .learning import lesson_text
from .mains import pull_mains
from .proof import scratch_folder
from .sweep import start_sweep
from .workspace import git, workspace_of


def session_start(payload: dict[str, Any], config: dict[str, Any]) -> str:
    cwd = Path(payload.get("cwd") or ".")
    workspace = workspace_of(cwd)
    if workspace is None:
        return ""
    repo = Path(git(cwd, "rev-parse", "--show-toplevel") or cwd)
    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    lines = [f"GDStudio workspace {workspace.as_posix()}; repository {repo.name}, branch {branch or '?'}."]
    local = workspace / "gdstudio.local.toml"
    if local.exists():
        tools = tomllib.loads(local.read_text(encoding="utf-8")).get("tools", {})
        lines += [f"Pinned {name}: {path}" for name, path in tools.items()]
    folder = scratch_folder(repo)
    if folder:
        lines.append(f"Captures and reports for this branch go in {folder.as_posix()}/ (never in a repository).")
    lines.append("Work on a branch, open a pull request; visual work attaches captures (`gh ... --attach`).")
    lines += pull_mains(workspace, config, force=True)
    start_sweep(workspace, config)
    start_disk_guard(workspace, config)
    lines.append(disk_note(workspace, config))
    lines.append(lesson_text("session", config, workspace))
    return "\n".join(line for line in lines if line)
