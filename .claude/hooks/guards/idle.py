"""Idle issues: the coordinator does not stop while an issue that can start has no agent (docs/studio/hooks.md#idle)."""

from __future__ import annotations

import contextlib
import json
import re
import subprocess
import time
import tomllib
from pathlib import Path
from typing import Any

from .stall import _refusal_runs, _write_refusal_runs
from .workspace import issues_module, kit_root, workspace_of

IDLE_CACHE = "idle-check.json"  # beside the ledger; `gds issue` commands remove it (gds_tools.issues.IDLE_CACHE)
IDLE_COUNTER = "cache/idle-check-refusals.json"
_GITHUB_URL = re.compile(r"github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git)?/?$")
KIT_NAME = "gdstudio"  # the kit's entry in workspace.toml ([repos.gdstudio])


def queue_cap(kit: Path) -> int | None:
    """merge.queue_cap of the kit's conventions (read with a regex: no YAML reader here): while more kit pull requests
    than this are open, nothing new starts (docs/studio/starting-work.md#parallel); 0 freezes on any open one. None
    (no key, no file) is no freeze."""
    try:
        found = re.search(
            r"^\s*queue_cap:\s*(\d+)", (kit / ".github" / "conventions.yml").read_text(encoding="utf-8"), re.MULTILINE
        )
    except OSError:
        return None
    return int(found.group(1)) if found else None


def workspace_repositories(kit: Path) -> list[tuple[str, str]]:
    """(`owner/repo`, folder name) of every repository in the kit's workspace.toml that has a GitHub URL."""
    try:
        repos = tomllib.loads((kit / "workspace.toml").read_text(encoding="utf-8")).get("repos", {})
    except (OSError, ValueError):
        return []
    found = []
    for name, entry in repos.items():
        match = _GITHUB_URL.search(str((entry or {}).get("url", "")))
        if match:
            found.append((match.group(1), name))
    return found


class IdleCache:
    """The `gh` reads of one check, kept `seconds` in a file so a Stop every few seconds asks GitHub once a minute.
    `gds issue start|block|unblock|release` remove the file, so a change made through them shows at once."""

    def __init__(self, path: Path, seconds: float, budget: float):
        self.path, self.seconds, self.deadline = path, seconds, time.time() + budget
        try:
            self.entries = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            self.entries = {}
        if not isinstance(self.entries, dict):
            self.entries = {}

    def __call__(self, args: list[str]) -> str:
        """The output of `gh <args>`; raises (OSError, RuntimeError) when GitHub cannot be asked."""
        key, now = " ".join(args), time.time()
        entry = self.entries.get(key)
        if isinstance(entry, dict) and 0 <= now - entry.get("time", 0) < self.seconds:
            return str(entry.get("out", ""))
        left = self.deadline - now
        if left < 2:
            raise RuntimeError("the time for GitHub reads is used up")
        done = subprocess.run(
            ["gh", *args], capture_output=True, text=True, encoding="utf-8", timeout=min(20.0, left), check=False
        )
        if done.returncode != 0:
            raise RuntimeError(f"gh {' '.join(args[:3])} failed")
        self.entries[key] = {"time": now, "out": done.stdout}
        return done.stdout

    def save(self) -> None:
        now = time.time()
        fresh = {k: v for k, v in self.entries.items() if isinstance(v, dict) and 0 <= now - v.get("time", 0) < 600}
        with contextlib.suppress(OSError):
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(json.dumps(fresh), encoding="utf-8")


