"""Local mains follow origin after a merge (docs/studio/hooks.md#mains)."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
from hook_support import CONFIG, context, guards


def _git(path: Path, *args: str) -> str:
    out = subprocess.run(
        ["git", "-C", str(path), "-c", "user.email=t@t", "-c", "user.name=t", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return out.stdout.strip()


@pytest.fixture()
def mains(workspace: Path, tmp_path_factory) -> tuple[Path, Path]:
    """An origin with one commit, and `<workspace>/repos/game` cloned from it on main."""
    origin = tmp_path_factory.mktemp("origin") / "game"
    origin.mkdir()
    _git(origin, "init", "-q", "-b", "main")
    (origin / "a.txt").write_text("1\n")
    _git(origin, "add", "-A")
    _git(origin, "commit", "-q", "-m", "one")
    (workspace / "repos").mkdir()
    subprocess.run(["git", "clone", "-q", str(origin), str(workspace / "repos" / "game")], check=True)
    return origin, workspace / "repos" / "game"


def _advance(origin: Path, text: str) -> str:
    (origin / "a.txt").write_text(text)
    _git(origin, "commit", "-q", "-am", text.strip())
    return _git(origin, "rev-parse", "HEAD")


def test_merge_commands_are_recognised():
    yes = ["gh pr merge 5 --squash", "gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=squash"]
    no = ["gh pr view 5", "gh api repos/o/r/pulls/12", "git merge main"]
    assert all(any(guards.is_merge(w) for w in guards.segments(c)) for c in yes)
    assert not any(any(guards.is_merge(w) for w in guards.segments(c)) for c in no)


def test_a_merge_command_pulls_the_local_main(mains, workspace):
    origin, local = mains
    head = _advance(origin, "2\n")
    payload = {"tool_name": "Bash", "tool_input": {"command": "gh pr merge 7 --squash"}, "cwd": str(workspace)}
    text = context("PostToolUse", workspace, **{k: v for k, v in payload.items() if k != "cwd"})
    assert _git(local, "rev-parse", "HEAD") == head
    assert "game: main pulled" in text
    other = {"tool_name": "Bash", "tool_input": {"command": "gh pr view 7"}}
    _advance(origin, "3\n")
    assert context("PostToolUse", workspace, **other) == ""
    assert _git(local, "rev-parse", "HEAD") == head


def test_local_changes_in_the_way_are_named_not_discarded(mains, workspace):
    origin, local = mains
    _advance(origin, "2\n")
    (local / "a.txt").write_text("mine\n")
    notes = guards.pull_mains(workspace, CONFIG, force=True)
    assert (local / "a.txt").read_text() == "mine\n"
    assert notes and "not pulled" in notes[0] and "ask before discarding" in notes[0]


def test_a_branch_checkout_is_left_alone_and_stop_is_throttled(mains, workspace):
    origin, local = mains
    _git(local, "switch", "-q", "-c", "feature")
    before = _git(local, "rev-parse", "HEAD")
    _advance(origin, "2\n")
    assert guards.pull_mains(workspace, CONFIG, force=True) == []
    assert _git(local, "rev-parse", "HEAD") == before
    _git(local, "switch", "-q", "main")
    assert guards.pull_mains(workspace, CONFIG) == []  # stamped by the forced pull a moment ago
    assert _git(local, "rev-parse", "HEAD") == before
    assert guards.pull_mains(workspace, CONFIG, force=True)


def test_session_start_pulls_the_local_main(mains, workspace):
    origin, local = mains
    head = _advance(origin, "2\n")
    assert "game: main pulled" in context("SessionStart", workspace)
    assert _git(local, "rev-parse", "HEAD") == head
