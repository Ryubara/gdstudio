"""Local mains: every main checkout in <workspace>/repos/ follows origin after a merge (docs/studio/hooks.md#mains)."""

from __future__ import annotations

import re
import subprocess
import time
from pathlib import Path
from typing import Any

from .shell import program
from .workspace import git

_MERGE_API = re.compile(r"/pulls/\d+/merge\b")


def is_merge(words: list[str]) -> bool:
    """`gh pr merge ...` or `gh api ... repos/<o>/<r>/pulls/<n>/merge`: a command that merges a pull request."""
    if program(words) != "gh" or len(words) < 2:
        return False
    if words[1:3] == ["pr", "merge"]:
        return True
    return words[1] == "api" and any(_MERGE_API.search(w) for w in words[2:])


def pull_mains(workspace: Path, config: dict[str, Any], force: bool = False) -> list[str]:
    """Fast-forward each repository under `<workspace>/repos/` that has `main` checked out, at most once every
    `[mains] every_seconds` unless `force`. Never discards anything: a checkout with local changes in the way, or one
    on another branch, is left as it is and named. Returns one line per repository that moved or could not."""
    rules = config.get("mains", {})
    if not rules.get("pull", True):
        return []
    stamp = workspace / rules.get("stamp", "cache/mains-pulled")
    now = time.time()
    if not force and stamp.exists() and now - stamp.stat().st_mtime < float(rules.get("every_seconds", 120)):
        return []
    try:
        stamp.parent.mkdir(parents=True, exist_ok=True)
        stamp.touch()
    except OSError:
        pass
    notes: list[str] = []
    repos = workspace / "repos"
    mains = config.get("git", {}).get("protected_branches", ["main"])
    for repo in sorted(p for p in repos.iterdir() if (p / ".git").is_dir()) if repos.is_dir() else []:
        if git(repo, "rev-parse", "--abbrev-ref", "HEAD") not in mains:
            continue
        before = git(repo, "rev-parse", "HEAD")
        try:
            result = subprocess.run(
                ["git", "-C", str(repo), "pull", "--ff-only", "--quiet"], capture_output=True, text=True, timeout=30
            )
        except (OSError, subprocess.SubprocessError) as error:
            notes.append(f"{repo.name}: main not pulled ({type(error).__name__})")
            continue
        if result.returncode != 0:
            why = (result.stderr.strip().splitlines() or ["git pull --ff-only failed"])[0]
            notes.append(f"{repo.name}: main not pulled, {why} (local changes are left alone: ask before discarding)")
        elif git(repo, "rev-parse", "HEAD") != before:
            notes.append(f"{repo.name}: main pulled to {git(repo, 'log', '-1', '--format=%h %s')}")
    return notes
