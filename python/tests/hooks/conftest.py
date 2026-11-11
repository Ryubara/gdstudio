"""The fixtures every hook test shares: no test reaches GitHub, the sweep, the disk guard or a real disk, and the
throwaway repository and workspace the guards judge."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest
from hook_support import FREE, guards, patch


@pytest.fixture(autouse=True)
def no_github_at_stop(monkeypatch):
    """The coordinator's Stop check asks GitHub; no test reaches it unless it says so (the `idle` fixture)."""
    patch(monkeypatch, "idle_issues", lambda workspace, config, gh=None: [])


@pytest.fixture(autouse=True)
def no_sweep(monkeypatch):
    """No test starts the real `gds worktree sweep` (it would remove worktrees of this machine); the `sweeps` fixture
    records the starts instead."""
    patch(monkeypatch, "start_sweep", lambda workspace, config, force=False: False)


@pytest.fixture(autouse=True)
def roomy_disk(monkeypatch):
    """No test starts the real `gds disk guard`, and every test sees a disk with room, whatever this machine has."""
    FREE["gb"] = 500.0
    patch(monkeypatch, "start_disk_guard", lambda workspace, config, force=False: False)
    patch(monkeypatch, "free_bytes", lambda path: int(FREE["gb"] * guards.GB))


@pytest.fixture(autouse=True)
def heads_hold_main(monkeypatch):
    """No test asks GitHub whether a pull request is behind its base: every head holds the tip (python/tests/
    test_merge_guard.py has the merge guard's own tests)."""
    guards.take_warnings()
    patch(monkeypatch, "behind", lambda target, repo, cwd: ({"behind_by": 0}, ""))


@pytest.fixture()
def repo(tmp_path: Path) -> Path:
    path = tmp_path / "repos" / "game"
    path.mkdir(parents=True)
    run = lambda *a: subprocess.run(["git", "-C", str(path), *a], check=True, capture_output=True)  # noqa: E731
    run("init", "-b", "main")
    run("-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", "init")
    return path


@pytest.fixture()
def workspace(tmp_path: Path) -> Path:
    (tmp_path / ".gdstudio-workspace").write_text("")
    return tmp_path
