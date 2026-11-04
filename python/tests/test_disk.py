"""The disk guard (gds_tools.disk, docs/workspace.md#disk): its thresholds, the refusal under the hard limit, and what
it never deletes. Nothing here measures or cleans the real disk: free space, processes and GitHub are stand-ins."""

from __future__ import annotations

import json
import os
import time
from pathlib import Path

import pytest

from gds_tools import cli, disk, issues, sweep, workspace

GB = disk.GB
KIT = Path(__file__).resolve().parents[2]
LIMITS = disk.Limits(soft_gb=40, hard_gb=10, worktree_budget_gb=1e-7, scratch_budget_gb=1.0)
OLD = time.time() - 10 * 3600  # untouched for ten hours


def age(path: Path, when: float = OLD) -> None:
    """Set the change time of a folder and everything in it."""
    for folder, dirs, files in os.walk(path):
        for name in [*dirs, *files]:
            os.utime(Path(folder) / name, (when, when))
    os.utime(path, (when, when))


@pytest.fixture()
def ws(tmp_path: Path) -> Path:
    (tmp_path / ".gdstudio-workspace").write_text("")
    return tmp_path


def worktree(ws: Path, name: str, *, imported: bool = True) -> Path:
    tree = ws / "worktrees" / "deadnight" / name
    (tree / "game").mkdir(parents=True)
    (tree / "game" / "main.gd").write_text("extends Node\n")
    if imported:
        cache = tree / "game" / ".godot" / "imported"
        cache.mkdir(parents=True)
        (cache / "wall.ctex").write_bytes(b"x" * 1000)
    return tree


def topic(ws: Path, name: str, note: str = "") -> Path:
    folder = ws / "scratch" / "deadnight" / name
    (folder / "artifacts" / "run-1").mkdir(parents=True)
    (folder / "artifacts" / "run-1" / "result.json").write_text("{}")
    (folder / "web.zip").write_bytes(b"z" * 500)
    (folder / "night.avi").write_bytes(b"a" * 700)
    (folder / "REPORT.md").write_text("numbers: 12 ms\n")
    (folder / "after.png").write_bytes(b"p")
    (folder / "clip").mkdir()
    (folder / "clip" / "frame_00012.png").write_bytes(b"f" * 300)
    (folder / "kept" / "notes").mkdir(parents=True)
    (folder / "kept" / "notes" / "big.zip").write_bytes(b"k")
    if note:
        (folder / disk.NOTE).write_text(note)
    age(folder)
    return folder


def by_activity(tree: Path) -> float:
    return disk.newest_change(tree)


# --- thresholds ------------------------------------------------------------------------------------------------------


def test_levels_at_the_thresholds():
    assert disk.level(int(40 * GB), LIMITS) == "ok"
    assert disk.level(int(40 * GB) - 1, LIMITS) == "soft"
    assert disk.level(int(10 * GB), LIMITS) == "soft"
    assert disk.level(int(10 * GB) - 1, LIMITS) == "hard"


def test_the_limits_come_from_the_kits_hooks_toml():
    limits = disk.load_limits(KIT)
    assert (limits.soft_gb, limits.hard_gb) == (40, 10)
    assert disk.load_limits(None) == disk.Limits()  # no kit: the defaults


# --- the refusal -----------------------------------------------------------------------------------------------------


def test_no_refusal_above_the_hard_limit(ws):
    assert disk.refusal(ws, LIMITS, "x", free=int(11 * GB)) is None
    assert disk.refusal(ws, LIMITS, "x", free=int(20 * GB)) is None  # soft: still starts


def test_the_refusal_names_the_free_space_and_the_biggest_folders(ws):
    (ws / "cache").mkdir()
    (ws / disk.STATUS).write_text(json.dumps({"biggest": [{"path": "scratch/deadnight/web-night-load", "gb": 6.1}]}))
    text = disk.refusal(ws, LIMITS, "starting o/r#1", free=int(2 * GB))
    assert text.startswith("starting o/r#1 refused: the disk has 2.0 GB free, under the hard limit of 10 GB")
    assert "scratch/deadnight/web-night-load 6.1 GB" in text


