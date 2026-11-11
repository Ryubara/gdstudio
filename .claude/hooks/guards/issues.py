"""Issue order: a task agent works on a started issue (or an open pull request), and the labels that say so are not set
by hand (docs/studio/hooks.md#issues)."""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path
from typing import Any

from .shell import program
from .workspace import workspace_of

# `Issue: owner/repo#N` or `PR: owner/repo#N` at the start of a line of an agent's prompt (a list bullet, a quote mark
# or backticks around the reference are fine).
_WORK_LINE = re.compile(r"(?im)^[ \t>*-]*(Issue|PR)[ \t]*:[ \t]*`?([\w.-]+/[\w.-]+)#(\d+)`?")
IN_PROGRESS = "S-in-progress"
CRITICAL = "P-critical"
HOLD = "S-hold"  # merge.hold.label in .github/conventions.yml; a test keeps them equal


def ledger_key(repo: str, number: int | str) -> str:
    """The key `gds issue start` writes to the ledger for an issue (python/src/gds_tools/issues.py builds the same)."""
    return f"{repo}#{number}".lower()


def read_ledger(workspace: Path, config: dict[str, Any]) -> dict[str, Any]:
    """The started issues of `<workspace>/cache/issues-started.json` by key; empty when the file is missing."""
    path = workspace / config.get("issues", {}).get("ledger", "cache/issues-started.json")
    try:
        started = json.loads(path.read_text(encoding="utf-8")).get("started", {})
    except (OSError, ValueError, AttributeError):
        return {}
    return started if isinstance(started, dict) else {}


def pr_state(repo: str, number: str) -> str | None:
    """`OPEN`, `MERGED` or `CLOSED` for a pull request, `MISSING` when GitHub has none, None when it cannot tell (no
    network, no `gh`): a guard that cannot look lets the call through."""
    try:
        out = subprocess.run(
            ["gh", "pr", "view", number, "-R", repo, "--json", "state", "--jq", ".state"],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode == 0:
        return out.stdout.strip() or None
    text = out.stderr.lower()
    return "MISSING" if "could not resolve" in text or "no pull requests found" in text else None


def check_issue(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """A task agent starts on a started issue (`Issue: owner/repo#N`, in the ledger of `gds issue start`) or on an open
    pull request it continues (`PR: owner/repo#N`: a review, a red main, a conflict). Helpers are exempt."""
    rules = config.get("issues", {})
    inp = payload.get("tool_input") or {}
    kind = inp.get("subagent_type") or "general-purpose"
    exempt = [*config.get("agents", {}).get("helpers", []), *rules.get("exempt", [])]
    if not rules.get("enforce", True) or kind in exempt or kind in config.get("agents", {}).get("refused", []):
        return []
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace is None:
        return []
    ledger = read_ledger(workspace, config)
    wanted = _WORK_LINE.findall(inp.get("prompt") or "")
    reasons = []
    for label, repo, number in wanted:
        if label.lower() == "issue" and ledger_key(repo, number) not in ledger:
            reasons.append(
                f"{repo}#{number} was not started with `gds issue start`: run `uv run --project "
                f"{(workspace / 'repos' / 'gdstudio' / 'python').as_posix()} gds issue start {repo}#{number} "
                f"--agent <name>` (it refuses an issue that is not among the oldest ready ones and lists those)"
            )
        elif label.lower() == "pr" and pr_state(repo, number) in ("MISSING", "MERGED", "CLOSED"):
            reasons.append(f"{repo}#{number} is not an open pull request: name an issue started with `gds issue start`")
    if not wanted:
        reasons.append(
            f"the agent type {kind!r} works on one task, and its prompt names none: start the issue with `gds issue "
            f"start <owner/repo>#N --agent <name>` (oldest ready issues first, `gds issue list` shows them) and put "
            f"`Issue: <owner/repo>#N` on a line of the prompt. Work on an existing open pull request (a review, a red "
            f"main, a conflict) names it instead: `PR: <owner/repo>#N`"
        )
    return reasons


def label_values(words: list[str]) -> list[str]:
    """The labels a `gh issue|pr edit|create` command adds (`--add-label X`, `--label=X`, `-l X`, comma lists)."""
    found: list[str] = []
    for i, word in enumerate(words):
        flag, _, inline = word.partition("=")
        if flag in ("--add-label", "--label", "-l"):
            value = inline or (words[i + 1] if i + 1 < len(words) else "")
            found += [v.strip() for v in value.split(",") if v.strip()]
    return found


def check_labels(words: list[str]) -> list[str]:
    """`S-in-progress` is set only by `gds issue start` and never on a pull request; only the maintainer sets
    `P-critical`. Covers `gh issue|pr edit|create` and a `gh api` call that writes labels."""
    if len(words) < 3 or program(words) != "gh":
        return []
    area, verb = words[1], words[2]
    if area in ("issue", "pr") and verb in ("edit", "create"):
        added = label_values(words)
    elif area == "api" and any(w in ("-f", "-F", "--field", "--raw-field", "--input", "-X", "--method") for w in words):
        # a write: any word naming the label counts (labels[]=..., labels=..., a path) unless it is a read
        read = any(w.upper() == "GET" for w in words)
        added = [] if read else [t for w in words for t in re.split(r"[=,\s\"'\[\]]+", w) if t]
    else:
        return []
    reasons = []
    if IN_PROGRESS in added:
        reasons.append(
            "a pull request is in progress by existing and never carries S-in-progress"
            if area == "pr"
            else "`S-in-progress` is set only by `gds issue start <owner/repo>#N --agent <name>`, which keeps the "
            "oldest-first order and writes the ledger the hooks read; `gds issue release` puts an issue back"
        )
    if CRITICAL in added:
        reasons.append("only the maintainer sets P-critical: report an issue that should have it instead")
    return reasons
