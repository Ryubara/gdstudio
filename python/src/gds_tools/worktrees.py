"""The branch and worktree of a started issue, made before the agent gets the work (docs/starting-work.md#worktree).

Agents used to make their own branches and merge commits, and a mistake in one (a merge message that `pr-rules`
refuses) was only found after the push, where fixing it takes a force push. `gds issue start` now creates the branch
from a fresh `origin/<default>` in `<workspace>/worktrees/<repo>/<branch>` and checks that the git hooks of the
repository (pre-commit, commit-msg, pre-push) are installed, so the checks run on this machine before anything is
pushed. Every path here is absolute: `git -C <relative path>` resolves inside the repository it is run from.
"""

from __future__ import annotations

import contextlib
import re
import shutil
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

#: The git hooks `pre-commit install` must have written: file checks, message checks, and the check before a push.
HOOK_TYPES = ("pre-commit", "commit-msg", "pre-push")
CONFIG = ".pre-commit-config.yaml"
_MARKER = "pre-commit"  # every hook script that pre-commit writes names itself

Run = Callable[[list[str], Path], str]


class WorktreeError(Exception):
    """The worktree cannot be made, or its hooks cannot be installed."""


def run(cmd: list[str], cwd: Path) -> str:
    """Run a command and return its output; a failure raises WorktreeError with git's own words."""
    try:
        done = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    except OSError as error:
        raise WorktreeError(f"cannot run {cmd[0]}: {error}") from error
    if done.returncode != 0:
        raise WorktreeError(f"`{' '.join(cmd)}` failed: {(done.stderr or done.stdout).strip()}")
    return done.stdout


def branch_name(title: str, number: int, taken: set[str] | None = None, limit: int = 48) -> str:
    """A branch name from an issue title: `tools: Add worktree setup` becomes `tools-add-worktree-setup`, cut at a word
    boundary. A name that is taken gets the issue number, and a title with no letters is `issue-<number>`."""
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    if len(slug) > limit:
        slug = slug[:limit].rsplit("-", 1)[0] if "-" in slug[:limit] else slug[:limit]
    slug = slug.strip("-") or f"issue-{number}"
    return f"{slug}-{number}" if slug in (taken or set()) else slug


@dataclass(frozen=True)
class Worktree:
    """A worktree made for an issue."""

    path: Path
    branch: str
    base: str  # the commit of origin/<default> it starts from
    hooks: list[str]  # what was found or done about the git hooks, one line each


def default_branch(checkout: Path, git: Run = run) -> str:
    """The default branch of the remote: `origin/HEAD`, else `main`."""
    try:
        ref = git(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], checkout).strip()
    except WorktreeError:
        return "main"
    return ref.removeprefix("origin/") or "main"


def hooks_dir(worktree: Path, git: Run = run) -> Path:
    """The hooks folder git uses for this worktree (the common one of the repository, shared by all its worktrees)."""
    out = git(["git", "rev-parse", "--path-format=absolute", "--git-path", "hooks"], worktree).strip()
    return Path(out)


def missing_hooks(worktree: Path, git: Run = run) -> list[str]:
    """The hook types the repository's pre-commit config needs that are not installed (empty without a config)."""
    if not (worktree / CONFIG).is_file():
        return []
    folder = hooks_dir(worktree, git)
    missing = []
    for kind in HOOK_TYPES:
        script = folder / kind
        if not script.is_file() or _MARKER not in script.read_text(encoding="utf-8", errors="replace"):
            missing.append(kind)
    return missing


def install_hooks(worktree: Path, git: Run = run) -> None:
    """Install the three hook types with pre-commit (`pre-commit` when it is on the PATH, else `uvx pre-commit`)."""
    program = shutil.which("pre-commit")
    base = [program] if program else [shutil.which("uvx") or "uvx", "pre-commit"]
    args = [arg for kind in HOOK_TYPES for arg in ("-t", kind)]
    git([*base, "install", *args], worktree)


def ensure_hooks(worktree: Path, *, git: Run = run, install: Callable[[Path], None] | None = None) -> list[str]:
    """Check the hooks are installed for the repository of `worktree`, installing what is missing, and check again.
    Returns the lines to print; raises WorktreeError when a hook is still missing."""
    if not (worktree / CONFIG).is_file():
        return [f"hooks: no {CONFIG} in this repository, nothing to install"]
    lines = []
    missing = missing_hooks(worktree, git)
    if missing:
        lines.append(f"hooks: {', '.join(missing)} were not installed; installing them with pre-commit")
        try:
            (install or (lambda path: install_hooks(path, git)))(worktree)
        except WorktreeError as error:
            raise WorktreeError(f"the git hooks cannot be installed: {error}") from error
        missing = missing_hooks(worktree, git)
    if missing:
        raise WorktreeError(f"the git hooks {', '.join(missing)} are still not installed in {hooks_dir(worktree, git)}")
    return [*lines, f"hooks: {', '.join(HOOK_TYPES)} installed ({hooks_dir(worktree, git)})"]


def create(
    checkout: Path,
    worktrees: Path,
    title: str,
    number: int,
    *,
    branch: str = "",
    git: Run = run,
    install: Callable[[Path], None] | None = None,
) -> Worktree:
    """Make the branch and its worktree for an issue: `<worktrees>/<branch>` (an absolute path) from a freshly fetched
    `origin/<default>`, without tracking it (a push goes to a branch of the same name), then verify the hooks.
    Nothing is left behind when a step fails."""
    checkout, worktrees = checkout.resolve(), worktrees.resolve()
    if not (checkout / ".git").exists():
        raise WorktreeError(f"{checkout} is not a git checkout (clone it first: gds workspace init)")
    default = default_branch(checkout, git)
    git(["git", "fetch", "--quiet", "origin", default], checkout)
    heads = git(["git", "for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes/origin"], checkout)
    taken = {ref.removeprefix("origin/") for ref in heads.split()}
    name = branch or branch_name(title, number, taken)
    if branch and name in taken:
        raise WorktreeError(f"the branch {name} already exists; choose another with --branch")
    path = worktrees / name
    if path.exists():
        raise WorktreeError(f"{path} already exists; remove it or choose another branch with --branch")
    base = git(["git", "rev-parse", f"origin/{default}"], checkout).strip()
    git(["git", "worktree", "add", "--no-track", "-b", name, str(path), f"origin/{default}"], checkout)
    try:
        hooks = ensure_hooks(path, git=git, install=install)
    except WorktreeError:
        remove(checkout, path, name, git)
        raise
    return Worktree(path=path, branch=name, base=base, hooks=hooks)


def remove(checkout: Path, path: Path, branch: str, git: Run = run) -> None:
    """Take a worktree made by `create` away again (a start that failed after it), best effort."""
    for cmd in (["git", "worktree", "remove", "--force", str(path)], ["git", "branch", "-D", branch]):
        with contextlib.suppress(WorktreeError):
            git(cmd, checkout)
