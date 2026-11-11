"""Idle issues: the coordinator's Stop (docs/studio/hooks.md#idle)."""

from __future__ import annotations

import json
import subprocess

import pytest
from hook_support import (
    CONFIG,
    READ_REPORT,
    REAL_IDLE_ISSUES,
    dispatch,
    guards,
    patch,
    queue_of,
    stop_payload,
    subagent_stop_payload,
)

DEADNIGHT = "Ryubara/deadnight"
IDLE = [(DEADNIGHT, 52, "Add the bot rig", "start"), (DEADNIGHT, 57, "Add the bot loop", "start")]


@pytest.fixture()
def idle(monkeypatch):
    """The issues the idle check finds; a test sets `idle.found`. The other tests never reach GitHub."""

    class Found:
        found: list = []
        asked = 0

    state = Found()

    def look(workspace, config, gh=None):
        state.asked += 1
        return list(state.found)

    patch(monkeypatch, "idle_issues", look)
    return state


def test_a_coordinator_with_idle_issues_is_refused_and_told_both_ways_out(workspace, idle):
    idle.found = IDLE + [(DEADNIGHT, 60, "Remove the old rig", "unblock")]
    out = dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG)
    reason = out["reason"]
    assert out["decision"] == "block"
    assert f"{DEADNIGHT}#52" in reason and f"{DEADNIGHT}#57" in reason and "Add the bot rig" in reason
    assert f"{DEADNIGHT}#60" in reason and "what they waited on has closed" in reason
    assert "gds issue start <repo>#N --agent <name>" in reason
    assert 'gds issue block <repo>#N --on <#N|maintainer> --why "<text>"' in reason
    assert "gds issue unblock <repo>#N" in reason
    assert "`Depends on:`" in reason and "--conflict <path>..." in reason  # a block needs a dependency or files
    assert "Refusal 1 of 2" in reason


def test_nothing_idle_lets_the_coordinator_stop(workspace, idle):
    idle.found = []  # every startable issue has an agent, or was blocked with a reason
    assert dispatch.answer(stop_payload(workspace), CONFIG) is None


def test_a_task_agents_stop_and_an_agent_session_are_never_judged(workspace, idle):
    idle.found = IDLE
    out = dispatch.answer(subagent_stop_payload(workspace, "PR #5 opened.\n\nMistakes: none" + READ_REPORT), CONFIG)
    assert out is None and idle.asked == 0  # SubagentStop does not even look
    assert dispatch.answer(stop_payload(workspace, agent_type="godot-engineer"), CONFIG) is None
    assert idle.asked == 0


def test_the_check_is_off_outside_a_workspace_and_when_disabled(tmp_path_factory, workspace, idle):
    idle.found = IDLE
    bare = tmp_path_factory.mktemp("not-a-workspace")
    assert dispatch.answer({"hook_event_name": "Stop", "cwd": str(bare)}, CONFIG) is None
    off = {**CONFIG, "idle": {**CONFIG["idle"], "enforce": False}}
    assert dispatch.answer(stop_payload(workspace), off) is None


def test_it_refuses_at_most_max_refusals_in_a_row_then_starts_again_when_nothing_is_idle(workspace, idle):
    idle.found = IDLE
    reasons = [dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG) for _ in range(3)]
    assert "Refusal 1 of 2" in reasons[0]["reason"] and "Refusal 2 of 2" in reasons[1]["reason"]
    assert reasons[2] is None  # the coordinator ignored it twice: it is let go, never held forever
    # stop_hook_active (the session is already held by a Stop hook) does not turn the check off or make it loop
    assert dispatch.answer(stop_payload(workspace, session_id="s1", stop_hook_active=True), CONFIG) is None
    other = dispatch.answer(stop_payload(workspace, session_id="s2", stop_hook_active=True), CONFIG)
    assert other["decision"] == "block"  # another session has its own count; the flag only skips the other gates
    idle.found = []  # the coordinator started them, so the next Stop passes and the count is forgotten
    assert dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG) is None
    idle.found = IDLE
    assert "Refusal 1 of 2" in dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG)["reason"]


def test_a_refusal_count_lapses_after_an_hour(workspace, idle, monkeypatch):
    idle.found = IDLE
    for _ in range(2):
        assert dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG)
    assert dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG) is None
    now = guards.time.time()
    monkeypatch.setattr(guards.time, "time", lambda: now + 3700)
    assert "Refusal 1 of 2" in dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG)["reason"]


def test_idle_reasons_come_with_the_other_stop_gates(workspace, idle):
    idle.found = IDLE
    (queue_of(workspace) / "row.md").write_text("a row", encoding="utf-8")
    reason = dispatch.answer(stop_payload(workspace), CONFIG)["reason"]
    assert "Corrections are queued" in reason and "may start now and no agent has them" in reason


# The real look at GitHub, with `gh` replaced by recorded answers.