def idle_issues(workspace: Path, config: dict[str, Any], gh: Any = None) -> list[tuple[str, int, str, str]]:
    """The issues of every repository in workspace.toml that nobody works on and that may start: the window's "May start
    now", plus blocked ones whose blocker closed, as (repository, number, title, kind) with kind `start` or `unblock`.
    A repository GitHub cannot answer for is left out: a check that cannot look finds nothing. A paused repository
    (`paused` in workspace.toml) offers only its `P-critical` issues, and no unblocked ones. While the kit has more
    open pull requests than `queue_cap`, the landing freeze is on and nothing is idle: the queue lands first."""
    kit = kit_root(workspace)
    issues = issues_module(kit)
    if issues is None:
        return []
    rules = config.get("idle", {})
    ledger = workspace / config.get("issues", {}).get("ledger", "cache/issues-started.json")
    cache = None
    if gh is None:
        cache = gh = IdleCache(
            ledger.with_name(IDLE_CACHE), float(rules.get("cache_seconds", 60)), float(rules.get("budget_seconds", 40))
        )
    found: list[tuple[str, int, str, str]] = []
    paused = getattr(issues, "paused_repositories", lambda kit: {})(kit)  # an older kit checkout has none
    cap = queue_cap(kit)
    for repo, name in sorted(workspace_repositories(kit), key=lambda entry: entry[1] != KIT_NAME):  # the kit first
        try:
            game = workspace / "repos" / name
            size = issues.load_settings(kit, game if game.is_dir() else None).window
            open_issues, prs = issues.fetch(repo, gh)
            reason = paused.get(repo.lower(), "")
            window = issues.compute_window(repo, open_issues, prs, size, *([reason] if reason else []))
        except Exception:  # offline, rate limited, bad JSON, no access to the repository: fail open
            continue
        if name == KIT_NAME and cap is not None and len(prs) > cap:  # the landing freeze: no starts anywhere
            found = []
            break
        found += [(repo, i.number, i.title, "start") for i in window.allowed]
        if not getattr(window, "paused", ""):
            found += [(repo, i.number, i.title, "unblock") for i in getattr(window, "unblocked", [])]
    if cache:
        cache.save()
    return found


def idle_message(workspace: Path, found: list[tuple[str, int, str, str]], count: int, limit: int) -> str:
    """The refusal: the idle issues, and both ways out (start them, or block them with a reason)."""
    gds = f"uv run --project {(kit_root(workspace) / 'python').as_posix()} gds issue"

    def lines(kind: str) -> list[str]:
        items = [f"  {repo}#{number}  {title[:90]}" for repo, number, title, k in found if k == kind]
        return items[:8] + ([f"  ... and {len(items) - 8} more"] if len(items) > 8 else [])

    text = []
    if lines("start"):
        text += ["These issues may start now and no agent has them:", *lines("start")]
    if lines("unblock"):
        text += ["These issues are still blocked, but what they waited on has closed:", *lines("unblock")]
    text += [
        "Everything that can run in parallel runs (docs/studio/starting-work.md#parallel). Before you end the turn, "
        "for each:",
        f"- start it (`{gds} start <repo>#N --agent <name>`, then give an agent the Issue and Worktree lines);",
        f'- or take it out of the line with its reason: `{gds} block <repo>#N --on <#N|maintainer> --why "<text>"` '
        "(`--on #N` only when its body names #N as a dependency, in `### Blocked by`, `Depends on:`, "
        "`Starts after` or `Carried from`, or add "
        "`--conflict <path>...` naming the files both would edit in ways a merge cannot settle; or it waits on the "
        "maintainer. Same subsystem, same agent and in order are not reasons: docs/studio/starting-work.md#parallel). "
        "A block writes `S-blocked` and a `Blocked (...)` line;",
        f"- an unblocked one: `{gds} unblock <repo>#N`, then start it.",
        f"(Refusal {count} of {limit} in a row; after that the end is allowed until nothing is idle, or for an hour.)",
    ]
    return "\n".join(text)


def stop_idle(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """Refuses the end of the main session's turn while an issue that may start has no agent. Only `Stop`, which task
    agents never send (they send `SubagentStop`); a session started as an agent (`agent_type`) is not the coordinator.
    Like `stop_stall` it counts its own refusals (`stop_hook_active` cannot count past one) and gives up after
    `[idle] max_refusals` in a row: the count resets when nothing is idle, and lapses an hour after the last refusal."""
    rules = config.get("idle", {})
    if not rules.get("enforce", True) or payload.get("agent_type"):
        return None
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace is None:
        return None
    path = workspace / rules.get("counter", IDLE_COUNTER)
    key = str(payload.get("session_id") or "coordinator")
    now = time.time()
    runs = {k: v for k, v in _refusal_runs(path, now).items() if now - v.get("time", 0) < 3600}
    found = idle_issues(workspace, config)
    if not found:
        if runs.pop(key, None) is not None:
            _write_refusal_runs(path, runs)
        return None
    limit = int(rules.get("max_refusals", 2))
    count = int(runs.get(key, {}).get("count", 0))
    if count >= limit:
        return None
    runs[key] = {"count": count + 1, "time": now}
    _write_refusal_runs(path, runs)
    return idle_message(workspace, found, count + 1, limit)
