"""Agent stalls (docs/studio/hooks.md#stall)."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

from hook_support import CONFIG, HOOKS, READ_REPORT, REPORT, _kit_worktree, dispatch, patch, subagent_stop_payload

STALLED = "I ran the unit tests and they pass.\n\nNow the autopilot."


def write_transcript(path: Path, last: str) -> Path:
    """A subagent transcript the way Claude Code writes it: one JSON entry per line, the prompt first."""
    lines = [
        {"type": "user", "message": {"role": "user", "content": "Issue: Ryubara/deadnight#226"}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": "Bash"}]}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": last}]}},
    ]
    path.write_text("\n".join(json.dumps(line) for line in lines), encoding="utf-8")
    return path


def stall_answer(workspace: Path, report: str, **extra):
    return dispatch.answer(subagent_stop_payload(workspace, report, **{"agent_id": "a1", **extra}), CONFIG)


def test_a_transcript_ending_on_an_announced_step_is_refused(workspace, tmp_path, monkeypatch):
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    payload = {"hook_event_name": "SubagentStop", "cwd": str(workspace), "agent_type": "godot-engineer"}
    transcript = write_transcript(tmp_path / "agent.jsonl", STALLED)
    out = dispatch.answer({**payload, "agent_id": "a1", "agent_transcript_path": str(transcript)}, CONFIG)
    assert out["decision"] == "block"
    assert "Now the autopilot." in out["reason"] and "Blocked:" in out["reason"] and "Refusal 1 of 2" in out["reason"]


def test_the_message_of_the_hook_input_is_judged_too(workspace):
    for kind in ("godot-engineer", "backend-engineer", "blender-artist"):
        out = stall_answer(workspace, STALLED, agent_type=kind, agent_id=kind)
        assert out["decision"] == "block", kind


def test_a_level_designer_ending_without_a_report_is_refused(workspace):
    out = stall_answer(workspace, STALLED, agent_type="level-designer", agent_id="ld1")
    assert out["decision"] == "block"
    assert "Now the autopilot." in out["reason"]
    assert stall_answer(workspace, REPORT, agent_type="level-designer", agent_id="ld2") is None


def test_a_report_with_a_pull_request_passes(workspace, tmp_path):
    assert stall_answer(workspace, REPORT) is None
    transcript = write_transcript(tmp_path / "agent.jsonl", REPORT)
    payload = {"hook_event_name": "SubagentStop", "cwd": str(workspace), "agent_type": "backend-engineer"}
    assert dispatch.answer({**payload, "agent_transcript_path": str(transcript)}, CONFIG) is None
    assert stall_answer(workspace, "Opened PR #148 and left auto-merge off." + READ_REPORT) is None


def test_a_blocked_line_passes(workspace):
    for text in (
        "Blocked: the Railway token is expired; the maintainer has to log in.",
        "Tried three times.\n\n**Blocked** - no Discord application exists yet.",
        "- Blocker: the pinned Godot has no export template.",
        "I stopped because the issue asks for a licence decision.",
    ):
        assert stall_answer(workspace, text) is None, text


def test_a_blocked_word_inside_an_announced_step_is_not_a_report(workspace):
    out = stall_answer(workspace, "The unblocked path works. Now the export check.")
    assert out and out["decision"] == "block"


def test_a_reviewer_and_the_helpers_are_never_held(workspace):
    for kind in ("reviewer", "Explore", "Plan", "web-fetch", "claude", "fork"):
        assert stall_answer(workspace, STALLED, agent_type=kind, agent_id=kind) is None, kind


def test_an_agent_with_a_running_background_task_is_waiting_not_stalled(workspace):
    assert stall_answer(workspace, "Started the web build; waiting for it.", background_tasks=[{"id": "b1"}]) is None
    assert stall_answer(workspace, "Started the web build; waiting for it.", background_tasks=[])["decision"] == "block"


def test_the_hook_cannot_hold_an_agent_forever(workspace):
    answers = [stall_answer(workspace, STALLED, stop_hook_active=i > 0) for i in range(3)]
    assert [bool(a) for a in answers] == [True, True, False]  # max_refusals = 2, even with stop_hook_active
    assert "Refusal 2 of 2" in answers[1]["reason"]
    other = stall_answer(workspace, STALLED, agent_id="a2")  # another agent run has its own count
    assert other["decision"] == "block"


def test_a_resumed_agent_that_stalls_again_is_refused_again(workspace):
    """Kit #156: the count is spent by the first stall; the allowed end must reset it, or the second stall goes free."""
    first = [stall_answer(workspace, STALLED) for _ in range(3)]
    assert [bool(a) for a in first] == [True, True, False]  # two refusals, then the end is allowed
    # the agent is resumed (SendMessage) and stalls again the same day, with the same agent_id
    second = [stall_answer(workspace, STALLED) for _ in range(3)]
    assert [bool(a) for a in second] == [True, True, False]
    assert "Refusal 1 of 2" in second[0]["reason"]


def test_a_report_resets_the_count_of_the_agent(workspace):
    assert stall_answer(workspace, STALLED)["decision"] == "block"
    assert stall_answer(workspace, REPORT) is None  # the end let through as a report
    again = [stall_answer(workspace, STALLED) for _ in range(3)]  # resumed, stalls again
    assert [bool(a) for a in again] == [True, True, False]
    assert "Refusal 1 of 2" in again[0]["reason"]


def test_the_limit_is_a_setting(workspace):
    config = {**CONFIG, "stop_check": {**CONFIG["stop_check"], "max_refusals": 1}}
    payload = subagent_stop_payload(workspace, STALLED, agent_id="a1")
    assert dispatch.answer(payload, config)["decision"] == "block"
    assert dispatch.answer(payload, config) is None


def test_nothing_to_judge_or_no_workspace_lets_the_end_through(workspace, tmp_path_factory):
    assert stall_answer(workspace, "") is None  # no message and no transcript: a guard that cannot look lets go
    elsewhere = tmp_path_factory.mktemp("elsewhere")
    payload = subagent_stop_payload(elsewhere, STALLED, agent_id="a1")
    assert dispatch.answer(payload, CONFIG) is None  # not a GDStudio workspace


def test_a_stall_and_unpublished_docs_come_back_together(workspace, monkeypatch):
    tree = _kit_worktree(workspace, "docs-b", 1)
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    reason = stall_answer(workspace, STALLED, cwd=str(tree))["reason"]
    assert "without a report" in reason and "docs-b" in reason
    again = stall_answer(
        workspace, STALLED, cwd=str(tree), stop_hook_active=True
    )  # the docs gate lets go once held; the stall gate counts
    assert "without a report" in again["reason"] and "docs-b" not in again["reason"]


def test_the_stall_gate_through_the_real_process(workspace):
    """As Claude Code starts it: a stalled end gets the block JSON with exit code 0, a report gets no output."""
    script = HOOKS / "dispatch.py"
    for report, blocked in (("Now the gap mode run and look at frames of both.", True), (REPORT, False)):
        payload = subagent_stop_payload(workspace, report, agent_id="proc", stop_hook_active=False)
        run = subprocess.run(
            [sys.executable, str(script)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env={"PATH": "", "CLAUDE_PROJECT_DIR": str(workspace)},
            timeout=60,
        )
        assert run.returncode == 0 and run.stderr == ""
        assert (json.loads(run.stdout)["decision"] == "block") if blocked else run.stdout == ""
