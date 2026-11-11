"""The kit's hook dispatcher (.claude/hooks) loaded for the tests, and how a test replaces a name of its guards."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

HOOKS = Path(__file__).resolve().parents[2] / ".claude" / "hooks"
sys.path.insert(0, str(HOOKS))
_spec = importlib.util.spec_from_file_location("dispatch", HOOKS / "dispatch.py")
dispatch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dispatch)
guards = dispatch.guards
CONFIG = dispatch.load_config(None)


def patch(monkeypatch: pytest.MonkeyPatch, name: str, value: Any) -> None:
    """Replace `name` in every module of the guards package that holds it: a module that imports a name from another
    holds its own binding, so replacing it in one module alone leaves the guards of the others calling the real one.
    The modules the package imports on first use are imported first, so none of them keeps the real one."""
    guards.modules()
    held = [
        module
        for key, module in list(sys.modules.items())
        if (key == "guards" or key.startswith("guards.")) and name in vars(module)
    ]
    assert held, f"no module of the guards package has {name!r}"
    for module in held:
        monkeypatch.setattr(module, name, value)


# The helpers of the hook suites (python/tests/hooks/): the real functions their fixtures replace, and payloads.

REAL_IDLE_ISSUES = guards.idle_issues
REAL_START_SWEEP = guards.start_sweep
REAL_START_DISK_GUARD = guards.start_disk_guard
FREE = {"gb": 500.0}  # the disk every test sees, unless it sets another


def shell(command: str, cwd: Path) -> dict:
    return {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd)}


def denied(payload: dict) -> str:
    out = dispatch.answer(payload, CONFIG)
    return out["hookSpecificOutput"]["permissionDecisionReason"] if out else ""


def queue_of(workspace: Path) -> Path:
    folder = workspace / "scratch" / "kit-lessons-queue"
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def context(event: str, cwd: Path, **extra) -> str:
    out = dispatch.answer({"hook_event_name": event, "cwd": str(cwd), **extra}, CONFIG)
    if not out:
        return ""
    assert out["hookSpecificOutput"]["hookEventName"] == event
    return out["hookSpecificOutput"]["additionalContext"]


READ = "\nRead: studio/hooks.md#docs, studio/starting-work.md#starting-an-agent"


def agent_call(workspace: Path, kind: str | None, prompt: str = "") -> dict:
    inp = {"prompt": prompt, **({"subagent_type": kind} if kind else {})}
    return {"hook_event_name": "PreToolUse", "tool_name": "Agent", "tool_input": inp, "cwd": str(workspace)}


def start_in_ledger(workspace: Path, *refs: str) -> None:
    """Write the ledger the way `gds issue start` does (through its own code, so the two keys cannot drift apart)."""
    from gds_tools import issues

    ledger = workspace / "cache" / "issues-started.json"
    started = issues.load_ledger(ledger)
    for ref in refs:
        repo, number = issues.parse_ref(ref)
        started[issues.ledger_key(repo, number)] = {"repo": repo, "number": number, "agent": "t"}
    issues.save_ledger(ledger, started)


def _kit_worktree(workspace: Path, name: str, commits: int) -> Path:
    tree = workspace / "worktrees" / "gdstudio" / name
    tree.mkdir(parents=True)

    def run(*a):
        subprocess.run(["git", "-C", str(tree), *a], check=True, capture_output=True)

    run("init", "-b", "main")
    run("-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", "base")
    run("update-ref", "refs/remotes/origin/main", "HEAD")
    run("switch", "-q", "-c", name)
    for n in range(commits):
        run("-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", f"c{n}")
    return tree


def stop_payload(workspace: Path, **extra) -> dict:
    return {"hook_event_name": "Stop", "cwd": str(workspace), **extra}


def subagent_stop_payload(workspace: Path, report: str, **extra) -> dict:
    return {
        "hook_event_name": "SubagentStop",
        "cwd": str(workspace),
        "agent_type": "godot-engineer",
        "last_assistant_message": report,
        **extra,
    }


READ_REPORT = "\n\nRead: studio/hooks.md#docs, studio/starting-work.md#starting-an-agent\nDocs gaps: none"
REPORT = (
    "Done.\n\nPR: https://github.com/Ryubara/deadnight/pull/412 (auto-merge off)\n\nMistakes: none\n\n"
    "Read: studio/hooks.md#stall\nDocs gaps: none"
)
