"""Agent stalls: a task agent whose turn ends without a report is finished for good (docs/studio/hooks.md#stall)."""

from __future__ import annotations

import contextlib
import json
import re
import time
from pathlib import Path
from typing import Any

from .docs import report_of
from .workspace import workspace_of


def reads_as_report(text: str, config: dict[str, Any]) -> bool:
    """True when a final message names a pull request, lists mistakes (a report section) or says it is blocked."""
    return re.search(config.get("stop_check", {}).get("report", r"(?!)"), text) is not None


def refusal_key(payload: dict[str, Any]) -> str:
    """What identifies one agent run across its stop attempts: its id, else its transcript, else its type."""
    return str(payload.get("agent_id") or payload.get("agent_transcript_path") or payload.get("agent_type") or "?")


def _refusal_runs(path: Path, now: float) -> dict[str, Any]:
    """The refusal counts of the agent runs younger than a day; empty when the file is missing or unreadable."""
    try:
        return {k: v for k, v in json.loads(path.read_text(encoding="utf-8")).items() if now - v.get("time", 0) < 86400}
    except (OSError, ValueError, AttributeError):
        return {}


def _write_refusal_runs(path: Path, runs: dict[str, Any]) -> None:
    with contextlib.suppress(OSError):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(runs), encoding="utf-8")


def count_refusal(workspace: Path, payload: dict[str, Any], config: dict[str, Any]) -> int:
    """Records one more refusal for this agent run and returns how many there have been (this one included). Runs older
    than a day are dropped. When the file cannot be written the count is 1 every time, which only means the gate
    could hold an agent longer on a read-only disk, never that it breaks."""
    path = workspace / config.get("stop_check", {}).get("counter", "cache/stop-check.json")
    now = time.time()
    runs = _refusal_runs(path, now)
    key = refusal_key(payload)
    count = int(runs.get(key, {}).get("count", 0)) + 1
    runs[key] = {"count": count, "time": now}
    _write_refusal_runs(path, runs)
    return count


def clear_refusals(workspace: Path, payload: dict[str, Any], config: dict[str, Any]) -> None:
    """Forgets this agent run's refusals once its end is let through (a report, or the limit reached): a run that is
    resumed (SendMessage) and stalls again gets its own refusals instead of the spent count of the first stall."""
    path = workspace / config.get("stop_check", {}).get("counter", "cache/stop-check.json")
    runs = _refusal_runs(path, time.time())
    if runs.pop(refusal_key(payload), None) is not None:
        _write_refusal_runs(path, runs)


def stop_stall(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """Refuses the end of a task agent (`[stop_check] agents`) whose final message is not a report: a background agent
    that ends its turn on "Now the autopilot." is never woken again. Let go when the message names a pull request or a
    blocker, when a background task of the agent is still running (it is waiting for the notification), when there is
    no message to judge, and after `max_refusals` refusals, so no agent is held forever. An end that is let through
    because it reads as a report or because the limit was reached resets the agent's count, so a resumed agent that
    stalls again is refused again. Does not look at `stop_hook_active`: that flag cannot count past one."""
    rules = config.get("stop_check", {})
    if payload.get("agent_type") not in rules.get("agents", []) or payload.get("background_tasks"):
        return None
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    report = report_of(payload).strip()
    if workspace is None or not report:
        return None
    if reads_as_report(report, config):
        clear_refusals(workspace, payload, config)
        return None
    limit = int(rules.get("max_refusals", 2))
    count = count_refusal(workspace, payload, config)
    if count > limit:
        clear_refusals(workspace, payload, config)
        return None
    tail = report.splitlines()[-1][:120]
    return (
        f'You ended your turn on "{tail}" without a report. A background agent whose turn ends is finished: nothing '
        f"wakes it, so whatever you announced never runs, and the pull request never opens. Do the step now, in this "
        f"turn, with a tool call; or start a background command that notifies you when it ends and wait for it. When "
        f"the task is done, end with the report: the pull request link (https://github.com/<owner>/<repo>/pull/<n>) "
        f"and your Mistakes section. When you cannot go on, end with one line `Blocked: <what stops you>`. "
        f"(Refusal {count} of {limit}; after that the end is allowed.)"
    )
