"""Finished worktrees are swept in the background (docs/studio/hooks.md#sweep)."""

from __future__ import annotations

import subprocess

import pytest
from hook_support import CONFIG, REAL_START_SWEEP, context, guards, patch


@pytest.fixture()
def sweeps(monkeypatch, workspace):
    """The real `start_sweep` with the process start recorded: (command, keyword arguments) per start."""
    started: list[tuple[list[str], dict]] = []

    class FakePopen:
        def __init__(self, command, **kwargs):
            started.append((command, kwargs))

    patch(monkeypatch, "start_sweep", REAL_START_SWEEP)
    monkeypatch.setattr(guards.subprocess, "Popen", FakePopen)
    monkeypatch.setattr(guards.shutil, "which", lambda name: "/bin/uv")
    return started


def test_the_sweep_starts_in_the_background_and_logs_to_scratch(sweeps, workspace):
    assert guards.start_sweep(workspace, CONFIG) is True
    command, kwargs = sweeps[0]
    assert command[:3] == ["/bin/uv", "run", "--project"] and command[-3:] == ["gds", "worktree", "sweep"]
    assert kwargs["stdin"] is subprocess.DEVNULL and kwargs["cwd"] == str(workspace)
    assert (workspace / "scratch" / "worktree-sweep.log").exists()  # opened for the child's output
    assert guards.start_sweep(workspace, CONFIG) is False  # stamped a moment ago: throttled
    assert guards.start_sweep(workspace, CONFIG, force=True) is True
    assert len(sweeps) == 2


def test_the_sweep_can_be_turned_off(sweeps, workspace):
    config = {**CONFIG, "sweep": {**CONFIG["sweep"], "enabled": False}}
    assert guards.start_sweep(workspace, config, force=True) is False and sweeps == []


def test_a_long_log_is_moved_aside(sweeps, workspace):
    log = workspace / "scratch" / "worktree-sweep.log"
    log.parent.mkdir()
    log.write_text("x" * 2_000_000)
    guards.start_sweep(workspace, CONFIG, force=True)
    assert log.with_suffix(".old.log").stat().st_size == 2_000_000 and log.stat().st_size == 0


def test_session_start_merge_and_stop_start_the_sweep(monkeypatch, workspace):
    calls = []
    patch(monkeypatch, "start_sweep", lambda ws, config, force=False: calls.append(force))
    context("SessionStart", workspace)
    context("PostToolUse", workspace, tool_name="Bash", tool_input={"command": "gh pr merge 7 --squash"})
    context("PostToolUse", workspace, tool_name="Bash", tool_input={"command": "gh pr view 7"})
    guards.stop({"cwd": str(workspace)}, CONFIG)
    assert calls == [False, True, False]  # session start, the merge (forced), Stop; viewing a pull request starts none