def test_gds_issue_start_is_refused_under_the_hard_limit(ws, monkeypatch, capsys):
    monkeypatch.setattr(workspace, "require_workspace", lambda start=None: ws)
    monkeypatch.setattr(workspace, "kit_checkout", lambda: KIT)
    monkeypatch.setattr(disk, "free_bytes", lambda root: int(3 * GB))

    def never(*args, **kwargs):
        raise AssertionError("the issue was started")

    monkeypatch.setattr(issues, "start", never)
    assert cli.main(["issue", "start", "Ryubara/deadnight#7", "--agent", "godot-engineer"]) == 2
    err = capsys.readouterr().err
    assert "starting Ryubara/deadnight#7 refused" in err and "3.0 GB free" in err
    assert not (ws / "worktrees").exists()  # no worktree made


# --- import caches ---------------------------------------------------------------------------------------------------


def test_the_import_cache_of_an_idle_worktree_is_cleared_and_its_files_stay(ws):
    tree = worktree(ws, "done")
    age(tree)
    freed = disk.clear_imports(ws, LIMITS, apply=True, running=[], now=time.time(), activity=by_activity)
    assert [f.path for f in freed] == ["worktrees/deadnight/done/game/.godot/imported"]
    assert freed[0].bytes == 1000
    assert not (tree / "game" / ".godot" / "imported").exists()
    assert (tree / "game" / "main.gd").exists()


def test_a_recently_touched_worktree_keeps_its_import_cache(ws):
    tree = worktree(ws, "busy")  # just made: touched now
    assert disk.clear_imports(ws, LIMITS, apply=True, running=[], now=time.time(), activity=by_activity) == []
    assert (tree / "game" / ".godot" / "imported" / "wall.ctex").exists()


def test_a_worktree_a_process_uses_keeps_its_import_cache(ws):
    tree = worktree(ws, "running")
    age(tree)
    godot = [(42, f"godot --path {tree.as_posix()}/game --headless", "")]
    assert disk.clear_imports(ws, LIMITS, apply=True, running=godot, now=time.time(), activity=by_activity) == []
    assert (tree / "game" / ".godot" / "imported").exists()


def test_a_dry_run_and_a_keep_marker_delete_nothing(ws):
    tree = worktree(ws, "kept")
    (tree / ".keep").write_text("")
    other = worktree(ws, "dry")
    age(tree)
    age(other)
    freed = disk.clear_imports(ws, LIMITS, apply=False, running=[], now=time.time(), activity=by_activity)
    assert [f.path for f in freed] == ["worktrees/deadnight/dry/game/.godot/imported"]
    assert (other / "game" / ".godot" / "imported").exists() and (tree / "game" / ".godot" / "imported").exists()


def test_main_checkouts_are_never_touched(ws):
    main = ws / "repos" / "deadnight" / "game" / ".godot" / "imported"
    main.mkdir(parents=True)
    age(ws / "repos")
    assert disk.clear_imports(ws, LIMITS, apply=True, running=[], now=time.time(), activity=by_activity) == []
    assert main.exists()


# --- scratch downloads -----------------------------------------------------------------------------------------------


def merged(repo: str, branch: str) -> list[str]:
    return ["MERGED"]


def finished(ws: Path, folder: Path, *, branch_pulls=merged, pr_state=lambda r, n: "MERGED", running=()):
    note = (folder / disk.NOTE).read_text() if (folder / disk.NOTE).exists() else ""
    return disk.topic_finished(
        ws,
        disk.Topic(folder, "deadnight", note),
        LIMITS,
        pr_state=pr_state,
        branch_pulls=branch_pulls,
        running=list(running),
        now=time.time(),
    )


def test_a_topic_past_its_pull_request_loses_its_downloads_and_keeps_its_notes(ws):
    folder = topic(ws, "web-night-load")
    freed = disk.clear_scratch(
        ws, LIMITS, apply=True, pr_state=lambda r, n: "MERGED", branch_pulls=merged, running=[], now=time.time()
    )
    assert [(f.path, f.bytes) for f in freed] == [("scratch/deadnight/web-night-load", 2 + 300 + 700 + 500)]
    assert freed[0].why.startswith("4 scratch download(s)")
    for gone in ("artifacts", "clip/frame_00012.png", "night.avi", "web.zip"):
        assert not (folder / gone).exists()
    assert (folder / "REPORT.md").exists() and (folder / "after.png").exists()
    assert (folder / "kept" / "notes" / "big.zip").exists()  # the sweep's kept files are never deleted


def test_a_scratch_note_names_the_pull_request_and_what_else_can_go(ws):
    folder = topic(ws, "night-load-gate", "PR: Ryubara/deadnight#950\nCan go: *.png\n")
    asked = []

    def state(repo, number):
        asked.append((repo, number))
        return "CLOSED"

    assert finished(ws, folder, pr_state=state, branch_pulls=lambda r, b: [])[0] is True
    assert asked == [("Ryubara/deadnight", 950)]
    note = (folder / disk.NOTE).read_text()
    names = [p.name for p in disk.downloads_in(disk.Topic(folder, "deadnight", note), LIMITS)]
    assert sorted(names) == ["after.png", "artifacts", "frame_00012.png", "night.avi", "web.zip"]


