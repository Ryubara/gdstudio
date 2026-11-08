"""The branch and worktree of a started issue, made before the agent gets the work
(docs/studio/starting-work.md#worktree).

Agents used to make their own branches and merge commits, and a mistake in one (a merge message that `pr-rules`
refuses) was only found after the push, where fixing it takes a force push. `gds issue start` now creates the branch
from a fresh `origin/<default>` in `<workspace>/worktrees/<repo>/<branch>` and checks that the git hooks of the
repository (pre-commit, commit-msg, pre-push) are installed, so the checks run on this machine before anything is
pushed. Every path here is absolute: `git -C <relative path>` resolves inside the repository it is run from.
"""

from __future__ import annotations

import contextlib
import os
import re
import shutil
import subprocess
import tempfile
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
        done = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace", stdin=subprocess.DEVNULL
        )
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


def repair_legacy_hooks(folder: Path) -> list[str]:
    """Make the hooks that pre-commit moved aside (`pre-push.legacy`, Git LFS's) runnable on Windows.

    `pre-commit install` renames a hook that was already there to `<hook>.legacy` and runs it itself. Git LFS writes
    `#!/bin/sh`, which pre-commit looks for as a Windows path (`/bin/sh`) and does not find, so every `git push` died
    with `ExecutableNotFoundError: Executable /bin/sh not found`. `#!/usr/bin/env sh` is found through the PATH."""
    fixed = []
    if os.name != "nt":
        return fixed
    for legacy in sorted(folder.glob("*.legacy")):
        text = legacy.read_text(encoding="utf-8", errors="replace")
        if text.startswith("#!/bin/sh"):
            legacy.write_text("#!/usr/bin/env sh" + text.removeprefix("#!/bin/sh"), encoding="utf-8", newline="\n")
            fixed.append(legacy.name)
    return fixed


def check_pre_push_runs(worktree: Path, git: Run = run) -> None:
    """Run the installed pre-push hook with nothing to push (`git hook run`), so a hook that dies on this machine is
    found now and not by the agent's first push."""
    try:
        git(["git", "hook", "run", "pre-push", "--", "origin", "https://example.invalid/none.git"], worktree)
    except WorktreeError as error:
        raise WorktreeError(f"the pre-push hook does not run on this machine: {error}") from error


def ensure_hooks(worktree: Path, *, git: Run = run, install: Callable[[Path], None] | None = None) -> list[str]:
    """Check the hooks are installed for the repository of `worktree`, installing what is missing, and check again.
    Then run the pre-push hook once. Returns the lines to print; raises WorktreeError when a hook is still missing or
    does not run."""
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
    for name in repair_legacy_hooks(hooks_dir(worktree, git)):
        lines.append(f"hooks: {name} started with #!/bin/sh, which pre-commit cannot find on Windows; repaired")
    check_pre_push_runs(worktree, git)
    return [*lines, f"hooks: {', '.join(HOOK_TYPES)} installed and the pre-push hook runs ({hooks_dir(worktree, git)})"]


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


def checked_out(checkout: Path, worktrees: Path, git: Run = run) -> dict[str, Path]:
    """The branches that have a worktree folder on disk directly under `worktrees` (`git worktree list`), by name."""
    out = git(["git", "worktree", "list", "--porcelain"], checkout.resolve())
    found: dict[str, Path] = {}
    base = worktrees.resolve()
    for block in out.split("\n\n"):
        path, branch = "", ""
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = line.removeprefix("worktree ")
            elif line.startswith("branch refs/heads/"):
                branch = line.removeprefix("branch refs/heads/")
        folder = Path(path).resolve() if path else None
        if branch and folder and folder.is_dir() and folder.parent == base:
            found[branch] = folder
    return found


def existing(
    checkout: Path,
    worktrees: Path,
    title: str,
    number: int,
    *,
    branch: str = "",
    known: str = "",
    others: frozenset[str] = frozenset(),
    git: Run = run,
) -> list[tuple[str, Path]]:
    """The worktrees of an issue that already exist, as (branch, folder). An issue's worktree is the checkout of a
    branch named for it: the one `--branch` gave (alone, when given), else the one the ledger recorded for it
    (`known`) or the one `create` names from the title, with or without the issue number. A branch the ledger
    records for another issue (`others`) is never the issue's, even when the title makes the same name."""
    slug = branch_name(title, number)
    names = {branch} if branch else {name for name in (known, slug, f"{slug}-{number}") if name} - others
    return sorted((name, path) for name, path in checked_out(checkout, worktrees, git).items() if name in names)


def reuse(
    found: list[tuple[str, Path]],
    *,
    git: Run = run,
    install: Callable[[Path], None] | None = None,
) -> Worktree:
    """Hand an agent the one worktree an issue already has: its hooks are checked (and installed where missing) and
    nothing else changes, so the work in it (commits, uncommitted edits) stays. More than one is refused by name."""
    if len(found) > 1:
        listing = "\n".join(f"  {name}: {path.as_posix()}" for name, path in found)
        raise WorktreeError(
            f"the issue has {len(found)} worktrees and gds cannot tell which to continue:\n{listing}\n"
            "remove the ones that are not wanted (git worktree remove), or pass --branch <name> for one"
        )
    name, path = found[0]
    hooks = ensure_hooks(path, git=git, install=install)
    default = default_branch(path, git)
    dirty = len(git(["git", "status", "--porcelain"], path).splitlines())
    try:
        ahead = int(git(["git", "rev-list", "--count", f"origin/{default}..HEAD"], path).strip())
    except (WorktreeError, ValueError):
        ahead = 0
    state = f"{ahead} commit(s) ahead of origin/{default}, {dirty} changed file(s) not committed"
    return Worktree(
        path=path, branch=name, base="", hooks=[f"reused the worktree the issue already had: {state}", *hooks]
    )


