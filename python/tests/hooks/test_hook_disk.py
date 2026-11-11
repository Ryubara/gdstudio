"""The disk guard (docs/studio/hooks.md#disk)."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from hook_support import CONFIG, FREE, READ, REAL_START_DISK_GUARD, context, denied, dispatch, guards, patch, shell


def disk_agent_call(cwd: Path, kind: str = "godot-engineer") -> dict:
    prompt = "Issue: Ryubara/deadnight#7\nDo it." + READ
    return {
        "hook_event_name": "PreToolUse",
        "tool_name": "Agent",
        "cwd": str(cwd),
        "tool_input": {"subagent_type": kind, "prompt": prompt},
    }


def started_ledger(workspace: Path) -> None:
    (workspace / "cache").mkdir(exist_ok=True)
    (workspace / "cache" / "issues-started.json").write_text(
        json.dumps({"started": {"ryubara/deadnight#7": {"branch": "b"}}})
    )


def test_a_task_agent_is_refused_under_the_hard_limit_and_starts_above_it(workspace):
    started_ledger(workspace)
    (workspace / "cache" / "disk-guard.json").write_text(
        json.dumps({"biggest": [{"path": "scratch/deadnight/web-night-load", "gb": 6.1}]})
    )
    FREE["gb"] = 4.0
    reason = denied(disk_agent_call(workspace))
    assert "starting a godot-engineer agent is refused: the disk has 4.0 GB free, under the hard limit of 10" in reason
    assert "scratch/deadnight/web-night-load 6.1 GB" in reason
    FREE["gb"] = 20.0  # soft: agents still start
    assert denied(disk_agent_call(workspace)) == ""


def test_helpers_and_the_reviewer_start_under_the_hard_limit(workspace):
    FREE["gb"] = 1.0
    assert denied(disk_agent_call(workspace, "Explore")) == ""
    assert denied(disk_agent_call(workspace, "reviewer")) == ""


def test_git_worktree_add_is_refused_under_the_hard_limit(workspace):
    repo = workspace / "repos" / "game"
    repo.mkdir(parents=True)
    subprocess.run(["git", "-C", str(repo), "init", "-q", "-b", "main"], check=True)
    command = "git worktree add ../../worktrees/game/x -b x"
    assert denied(shell(command, repo)) == ""
    FREE["gb"] = 2.0
    assert "a new worktree is refused" in denied(shell(command, repo))
    assert denied(shell("git worktree list", repo)) == ""


def test_outside_a_workspace_the_disk_is_not_checked(tmp_path):
    FREE["gb"] = 1.0
    assert "disk" not in denied(disk_agent_call(tmp_path, "Explore"))
    assert denied(shell("git worktree add x", tmp_path)) == ""


def test_an_agent_is_told_to_keep_its_output_small_under_the_soft_limit(workspace):
    FREE["gb"] = 30.0
    text = context("SubagentStart", workspace, agent_type="godot-engineer")
    assert "Disk SOFT: 30.0 GB free" in text and "reduce downloaded CI artifacts to their numbers" in text
    FREE["gb"] = 80.0
    assert "Disk" not in context("SubagentStart", workspace, agent_type="godot-engineer")


def test_the_disk_guard_starts_in_the_background_and_is_throttled(monkeypatch, workspace):
    started: list[list[str]] = []

    class FakePopen:
        def __init__(self, command, **kwargs):
            started.append(command)

    patch(monkeypatch, "start_disk_guard", REAL_START_DISK_GUARD)
    monkeypatch.setattr(guards.subprocess, "Popen", FakePopen)
    monkeypatch.setattr(guards.shutil, "which", lambda name: "/bin/uv")
    assert guards.start_disk_guard(workspace, CONFIG) is True
    assert started[0][-3:] == ["gds", "disk", "guard"]
    assert (workspace / "scratch" / "disk-guard.log").exists()
    assert guards.start_disk_guard(workspace, CONFIG) is False  # within every_seconds
    assert guards.start_disk_guard(workspace, CONFIG, force=True) is True
    off = {**CONFIG, "disk": {**CONFIG["disk"], "enabled": False}}
    assert guards.start_disk_guard(workspace, off, force=True) is False
    # every tool call in a workspace may start it (throttled by the stamp)
    (workspace / "cache" / "disk-guard-started").unlink()
    dispatch.answer(shell("ls", workspace), CONFIG)
    assert len(started) == 3