@pytest.mark.parametrize(
    ("setup", "why"),
    [
        ("open", "open pull request"),
        ("unknown", "no pull request is known"),
        ("note-open", "open or unknown"),
        ("worktree", "its worktree still exists"),
        ("keep", "protected by .keep"),
        ("process", "a process uses it"),
        ("recent", "grace"),
    ],
)
def test_a_topic_that_may_still_be_in_use_is_never_cleared(ws, setup, why):
    folder = topic(ws, "probe", "PR: Ryubara/deadnight#1\n" if setup == "note-open" else "")
    pulls, state, running = merged, (lambda r, n: "MERGED"), []
    if setup == "open":
        pulls = lambda r, b: ["MERGED", "OPEN"]  # noqa: E731
    elif setup == "unknown":
        pulls = lambda r, b: []  # noqa: E731
    elif setup == "note-open":
        state = lambda r, n: "OPEN"  # noqa: E731
    elif setup == "worktree":
        (ws / "worktrees" / "deadnight" / "probe").mkdir(parents=True)
    elif setup == "keep":
        (folder / ".keep").write_text("")
    elif setup == "process":
        running = [(7, f"python soak.py --out {folder.as_posix()}/artifacts", "")]
    elif setup == "recent":
        (folder / "artifacts" / "run-2.json").write_text("{}")  # written just now
    done, reason = finished(ws, folder, branch_pulls=pulls, pr_state=state, running=running)
    assert done is False and why in reason
    disk.clear_scratch(ws, LIMITS, apply=True, pr_state=state, branch_pulls=pulls, running=running, now=time.time())
    assert (folder / "web.zip").exists() and (folder / "artifacts").exists()


# --- the guard -------------------------------------------------------------------------------------------------------


def fake_sweep(calls):
    def run(root, apply, idle_hours):
        calls.append((apply, idle_hours))
        return sweep.Report()

    return run


def guard(ws, free_gb, calls, **kwargs):
    return disk.guard(
        ws,
        LIMITS,
        gh=lambda args: "[]",
        processes=lambda: [],
        free=lambda root: int(free_gb * GB),
        run_sweep=fake_sweep(calls),
        **kwargs,
    )


def test_above_the_soft_limit_the_guard_only_measures(ws):
    tree = worktree(ws, "done")
    age(tree)
    calls = []
    report = guard(ws, 100, calls)
    assert calls == [] and report.freed == [] and report.level == "ok"
    assert (tree / "game" / ".godot" / "imported").exists()
    status = json.loads((ws / disk.STATUS).read_text())
    assert status["level"] == "ok" and status["line"].startswith("disk 100.0G free | over budget: deadnight/done")
    assert status["over_budget"][0]["path"] == "worktrees/deadnight/done"


def test_below_the_soft_limit_the_guard_sweeps_and_clears(ws):
    tree = worktree(ws, "done")
    age(tree)
    calls = []
    report = guard(ws, 20, calls)
    assert calls == [(True, sweep.Settings().idle_hours)]
    assert "worktrees/deadnight/done/game/.godot/imported" in [f.path for f in report.freed]
    assert json.loads((ws / disk.STATUS).read_text())["level"] == "soft"


def test_below_the_hard_limit_the_sweep_uses_the_short_idle_time(ws):
    calls = []
    report = guard(ws, 5, calls)
    assert calls == [(True, LIMITS.imports_idle_hours)] and report.level == "hard"
    assert "HARD<10" in report.status_line()


def test_a_dry_run_guard_deletes_nothing(ws):
    tree = worktree(ws, "done")
    age(tree)
    calls = []
    report = guard(ws, 5, calls, apply=False)
    assert calls == [(False, LIMITS.imports_idle_hours)]
    assert report.freed and (tree / "game" / ".godot" / "imported").exists()


def test_a_running_sweep_is_not_waited_for(ws):
    def locked(root, apply, idle):
        raise sweep.Locked("another sweep is running")

    report = disk.guard(
        ws, LIMITS, gh=lambda a: "[]", processes=lambda: [], free=lambda r: int(5 * GB), run_sweep=locked
    )
    assert any("worktree sweep skipped" in n for n in report.notes)