WINDOW_ISSUES = [
    {"number": 52, "title": "ready", "labels": [{"name": "S-ready-to-start"}], "assignees": [], "body": ""},
    {"number": 53, "title": "agent has it", "labels": [{"name": "S-in-progress"}], "assignees": [], "body": ""},
    {
        "number": 54,
        "title": "blocked on a closed issue",
        "labels": [{"name": "S-blocked"}],
        "assignees": [],
        "body": "Blocked (coordinator, 2026-11-02): waits on #200: the rig",
    },
    {
        "number": 55,
        "title": "blocked on an open one",
        "labels": [{"name": "S-blocked"}],
        "assignees": [],
        "body": "Blocked (coordinator, 2026-11-02): waits on #52: the rig",
    },
]


def fake_gh(issues_json: list | None = None, calls: list | None = None):
    def gh(args: list[str]) -> str:
        if calls is not None:
            calls.append(args)
        return (
            json.dumps(WINDOW_ISSUES if issues_json is None else issues_json) if args[:2] == ["issue", "list"] else "[]"
        )

    return gh


PAUSES: dict[str, str] = {}  # what the hook's issues module reads as paused (the real workspace.toml pauses deadnight)


@pytest.fixture()
def one_repository(monkeypatch):
    patch(monkeypatch, "workspace_repositories", lambda kit: [(DEADNIGHT, "deadnight")])
    PAUSES.clear()
    monkeypatch.setattr(guards.issues_module(guards.KIT), "paused_repositories", lambda kit: dict(PAUSES))


def test_idle_issues_finds_the_window_and_the_unblocked(workspace, one_repository):
    found = REAL_IDLE_ISSUES(workspace, CONFIG, gh=fake_gh())
    assert found == [(DEADNIGHT, 52, "ready", "start"), (DEADNIGHT, 54, "blocked on a closed issue", "unblock")]


def test_all_started_or_blocked_means_nothing_idle(workspace, one_repository):
    rows = [r for r in WINDOW_ISSUES if r["number"] in (53, 55)]
    rows.append({"number": 52, "title": "now started", "labels": [{"name": "S-in-progress"}], "assignees": []})
    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=fake_gh(rows)) == []


def test_idle_issues_fails_open_when_github_cannot_answer(workspace, one_repository):
    def broken(args):
        raise RuntimeError("offline")

    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=broken) == []

    def garbage(args):
        return "not json"

    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=garbage) == []


def test_a_paused_repository_offers_nothing_but_its_critical_issues(workspace, one_repository):
    PAUSES[DEADNIGHT.lower()] = "by the maintainer on 2026-11-07, for kit work first"
    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=fake_gh()) == []  # neither #52 (ready) nor #54 (unblocked)
    rows = [*WINDOW_ISSUES, {"number": 60, "title": "urgent", "labels": [{"name": "P-critical"}], "assignees": []}]
    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=fake_gh(rows)) == [(DEADNIGHT, 60, "urgent", "start")]


def test_the_stop_hook_reads_the_pause_of_the_kits_workspace_toml():
    paused = guards.issues_module(guards.KIT).paused_repositories(guards.KIT)
    assert paused.get("ryubara/deadnight") and "ryubara/gdstudio" not in paused


def test_every_repository_of_workspace_toml_is_looked_at():
    names = [repo for repo, _ in guards.workspace_repositories(guards.KIT)]
    assert "Ryubara/gdstudio" in names and "Ryubara/deadnight" in names


def test_the_gh_reads_are_cached_for_a_minute(tmp_path, monkeypatch):
    calls = []

    def run(command, **kwargs):
        calls.append(command)
        return subprocess.CompletedProcess(command, 0, stdout="[]", stderr="")

    monkeypatch.setattr(guards.subprocess, "run", run)
    path = tmp_path / "cache" / "idle-check.json"
    first = guards.IdleCache(path, 60, 40)
    first(["issue", "list", "-R", DEADNIGHT])
    first(["issue", "list", "-R", DEADNIGHT])
    first.save()
    assert len(calls) == 1
    second = guards.IdleCache(path, 60, 40)  # the next Stop, seconds later
    second(["issue", "list", "-R", DEADNIGHT])
    assert len(calls) == 1
    now = guards.time.time()
    monkeypatch.setattr(guards.time, "time", lambda: now + 61)
    guards.IdleCache(path, 60, 40)(["issue", "list", "-R", DEADNIGHT])
    assert len(calls) == 2  # a minute later it asks again


def test_a_failing_gh_and_a_used_up_budget_raise_instead_of_hanging(tmp_path, monkeypatch):
    monkeypatch.setattr(
        guards.subprocess, "run", lambda command, **kw: subprocess.CompletedProcess(command, 1, stdout="", stderr="no")
    )
    with pytest.raises(RuntimeError):
        guards.IdleCache(tmp_path / "c.json", 60, 40)(["issue", "list"])
    with pytest.raises(RuntimeError, match="used up"):
        guards.IdleCache(tmp_path / "c.json", 60, 0)(["issue", "list"])


def test_the_hook_reads_the_kits_own_window_code(workspace):
    module = guards.issues_module(guards.KIT)
    assert module is not None and hasattr(module, "compute_window") and hasattr(module, "parse_block")
