"""Commits and pushes: never on a protected branch, never forced, never past the hooks, and none under the disk's hard
limit."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from .disk import disk_refusal
from .shell import git_dir_anchored, git_dir_of
from .workspace import git

UNKNOWN_FOLDER = (
    "`git {verb}` after a `cd` the hook cannot follow (`$(...)`, a variable the line did not set to a plain path, "
    "`cd -`, `popd`): it cannot tell which branch it would {act}, and the session's folder may be another checkout. "
    'Run `git -C <absolute worktree path> {verb} ...`, or `cd` to a plain absolute path (or `WT=<path>; cd "$WT"`, '
    "`$wt = '<path>'; Set-Location $wt`) first"
)


def check_git(words: list[str], cwd: Path, config: dict[str, Any], unknown: bool = False) -> list[str]:
    """Commits and pushes: never on a protected branch, never forced, never past the hooks. `unknown` says a `cd`
    before it could not be followed: then a commit, or a push to the current branch, is refused unless an absolute
    `-C` names its folder, rather than judged by the branch of the session's folder (gdstudio #1520)."""
    here, rest = git_dir_of(words, cwd)
    if not rest:
        return []
    unknown = unknown and not git_dir_anchored(words)
    verb, args = rest[0], rest[1:]
    protected = config.get("git", {}).get("protected_branches", ["main"])
    reasons: list[str] = []
    if verb == "worktree" and args[:1] == ["add"]:
        refused = disk_refusal(here, config, "a new worktree")
        if refused:
            reasons.append(refused)
    if verb in ("commit", "push") and ("--no-verify" in args or (verb == "commit" and "-n" in args)):
        reasons.append(f"`git {verb} --no-verify` skips the checks; fix what they report instead")
    if verb == "commit" and unknown:
        reasons.append(UNKNOWN_FOLDER.format(verb=verb, act="commit on"))
    elif verb == "commit":
        branch = git(here, "rev-parse", "--abbrev-ref", "HEAD")
        if branch in protected:
            reasons.append(
                f"`{branch}` takes no commits: `git switch -c <branch>` (or a worktree under "
                f"<workspace>/worktrees/<repo>/<branch>/) and open a pull request"
            )
    if verb == "push":
        if any(
            a in ("--force", "-f", "--force-with-lease", "--force-if-includes")
            or a.startswith("--force")
            or (not a.startswith("-") and a.startswith("+"))
            for a in args
        ):
            reasons.append("force-pushing is a maintainer decision; push a new commit instead")
        refspecs = [a for a in args if not a.startswith("-")][1:]  # the first is the remote
        targets = {r.split(":")[-1].removeprefix("refs/heads/").lstrip("+") for r in refspecs}
        if not refspecs or "HEAD" in targets:  # `git push`, `git push origin HEAD`: the current branch
            if unknown:
                return [*reasons, UNKNOWN_FOLDER.format(verb=verb, act="push")]
            targets = (targets - {"HEAD"}) | {git(here, "rev-parse", "--abbrev-ref", "HEAD")}
        hit = sorted(t for t in targets if t in protected)
        if hit:
            reasons.append(f"`{hit[0]}` takes no pushes: push your branch and open a pull request")
    return reasons
