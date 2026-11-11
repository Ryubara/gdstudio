"""Merges and holds: no `--admin`, no auto-merge of a manual path, and nothing merges or unlabels a pull request a
maintainer holds (docs/studio/hooks.md#hold)."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path
from urllib.parse import unquote

from .issues import HOLD
from .shell import flag_values
from .workspace import git


def manual_paths(repo: Path) -> list[str]:
    """merge.manual_paths of the repository's conventions (read with a regex: no YAML reader here)."""
    conv = repo / ".github" / "conventions.yml"
    if not conv.exists():
        return []
    found = re.search(
        r"^\s*manual_paths:\s*\[(.*?)\]",
        conv.read_text(encoding="utf-8"),
        re.MULTILINE | re.DOTALL,
    )
    return [p.strip().strip("'\"") for p in found.group(1).split(",") if p.strip()] if found else []


def check_merge(words: list[str], cwd: Path) -> list[str]:
    """`gh pr merge`: never `--admin`, and never on a pull request that changes a manual path (a maintainer merges
    those by hand, merge.manual_paths)."""
    if len(words) < 3 or words[1:3] != ["pr", "merge"]:
        return []
    args = words[3:]
    if "--admin" in args:
        return ["`gh pr merge --admin` bypasses the branch rules; let the required checks pass"]
    if "--disable-auto" in args:
        return []
    repo = Path(git(cwd, "rev-parse", "--show-toplevel") or cwd)
    paths = manual_paths(repo)
    if not paths:
        return []
    target = next((a for a in args if not a.startswith("-")), None)
    try:
        cmd = [
            "gh",
            "pr",
            "view",
            *([target] if target else []),
            "--json",
            "files",
            "--jq",
            ".files[].path",
        ]
        out = subprocess.run(cmd, cwd=repo, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    hits = [f for f in out.stdout.split() if any(f == p or (p.endswith("/") and f.startswith(p)) for p in paths)]
    if hits:
        return [f"this pull request changes {', '.join(hits[:5])}: a maintainer merges it by hand; report it instead"]
    return []


_API_MERGE = re.compile(r"repos/([\w.-]+/[\w.-]+)/pulls/(\d+)/merge\b")
_API_ISSUE = re.compile(r"repos/([\w.-]+/[\w.-]+)/issues/(\d+)(/labels)?(?:[/?]|$)")
_API_LABEL = re.compile(r"/labels/([^/?\s]+)")
_MERGE_MUTATIONS = re.compile(r"\b(mergePullRequest|enablePullRequestAutoMerge|enqueuePullRequest)\b")
_LABEL_MUTATIONS = re.compile(r"\b(removeLabelsFromLabelable|clearLabelsFromLabelable|updateLabel|deleteLabel)\b")
_VALUE_FLAGS = ("-R", "--repo", "-t", "--subject", "-b", "--body", "-F", "--body-file", "-A", "--author-email")
_HELD = f"a maintainer holds it (`{HOLD}`): stop and report; only the maintainer takes the label off"
_API_FIELD_FLAGS = ("-f", "-F", "--field", "--raw-field", "--input")
_API_VALUE_FLAGS = (*_API_FIELD_FLAGS, "-X", "--method", "-H", "--header", "-q", "--jq", "-t", "--template")
_API_VALUE_FLAGS += ("-p", "--preview", "--hostname", "--cache")


def held(target: str, repo: str | None, cwd: Path) -> bool | None:
    """Whether a pull request (its number, URL or branch) carries the hold label; None when GitHub cannot be asked. A
    guard that cannot look lets the call through: GitHub's required `hold` check is the rule, this explains it."""
    command = ["gh", "pr", "view", *([target] if target else []), *(["-R", repo] if repo else [])]
    try:
        out = subprocess.run(
            [*command, "--json", "labels", "--jq", ".labels[].name"],
            cwd=cwd if cwd.is_dir() else None,
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return HOLD in out.stdout.split() if out.returncode == 0 else None


def api_call(words: list[str]) -> tuple[str, list[str], list[str]]:
    """A `gh api` call as gh reads it: its upper-case HTTP method (`-X`, or POST when it sends fields or `--input`, else
    GET), its endpoints and the values of its fields (an `--input` file counts as a field with no text to read)."""
    method, endpoints, fields, i = "", [], [], 2
    while i < len(words):
        word = re.sub(r"^-i+(?=[^-])", "-", words[i])  # `-i` takes no value, so it can lead a cluster: `-iX POST`
        i += 1
        if not word.startswith("-") or word == "-":
            endpoints.append(word)
            continue
        flag, has_value, value = word.partition("=") if word.startswith("--") else (word[:2], len(word) > 2, word[2:])
        value = value.removeprefix("=")
        if flag in _API_VALUE_FLAGS and not has_value and i < len(words):
            value = words[i]
            i += 1
        if flag in ("-X", "--method"):
            method = value.upper()
        elif flag in _API_FIELD_FLAGS:
            fields.append(value)
    return method or ("POST" if fields else "GET"), endpoints, fields


def api_method(words: list[str]) -> str:
    """The HTTP method of a `gh api` call."""
    return api_call(words)[0]


def check_hold_api(words: list[str], cwd: Path) -> list[str]:
    """`gh api`: a merge of a held pull request, or any write that would take the label off it or off the repository."""
    if words[2] == "graphql":
        text = " ".join(words[3:])
        if _MERGE_MUTATIONS.search(text) or _LABEL_MUTATIONS.search(text):
            return [f"a GraphQL mutation cannot be read for `{HOLD}`: use `gh pr merge` or `gh pr edit` instead"]
        return []
    method, reasons = api_method(words), []
    if method == "GET":
        return []
    for word in words[2:]:
        path = unquote(word)
        merge = _API_MERGE.search(path)
        if merge and held(merge.group(2), merge.group(1), cwd):
            reasons.append(f"{merge.group(1)}#{merge.group(2)}: {_HELD}")
        label = _API_LABEL.search(path)
        if label:
            if label.group(1) == HOLD and method in ("DELETE", "PATCH"):
                reasons.append(f"`{HOLD}` is taken off only by the maintainer, by hand on the pull request's page")
            continue
        issue = _API_ISSUE.search(path)
        if not issue:
            continue
        replaces = method in ("DELETE", "PUT") if issue.group(3) else method == "PATCH" and "labels" in " ".join(words)
        if replaces and held(issue.group(2), issue.group(1), cwd):
            reasons.append(f"this replaces the labels of {issue.group(1)}#{issue.group(2)}: {_HELD}")
    return reasons


def check_hold(words: list[str], cwd: Path) -> list[str]:
    """The hook's half of the hold (docs/studio/hooks.md#hold): no merge command on a pull request carrying the label,
    and no
    removal of the label by a session. The label is what GitHub enforces; this says why, and it is what stops a session
    taking the label off, since a token cannot tell an agent from the maintainer."""
    if len(words) < 3:
        return []
    area, verb = words[1], words[2]
    if area == "api":
        return check_hold_api(words, cwd)
    if area == "label" and verb in ("delete", "edit") and HOLD in words[3:]:
        return [f"`{HOLD}` is the label GitHub's hold reads: it is not deleted or renamed"]
    if area in ("pr", "issue") and verb == "edit":
        removed = [name.strip() for value in flag_values(words, ("--remove-label",)) for name in value.split(",")]
        if HOLD in removed:
            return [f"`{HOLD}` is taken off only by the maintainer, on the pull request's page: report it instead"]
    if area == "pr" and verb == "merge" and "--disable-auto" not in words:
        target, repo = merge_target(words)
        if held(target, repo, cwd):
            return [f"{target or 'this pull request'}: {_HELD}"]
    return []


def merge_target(words: list[str]) -> tuple[str, str | None]:
    """The pull request a `gh pr merge` names (its number, URL or branch; '' for the current branch's) and the
    repository `-R` gives, if any."""
    positional = [
        word for i, word in enumerate(words[3:], 3) if not word.startswith("-") and words[i - 1] not in _VALUE_FLAGS
    ]
    named = flag_values(words, ("-R", "--repo"))
    return (positional[0] if positional else ""), (named[0] if named else None)