def remove(checkout: Path, path: Path, branch: str, git: Run = run) -> None:
    """Take a worktree made by `create` away again (a start that failed after it), best effort."""
    for cmd in (["git", "worktree", "remove", "--force", str(path)], ["git", "branch", "-D", branch]):
        with contextlib.suppress(WorktreeError):
            git(cmd, checkout)


# --------------------------------------------------------------------------------------------------------------------
# Merging main into a branch (`gds merge-main`)
# --------------------------------------------------------------------------------------------------------------------

_TRAILER_LINE = re.compile(r"^Co-Authored-By: .+ <[^<>\s]+@[^<>\s]+>$", re.MULTILINE)


class MergeConflict(WorktreeError):
    """`origin/<default>` does not merge cleanly; the merge is left in progress for the agent to resolve."""


def toplevel(path: Path, git: Run = run) -> Path:
    """The worktree around `path`, as an absolute path."""
    return Path(git(["git", "rev-parse", "--show-toplevel"], path.resolve()).strip()).resolve()


def last_trailer(tree: Path, default: str, git: Run = run) -> str:
    """The newest `Co-Authored-By` line of the commits this branch has on top of `origin/<default>`, or ''."""
    log = git(["git", "log", "--format=%B%x1e", f"origin/{default}..HEAD"], tree)
    found = _TRAILER_LINE.findall(log)
    return found[0] if found else ""


def merge_message(branch: str, default: str, trailer: str) -> str:
    """The whole message of the merge commit: a title, a blank line, the one trailer, and nothing after it."""
    return f"Merge origin/{default} into {branch}\n\n{trailer}\n"


def unmerged(tree: Path, git: Run = run) -> list[str]:
    return git(["git", "diff", "--name-only", "--diff-filter=U"], tree).split()


def merge_main(path: Path, *, co_author: str = "", resume: bool = False, git: Run = run) -> list[str]:
    """Merge `origin/<default>` into the branch of the worktree at `path`, with a clean message.

    The merge is made with `--no-commit` and committed with the whole message from a file (`--cleanup=strip -F`), so
    nothing git appends (`# Conflicts:`) can follow the trailer. With conflicts it stops, leaves the merge in progress
    and lists the files; after `git add` of the resolved files, `resume=True` commits it. Returns the lines to print."""
    tree = toplevel(path, git)
    default = default_branch(tree, git)
    branch = git(["git", "rev-parse", "--abbrev-ref", "HEAD"], tree).strip()
    if branch in (default, "HEAD"):
        raise WorktreeError(f"{tree} is on {branch}; merge main into a work branch, in its own worktree")
    in_progress = Path(
        git(["git", "rev-parse", "--path-format=absolute", "--git-path", "MERGE_HEAD"], tree).strip()
    ).exists()
    if resume and not in_progress:
        raise WorktreeError("no merge is in progress; run `gds merge-main` without --continue")
    if not resume:
        if in_progress:
            raise WorktreeError("a merge is already in progress; resolve it, then `gds merge-main --continue`")
        if git(["git", "status", "--porcelain", "--untracked-files=no"], tree).strip():
            raise WorktreeError("the worktree has uncommitted changes; commit them first")
        git(["git", "fetch", "--quiet", "origin", default], tree)
        try:
            git(["git", "merge-base", "--is-ancestor", f"origin/{default}", "HEAD"], tree)
            return [f"{branch} already contains origin/{default}; nothing to merge"]
        except WorktreeError:
            pass
    trailer = co_author and f"Co-Authored-By: {co_author}" or last_trailer(tree, default, git)
    if not trailer:
        raise WorktreeError(
            'no Co-Authored-By trailer to use: pass --co-author "<model name> <noreply address>" '
            "(none of the branch's commits has one)"
        )
    if not resume:
        try:
            git(["git", "merge", "--no-commit", "--no-ff", f"origin/{default}"], tree)
        except WorktreeError:
            files = unmerged(tree, git)
            if not files:
                raise
            listing = "\n".join(f"  {name}" for name in files)
            raise MergeConflict(
                f"origin/{default} conflicts with {branch} in {len(files)} file(s):\n{listing}\n"
                "resolve them, `git add` each, then run `gds merge-main --continue` "
                "(do not `git commit --no-edit`: git would put a '# Conflicts:' paragraph after the trailer)"
            ) from None
    elif files := unmerged(tree, git):
        raise MergeConflict("still unmerged: " + ", ".join(files) + "; `git add` them, then `--continue`")
    message = Path(tempfile.mkdtemp(prefix="gds-merge-")) / "message.txt"
    message.write_text(merge_message(branch, default, trailer), encoding="utf-8", newline="\n")
    try:
        git(["git", "commit", "--cleanup=strip", "-F", str(message)], tree)
    finally:
        shutil.rmtree(message.parent, ignore_errors=True)
    stored = git(["git", "log", "-1", "--format=%B"], tree).strip().splitlines()
    if not stored or stored[-1] != trailer:
        raise WorktreeError(f"the merge commit does not end with its trailer: {stored[-1:]}")
    return [f"merged origin/{default} into {branch}; the message ends with the trailer", "push once: `git push`"]
