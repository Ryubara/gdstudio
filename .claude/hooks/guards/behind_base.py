"""A merge only of a pull request that holds the tip of its base (docs/studio/hooks.md#behind), and the warnings of a
guard that could not ask GitHub."""

from __future__ import annotations

import contextlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any
from urllib.parse import unquote

from .merges import _API_MERGE, api_method, merge_target
from .workspace import WARNINGS, git, workspace_of

_PR_URL = re.compile(r"github\.com/([\w.-]+/[\w.-]+)/pull/\d+")
SHOWN_COMMITS = 5


def gh_text(command: list[str], cwd: Path, what: str) -> str:
    """The output of a `gh` command; raises `LookupError(why)` when GitHub cannot be asked or says no."""
    try:
        out = subprocess.run(command, cwd=cwd if cwd.is_dir() else None, capture_output=True, text=True, timeout=20)
    except subprocess.TimeoutExpired:
        raise LookupError(f"{what} timed out") from None
    except (OSError, subprocess.SubprocessError) as error:
        raise LookupError(f"{what} did not run: {error}") from None
    if out.returncode != 0:
        raise LookupError(f"{what} failed: {(out.stderr or out.stdout).strip()[:200] or out.returncode}")
    return out.stdout.strip()


def behind(target: str, repo: str | None, cwd: Path) -> tuple[dict[str, Any] | None, str]:
    """How far a pull request's head is behind its base branch, as GitHub's compare API counts it (the local clone may
    be stale): `({repo, number, base, branch, behind_by, commits}, '')`, `commits` being the base's commits the head
    lacks as `<sha> <subject>` lines (empty when only the count could be read); `(None, why)` when GitHub cannot say."""
    try:
        view = ["gh", "pr", "view", *([target] if target else []), *(["-R", repo] if repo else [])]
        fields = "number,baseRefName,headRefName,headRefOid,url"
        try:
            pr = json.loads(gh_text([*view, "--json", fields], cwd, "reading the pull request"))
            number, base, branch, head = pr["number"], pr["baseRefName"], pr["headRefName"], pr["headRefOid"]
            repo = repo or _PR_URL.search(pr["url"]).group(1)
        except (ValueError, KeyError, TypeError, AttributeError):
            raise LookupError("reading the pull request gave no number, base and head") from None
        compare = f"repos/{repo}/compare/"
        count = gh_text(["gh", "api", f"{compare}{base}...{head}", "--jq", ".behind_by"], cwd, "the compare call")
        try:
            lacking = int(count)
        except ValueError:
            raise LookupError(f"the compare call gave {count[:40]!r} for behind_by") from None
        commits: list[str] = []
        if lacking:
            jq = '.commits[] | .sha[0:9] + " " + (.commit.message | split("\\n")[0])'
            with contextlib.suppress(LookupError):  # the count alone still refuses
                commits = gh_text(["gh", "api", f"{compare}{head}...{base}", "--jq", jq], cwd, "the list").splitlines()
        return {
            "repo": repo,
            "number": number,
            "base": base,
            "branch": branch,
            "behind_by": lacking,
            "commits": commits,
        }, ""
    except LookupError as error:
        return None, str(error)


def worktree_of(branch: str, cwd: Path) -> Path | None:
    """The worktree where `branch` is checked out, found from any checkout of the repository (None: no worktree)."""
    found = None
    for line in git(cwd, "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            found = line.removeprefix("worktree ")
        elif line == f"branch refs/heads/{branch}" and found:
            return Path(found).resolve()
    return None


def behind_reason(found: dict[str, Any], cwd: Path) -> str:
    """The refusal for a pull request whose head lacks `found["behind_by"]` commits of its base."""
    count, base = found["behind_by"], found["base"]
    commits = found["commits"]
    named = ", ".join(commits[:SHOWN_COMMITS]) + (
        f" and {len(commits) - SHOWN_COMMITS} more" if len(commits) > SHOWN_COMMITS else ""
    )
    workspace = workspace_of(cwd)
    gds = f"uv run --project {(workspace / 'repos' / 'gdstudio' / 'python').as_posix()} gds" if workspace else "gds"
    tree = worktree_of(found["branch"], cwd)
    return (
        f"{found['repo']}#{found['number']} is {count} commit{'s' * (count != 1)} behind {base}"
        f"{f' (missing: {named})' if commits else ''}: refresh it with `{gds} merge-main --path "
        f"{tree.as_posix() if tree else '<worktree>'}`, push once, and merge when its checks have passed on that head "
        "(docs/studio/starting-work.md#landing)"
    )


def check_behind(words: list[str], cwd: Path) -> list[str]:
    """A merge command (`gh pr merge`, with or without `--auto`, or a write to `gh api .../pulls/<n>/merge`) on a pull
    request whose head does not contain the tip of its base branch. GitHub's own answer decides; when it cannot be
    asked the call goes through with a warning, never silently."""
    if len(words) < 3 or words[1] not in ("pr", "api"):
        return []
    asks: list[tuple[str, str | None]] = []
    if words[1] == "pr" and words[2] == "merge" and "--disable-auto" not in words:
        asks.append(merge_target(words))
    elif words[1] == "api" and words[2] != "graphql" and api_method(words) != "GET":
        for word in words[2:]:
            merge = _API_MERGE.search(unquote(word))
            if merge:
                asks.append((merge.group(2), merge.group(1)))
    reasons = []
    for target, repo in asks:
        found, why = behind(target, repo, cwd)
        if found is None:
            WARNINGS.append(
                f"the merge guard could not check whether {target or 'this pull request'} holds the tip of its base "
                f"({why}); the call goes through, so check it yourself (`gh pr view --json mergeStateStatus`)"
            )
        elif found["behind_by"] > 0:
            reasons.append(behind_reason(found, cwd))
    return reasons
