"""The proof gate at Stop: a session that changed visual files of a game ends only once a newer capture exists."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .workspace import git, matches, workspace_of


def changed_files(repo: Path, protected: list[str]) -> list[str]:
    """Files changed on this branch (against the default branch) and in the working tree."""
    files = set()
    for line in git(repo, "status", "--porcelain", "--untracked-files=all").splitlines():
        files.add(line[3:].split(" -> ")[-1].strip('"'))
    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    if branch and branch not in protected:
        base = git(repo, "merge-base", "HEAD", "origin/main") or git(repo, "merge-base", "HEAD", "main")
        if base:
            files.update(git(repo, "diff", "--name-only", f"{base}..HEAD").splitlines())
    return sorted(f for f in files if f)


def scratch_folder(repo: Path) -> Path | None:
    """<workspace>/scratch/<repo>/<branch>/, where a branch's captures and reports go."""
    workspace = workspace_of(repo)
    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD") or "detached"
    name = repo.name if repo.parent.name == "repos" else repo.parent.name  # a worktree: worktrees/<repo>/<branch>
    return workspace / "scratch" / name / branch.replace("/", "-") if workspace else None


def stop_proof(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """The proof gate: a session that changed visual files of a game ends only once a newer capture exists."""
    cwd = Path(payload.get("cwd") or ".")
    repo = Path(git(cwd, "rev-parse", "--show-toplevel") or cwd)
    if not (repo / "game" / "project.godot").exists():
        return None
    rules = config.get("proof", {})
    visual = [
        f
        for f in changed_files(repo, config.get("git", {}).get("protected_branches", ["main"]))
        if matches(f, rules.get("visual", [])) and (repo / f).exists()
    ]
    if not visual:
        return None
    newest = max((repo / f).stat().st_mtime for f in visual)
    folder = scratch_folder(repo)
    if folder is None:
        return None
    shots = (
        [p for p in folder.rglob("*") if p.is_file() and matches(p.name, rules.get("captures", []))]
        if folder.exists()
        else []
    )
    if any(p.stat().st_mtime >= newest for p in shots):
        return None
    return (
        f"Visual files changed ({', '.join(visual[:4])}{'...' if len(visual) > 4 else ''}) with no capture "
        f"newer than them in {folder}. Capture the result (Godot's Movie Maker: `--write-movie "
        f"{folder.as_posix()}/<name>.png --fixed-fps 10 --quit-after 5`), look at it, then finish; attach it to "
        f"the pull request with `gh pr create|edit --attach`."
    )
