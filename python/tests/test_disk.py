"""The disk guard (gds_tools.disk, docs/studio/workspace.md#disk): its thresholds, the refusal under the hard limit,
and what
it never deletes. Nothing here measures or cleans the real disk: free space, processes and GitHub are stand-ins."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

import pytest

from gds_tools import cli, disk, issues, sweep, workspace
from gds_tools.worktrees import WorktreeError

pytestmark = pytest.mark.usefixtures("no_real_services")

GB = disk.GB
KIT = Path(__file__).resolve().parents[2]
LIMITS = disk.Limits(soft_gb=40, hard_gb=10, worktree_budget_gb=1e-7, scratch_budget_gb=1.0)
OLD = time.time() - 20 * 3600  # untouched for twenty hours: past the 12-hour hold


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


def finished(ws: Path, folder: Path, *, branch_pulls=merged, work_state=lambda r, n: "MERGED", running=()):
    note = (folder / disk.NOTE).read_text() if (folder / disk.NOTE).exists() else ""
    return disk.topic_finished(
        ws,
        disk.Topic(folder, "deadnight", note),
        LIMITS,
        work_state=work_state,
        branch_pulls=branch_pulls,
        running=list(running),
        now=time.time(),
    )


def test_a_topic_past_its_pull_request_loses_its_downloads_and_keeps_its_notes(ws):
    folder = topic(ws, "web-night-load")
    freed = disk.clear_scratch(
        ws, LIMITS, apply=True, work_state=lambda r, n: "MERGED", branch_pulls=merged, running=[], now=time.time()
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

    assert finished(ws, folder, work_state=state, branch_pulls=lambda r, b: [])[0] is True
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
    done, reason = finished(ws, folder, branch_pulls=pulls, work_state=state, running=running)
    assert done is False and why in reason
    disk.clear_scratch(ws, LIMITS, apply=True, work_state=state, branch_pulls=pulls, running=running, now=time.time())
    assert (folder / "web.zip").exists() and (folder / "artifacts").exists()


# --- topics that name no pull request --------------------------------------------------------------------------------


DAY = 86400.0


def no_pulls(repo: str, branch: str) -> list[str]:
    return []


def clear_unknown(ws: Path, *, pulls=no_pulls, limits: disk.Limits = LIMITS, apply: bool = True):
    return disk.clear_scratch(
        ws, limits, apply=apply, work_state=lambda r, n: "MERGED", branch_pulls=pulls, running=[], now=time.time()
    )


def test_a_topic_that_names_no_pull_request_loses_its_downloads_after_three_days(ws):
    folder = topic(ws, "grenade-feel")
    age(folder, time.time() - 4 * DAY)
    (folder / "clip" / "frame_00013.png").write_bytes(b"g" * 100)  # inside the folder: older than the limit as well
    age(folder, time.time() - 4 * DAY)
    freed = clear_unknown(ws)
    assert [f.path for f in freed] == ["scratch/deadnight/grenade-feel"]
    assert "no pull request named, idle 4.0 days" in freed[0].why
    for gone in ("artifacts", "clip/frame_00012.png", "night.avi", "web.zip"):
        assert not (folder / gone).exists()
    assert (folder / "REPORT.md").exists() and (folder / "after.png").exists()  # notes and plain files stay
    assert (folder / "kept" / "notes" / "big.zip").exists()


def test_a_topic_that_names_no_pull_request_is_held_for_three_days(ws):
    folder = topic(ws, "audio-levels")
    age(folder, time.time() - 2 * DAY)
    done, reason = finished(ws, folder, branch_pulls=no_pulls)
    assert done is False and "2.0 days ago (held 3 days" in reason
    assert clear_unknown(ws) == []
    assert (folder / "web.zip").exists()
    age(folder, time.time() - 3.1 * DAY)
    assert finished(ws, folder, branch_pulls=no_pulls)[0] is True


def test_the_unknown_topic_hold_comes_from_the_limits_and_zero_keeps_them_for_ever(ws):
    folder = topic(ws, "old-probe")
    age(folder, time.time() - 30 * DAY)
    assert clear_unknown(ws, limits=disk.Limits(unknown_topic_days=0)) == []
    assert (folder / "web.zip").exists()
    assert clear_unknown(ws, limits=disk.Limits(unknown_topic_days=60)) == []
    assert clear_unknown(ws, limits=disk.Limits(unknown_topic_days=29))[0].bytes > 0
    assert disk.Limits().unknown_topic_days == 3


@pytest.mark.parametrize(
    ("setup", "why"),
    [
        ("open", "open pull request"),
        ("unreadable", "could not be read"),
        ("keep", "protected by .keep"),
        ("worktree", "its worktree still exists"),
        ("process", "a process uses it"),
        ("note-open", "open or unknown"),
    ],
)
def test_an_old_topic_is_still_kept_while_its_pull_request_may_be_open(ws, setup, why):
    folder = topic(ws, "probe", "PR: Ryubara/deadnight#1\n" if setup == "note-open" else "")
    age(folder, time.time() - 30 * DAY)
    pulls, state, running = no_pulls, (lambda r, n: "MERGED"), []
    if setup == "open":
        pulls = lambda r, b: ["OPEN"]  # noqa: E731
    elif setup == "unreadable":
        pulls = lambda r, b: ["UNKNOWN"]  # noqa: E731
    elif setup == "keep":
        (folder / ".keep").write_text("")
        age(folder, time.time() - 30 * DAY)
    elif setup == "worktree":
        (ws / "worktrees" / "deadnight" / "probe").mkdir(parents=True)
    elif setup == "process":
        running = [(7, f"python soak.py --out {folder.as_posix()}/artifacts", "")]
    elif setup == "note-open":
        state = lambda r, n: "OPEN"  # noqa: E731
    done, reason = finished(ws, folder, branch_pulls=pulls, work_state=state, running=running)
    assert done is False and why in reason
    disk.clear_scratch(ws, LIMITS, apply=True, work_state=state, branch_pulls=pulls, running=running, now=time.time())
    assert (folder / "web.zip").exists() and (folder / "artifacts").exists()


def test_a_dry_run_names_the_unknown_topics_and_deletes_nothing(ws):
    folder = topic(ws, "grenade-feel")
    age(folder, time.time() - 5 * DAY)
    freed = clear_unknown(ws, apply=False)
    assert freed and freed[0].bytes == 2 + 300 + 700 + 500
    assert (folder / "web.zip").exists() and (folder / "artifacts").exists()
    report = disk.Report(1, 1, "ok", LIMITS, freed=freed, dry_run=True)
    assert any(line.startswith("would free") and "scratch/deadnight/grenade-feel" in line for line in report.lines())


def test_a_branch_whose_pull_requests_could_not_be_read_is_unknown_not_absent(ws):
    def broken(args):
        raise issues.IssueError("gh is down")

    (ws / "repos" / "deadnight" / ".git").mkdir(parents=True)
    pulls = disk.Pulls(ws, broken)
    monkey = pytest.MonkeyPatch()
    monkey.setattr(sweep, "remote_slug", lambda checkout: "Ryubara/deadnight")
    try:
        assert pulls.branch("deadnight", "grenade-feel") == ["UNKNOWN"]
    finally:
        monkey.undo()
    assert disk.Pulls(ws, broken).branch("misc", "anything") == []  # a group that is no repository has no pull requests


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


# --- what must stay: every case runs the whole guard and compares every byte of the topic ----------------------------


KIT_SLUG = "Ryubara/gdstudio"
GAME_SLUG = "Ryubara/deadnight"


class Github:
    """`gh` as the real one answers, from tables a test fills in; every call is recorded. `pr view` of an issue's
    number fails as the real one does (`Could not resolve to a PullRequest`), and an unknown command is a test failure,
    so the guard cannot pass on a call the real `gh` would refuse."""

    def __init__(self) -> None:
        self.issues: dict[str, dict[int, tuple[str, str]]] = {GAME_SLUG: {}, KIT_SLUG: {}}
        self.pulls: dict[str, dict[int, tuple[str, str, str]]] = {GAME_SLUG: {}, KIT_SLUG: {}}
        self.calls: list[list[str]] = []
        self.down = False

    def issue(self, number: int, state: str = "OPEN", *, slug: str = GAME_SLUG, body: str = "") -> None:
        self.issues[slug][number] = (state, body)

    def pull(self, number: int, state: str = "MERGED", *, slug: str = GAME_SLUG, branch: str = "", body: str = ""):
        self.pulls[slug][number] = (state, branch or f"branch-{number}", body)

    def __call__(self, args: list[str]) -> str:
        self.calls.append(args)
        if self.down:
            raise issues.IssueError("gh could not run: offline")
        kind, verb = args[:2]
        slug = args[args.index("--repo") + 1]
        if verb == "view":
            number = int(args[2])
            table = self.pulls[slug] if kind == "pr" else {**self.pulls[slug], **self.issues[slug]}
            if number not in table:
                raise issues.IssueError(f"GraphQL: Could not resolve to a PullRequest with the number of {number}")
            return json.dumps({"state": table[number][0]})
        assert verb == "list", args
        wanted = args[args.index("--state") + 1]
        fields = args[args.index("--json") + 1].split(",")
        rows = []
        if kind == "pr":
            for number, (state, branch, body) in self.pulls[slug].items():
                rows.append({"number": number, "state": state, "headRefName": branch, "headRefOid": "", "body": body})
        else:
            assert kind == "issue", args
            for number, (state, body) in self.issues[slug].items():
                rows.append({"number": number, "state": state, "body": body})
        rows = [r for r in rows if wanted == "all" or r["state"].lower() == wanted]
        return json.dumps([{key: row[key] for key in fields} for row in rows])


@pytest.fixture(scope="session")
def checkout_seed(tmp_path_factory: pytest.TempPathFactory):
    """`seed(slug)`: a real git checkout whose origin is that repository, made once a session per slug (two git
    processes) and copied by `checkout`."""
    seeds: dict[str, Path] = {}

    def seed(slug: str) -> Path:
        if slug not in seeds:
            path = tmp_path_factory.mktemp("checkout") / "repo"
            subprocess.run(["git", "init", "-q", str(path)], check=True)
            url = f"https://github.com/{slug}.git"
            subprocess.run(["git", "-C", str(path), "remote", "add", "origin", url], check=True)
            seeds[slug] = path
        return seeds[slug]

    return seed


def checkout(ws: Path, name: str, seed: Path) -> None:
    """A real git checkout, copied from a seed: the guard reads the repository's name from its origin, as it does at
    work."""
    shutil.copytree(seed, ws / "repos" / name)


@pytest.fixture()
def github(ws: Path, checkout_seed) -> Github:
    checkout(ws, "deadnight", checkout_seed(GAME_SLUG))
    checkout(ws, "gdstudio", checkout_seed(KIT_SLUG))
    return Github()


def capture_topic(ws: Path, name: str, note: str = "") -> Path:
    """A topic as the disk held them: one of each thing #691 freed, and one of each thing it kept."""
    folder = topic(ws, name, note)
    (folder / "take.wav").write_bytes(b"w" * 400)
    (folder / "run.log").write_bytes(b"l" * 90)
    shots = folder / "cap"
    shots.mkdir()
    for number in range(25):
        (shots / f"shot_{chr(97 + number)}.png").write_bytes(b"i" * 10)
    (folder / "clip.mp4").write_bytes(b"m" * 800)
    (folder / "lone.png").write_bytes(b"p")
    age(folder)
    return folder


def contents(folder: Path) -> dict[str, bytes]:
    return {p.relative_to(folder).as_posix(): p.read_bytes() for p in sorted(folder.rglob("*")) if p.is_file()}


def run_guard(ws: Path, github: Github, *, running=(), processes=None, limits: disk.Limits = LIMITS) -> disk.Report:
    return disk.guard(
        ws,
        limits,
        force=True,
        gh=github,
        processes=processes or (lambda: list(running)),
        free=lambda root: int(100 * GB),
        run_sweep=fake_sweep([]),
        measure_items=False,
    )


def test_a_topic_past_everything_is_cleared_by_this_harness(ws, github):
    """The other half of every hold below: the same topic, with nothing live, does lose its captures. Without this a
    hold test would pass on a harness that never deletes."""
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "free-me", "Issue: Ryubara/deadnight#5\n")
    report = run_guard(ws, github)
    assert report.freed_bytes > 0
    assert not (folder / "take.wav").exists() and not (folder / "web.zip").exists()


@pytest.mark.parametrize(
    ("note", "status", "extra"),
    [
        ("Issue: Ryubara/deadnight#7\n", "", {}),
        ("Issue: #7\n", "", {}),
        ("Issue: https://github.com/Ryubara/deadnight/issues/7\n", "", {}),
        ("PR: #7\n", "", {}),
        ("PR: Ryubara/deadnight#5, Ryubara/deadnight#7\n", "", {}),
        ("**PR:** Ryubara/deadnight#7\n", "", {}),
        ("PR: https://github.com/Ryubara/deadnight/pull/7\n", "", {}),
        ("", "# Deadnight #7: the apron lamps\n", {}),
        ("", "# Status: Ryubara/deadnight#5, PR #7\n", {}),
        ("", "line\n" * 40 + "still waiting on #7\n", {}),
        ("PR: Ryubara/deadnight#5\n", "", {"kit-pr3.md": "Adds a lesson from Deadnight #7: a Rookie bot.\n"}),
        ("PR: Ryubara/deadnight#5\n", "", {"sub/note.md": "goes on in issue 7 (#7)\n"}),
    ],
    ids=[
        "issue-line",
        "issue-bare-number",
        "issue-url",
        "pr-bare-number",
        "second-number-on-the-line",
        "bold-label",
        "pull-url",
        "status-first-line",
        "status-pr-beside-closed-issue",
        "status-deep-in-the-file",
        "rookie-parity-prose-of-another-note",
        "note-in-a-subfolder",
    ],
)
def test_a_topic_that_names_open_work_stays(ws, github, note, status, extra):
    github.issue(5, "CLOSED")
    github.pull(7, "OPEN") if "pull" in note or "PR" in note + status else github.issue(7, "OPEN")
    folder = capture_topic(ws, "live", note)
    if status:
        (folder / "STATUS.md").write_text(status, encoding="utf-8")
    for rel, text in extra.items():
        (folder / rel).parent.mkdir(exist_ok=True)
        (folder / rel).write_text(text, encoding="utf-8")
    age(folder)
    before = contents(folder)
    report = run_guard(ws, github)
    assert contents(folder) == before and report.freed == []


@pytest.mark.parametrize(
    "rel",
    [
        "LICENSE.md",
        "README.md",
        "copy/LICENSE.md",
        "copy/game/README.md",
        "copy/docs/audio.md",
        "tree/game/docs/design.md",
        "clone/docs/audio.md",
    ],
)
def test_a_copy_of_a_repository_does_not_hold_a_topic(ws, github, rel):
    """The game's `LICENSE.md` cites its tracking issue: copied with a tree, it held 127 finished topics."""
    github.issue(5, "CLOSED")
    github.issue(252, "OPEN")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    target = folder / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("Replace before release (tracking issue #252).\n", encoding="utf-8")
    (folder / "copy" / "LICENSE.md").parent.mkdir(exist_ok=True)
    (folder / "copy" / "LICENSE.md").write_text("Licence.\n", encoding="utf-8")
    (folder / "tree").mkdir(exist_ok=True)
    (folder / "tree" / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    (folder / "clone" / ".git").mkdir(parents=True)
    age(folder)
    assert run_guard(ws, github).freed_bytes > 0
    assert target.exists() and not (folder / "take.wav").exists()


def test_a_note_that_cannot_be_read_holds_the_topic(ws, github, monkeypatch):
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    (folder / "busy.md").write_text("being written\n", encoding="utf-8")
    age(folder)
    before = contents(folder)
    real = Path.read_text

    def locked(self, *args, **kwargs):
        if self.name == "busy.md":
            raise PermissionError(self)
        return real(self, *args, **kwargs)

    monkeypatch.setattr(Path, "read_text", locked)
    report = run_guard(ws, github)
    monkeypatch.undo()
    assert contents(folder) == before and report.freed == []


def test_a_bare_number_in_a_group_with_no_repository_holds_the_topic(ws, github):
    folder = ws / "scratch" / "misc" / "notes"
    folder.mkdir(parents=True)
    (folder / disk.NOTE).write_text("Issue: #7\n", encoding="utf-8")
    (folder / "web.zip").write_bytes(b"z")
    age(folder, time.time() - 30 * DAY)
    run_guard(ws, github)
    assert (folder / "web.zip").exists()


def test_open_work_that_cannot_be_read_holds_a_topic_past_its_issue(ws, github):
    """Only the list of open bodies fails: every other answer says the topic is over."""
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    before = contents(folder)

    def body_fails(args):
        if "body" in args[-1]:
            raise issues.IssueError("gh could not run: offline")
        return github(args)

    run_guard(ws, body_fails)
    assert contents(folder) == before


def test_a_number_in_a_note_that_cannot_be_read_holds_the_topic(ws, github):
    """The kit's lists fail and the game's do not: the note's prose names work of the kit, below its first lines."""
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n" + "line\n" * 10 + "see kit #558\n")
    before = contents(folder)

    def kit_fails(args):
        if KIT_SLUG in args and "number,state" in args:
            raise issues.IssueError("gh could not run: offline")
        return github(args)

    run_guard(ws, kit_fails)
    assert contents(folder) == before


def test_a_short_name_of_the_kit_counts_as_the_kit(ws, github):
    github.issue(5, "CLOSED")
    github.issue(558, "OPEN", slug=KIT_SLUG)
    github.issue(559, "CLOSED")  # the game's number 559 is closed; the note means the kit's
    github.issue(559, "OPEN", slug=KIT_SLUG)
    first = capture_topic(ws, "one", "Issue: Ryubara/deadnight#5\nkit #558 is open\n")
    second = capture_topic(ws, "two", "Issue: Ryubara/deadnight#5\nsee gdstudio#559\n")
    before = contents(first), contents(second)
    run_guard(ws, github)
    assert (contents(first), contents(second)) == before


@pytest.mark.parametrize("kind", ["issue", "pr"])
def test_a_topic_an_open_issue_or_pull_request_names_stays(ws, github, kind):
    github.issue(5, "CLOSED")
    body = "The decisions are in `scratch/deadnight/progression/decisions.md`."
    github.issue(1056, "OPEN", body=body) if kind == "issue" else github.pull(1056, "OPEN", body=body)
    folder = capture_topic(ws, "progression", "Issue: Ryubara/deadnight#5\n")
    other = capture_topic(ws, "progression-old", "Issue: Ryubara/deadnight#5\n")
    before = contents(folder)
    run_guard(ws, github)
    assert contents(folder) == before
    assert not (other / "take.wav").exists()  # a longer name that starts the same is no match


def test_a_closed_issue_does_not_finish_a_topic_whose_branch_has_an_open_pull_request(ws, github):
    github.issue(5, "CLOSED")
    github.pull(9, "OPEN", branch="live")
    folder = capture_topic(ws, "live", "Issue: Ryubara/deadnight#5\n")
    before = contents(folder)
    run_guard(ws, github)
    assert contents(folder) == before


@pytest.mark.parametrize(("hours", "stays"), [(1, True), (11.5, True), (12.5, False)])
def test_a_topic_changed_in_the_last_12_hours_stays(ws, github, hours, stays):
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "fresh", "Issue: Ryubara/deadnight#5\n")
    deep = folder / "cap" / "new.txt"
    deep.write_text("written by a run that is still going\n", encoding="utf-8")
    age(folder, time.time() - 30 * 3600)
    when = time.time() - hours * 3600
    os.utime(deep, (when, when))  # one file, deep down, is all that changed
    before = contents(folder)
    run_guard(ws, github)
    assert (contents(folder) == before) is stays


def test_the_12_hours_come_from_the_kits_hooks_toml(ws):
    assert disk.load_limits(KIT).scratch_grace_hours == 12
    assert disk.Limits().scratch_grace_hours == 12


@pytest.mark.parametrize(
    "command",
    [
        "python soak.py --out {abs}/artifacts",
        "bash -c 'tail -f {win}\\\\suites2\\\\summary.txt'",
        "python soak.py --out ../../scratch/deadnight/rookie-parity/run",
        "uv run gds bots --out rookie-parity",
        "claude --name rookie-parity --print",
        "CLAUDE --NAME ROOKIE-PARITY",
    ],
    ids=["absolute", "windows", "relative", "bare-name", "agent-name", "other-case"],
)
def test_a_topic_a_running_process_names_stays(ws, github, command):
    """`rookie-parity`: the note cited a merged pull request, the agent was running another issue."""
    github.pull(1040, "MERGED")
    folder = capture_topic(ws, "rookie-parity", "PR: Ryubara/deadnight#1040\nCan go: *.log\n")
    line = command.format(abs=folder.as_posix(), win=str(folder).replace("\\", "\\\\"))
    before = contents(folder)
    report = run_guard(ws, github, running=[(767, line, "")])
    assert contents(folder) == before and report.freed == []


def test_a_process_with_a_longer_name_holds_nothing(ws, github):
    github.pull(1040, "MERGED")
    folder = capture_topic(ws, "rookie-parity", "PR: Ryubara/deadnight#1040\n")
    run_guard(ws, github, running=[(1, "python soak.py --out rookie-parity-2", "")])
    assert not (folder / "take.wav").exists()


def test_a_process_that_started_during_the_sweep_holds_the_topic(ws, github):
    """The sweep can take 15 minutes: the list the scratch clean-up judges by must be read after it."""
    github.pull(1040, "MERGED")
    folder = capture_topic(ws, "rookie-parity", "PR: Ryubara/deadnight#1040\n")
    lists = iter([[], [(767, "uv run gds bots --out rookie-parity", "")]])
    before = contents(folder)
    run_guard(ws, github, processes=lambda: next(lists))
    assert contents(folder) == before


def test_a_process_list_that_cannot_be_read_frees_nothing(ws, github):
    github.pull(1040, "MERGED")
    folder = capture_topic(ws, "rookie-parity", "PR: Ryubara/deadnight#1040\n")
    before = contents(folder)

    def broken():
        raise WorktreeError("cannot list the running processes")

    report = run_guard(ws, github, processes=broken)
    assert contents(folder) == before and report.freed == []
    assert any("nothing freed" in note for note in report.notes)


def test_a_process_list_that_fails_after_the_sweep_frees_no_scratch(ws, github):
    github.pull(1040, "MERGED")
    folder = capture_topic(ws, "rookie-parity", "PR: Ryubara/deadnight#1040\n")
    before = contents(folder)
    answers = iter([[], None])

    def second_fails():
        answer = next(answers)
        if answer is None:
            raise WorktreeError("cannot list the running processes")
        return answer

    run_guard(ws, github, processes=second_fails)
    assert contents(folder) == before


def test_github_down_frees_nothing_from_a_topic_that_names_work(ws, github):
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "live", "Issue: Ryubara/deadnight#5\n")
    bare = capture_topic(ws, "bare")
    age(bare, time.time() - 30 * DAY)
    github.down = True
    before = contents(folder), contents(bare)
    run_guard(ws, github)
    assert (contents(folder), contents(bare)) == before


def test_a_truncated_open_issue_list_counts_as_unknown(ws, github, monkeypatch):
    """`--limit` stops `gh issue list` without an error, and the newest issues come first: an old open issue would be
    read as absent. A full page is therefore no answer."""
    monkeypatch.setattr(disk, "LIST_LIMIT", 2)
    github.issue(1, "CLOSED")
    github.issue(2, "CLOSED")
    github.issue(3, "OPEN")
    folder = capture_topic(ws, "live", "Issue: Ryubara/deadnight#1\n")
    before = contents(folder)
    run_guard(ws, github)
    assert contents(folder) == before


@pytest.mark.parametrize(
    ("rel", "note"),
    [
        ("REPORT.md", ""),
        ("deep/down/NOTES.MD", ""),
        ("artifacts/REPORT.md", ""),
        ("artifacts/run-1/deep/verdict.md", ""),
        ("logs/report.md", "Can go: logs\n"),
        ("logs/report.md", "Can go: logs/**\n"),
        ("logs/report.md", "Can go: *\n"),
        ("logs/report.md", "Can go: *.md\n"),
        ("kept/a.zip", ""),
        ("kept/take.wav", ""),
        ("kept-2/frames0001.png", ""),
        ("Kept/take.wav", ""),
        ("artifacts/kept/take.wav", ""),
        ("artifacts/run-1/kept-3/a.zip", ""),
        ("deep/kept/run.log", ""),
        ("logs/kept/run.log", "Can go: logs\n"),
        ("logs/kept/run.log", "Can go: *\n"),
        ("deep/guarded/.keep", ""),
        ("deep/guarded/take.wav", ""),
        ("artifacts/guarded/.keep", ""),
        ("artifacts/guarded/a.zip", ""),
    ],
)
def test_notes_kept_folders_and_keep_markers_outlive_every_rule(ws, github, rel, note):
    """The list is the whole of what a `.md` or a `kept/` can sit under: a download folder deleted whole, a `Can go:`
    folder, a wildcard. `guarded/` gets a `.keep` beside the file in the last four cases."""
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "finished", f"Issue: Ryubara/deadnight#5\n{note}")
    target = folder / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(b"must stay")
    if "guarded" in rel and target.name != ".keep":
        (target.parent / ".keep").write_text("")
    age(folder)
    report = run_guard(ws, github)
    assert report.freed_bytes > 0  # the clean-up did run
    assert target.read_bytes() == b"must stay"
    assert (folder / disk.NOTE).exists() and (folder / "REPORT.md").exists()


@pytest.mark.skipif(os.name != "nt", reason="a junction is a Windows folder link")
def test_a_junction_in_a_download_folder_is_not_followed(ws, github):
    github.issue(5, "CLOSED")
    outside = ws / "outside"
    outside.mkdir()
    (outside / "game.wav").write_bytes(b"not scratch")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    done = subprocess.run(
        ["cmd", "/c", "mklink", "/J", str(folder / "artifacts" / "link"), str(outside)], capture_output=True
    )
    assert done.returncode == 0, done
    age(folder)
    run_guard(ws, github)
    assert (outside / "game.wav").read_bytes() == b"not scratch"


@pytest.mark.skipif(os.name != "nt", reason="a junction is a Windows folder link")
def test_a_junction_in_a_plain_folder_is_not_walked_into(ws, github):
    """Here nothing deletes the folder whole: only the walk could leave the topic through the link."""
    github.issue(5, "CLOSED")
    outside = ws / "outside"
    outside.mkdir()
    (outside / "game.wav").write_bytes(b"not scratch")
    (outside / "notes.txt").write_text("issue #7\n", encoding="utf-8")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    (folder / "plain").mkdir()
    done = subprocess.run(
        ["cmd", "/c", "mklink", "/J", str(folder / "plain" / "link"), str(outside)], capture_output=True
    )
    assert done.returncode == 0, done
    age(folder)
    run_guard(ws, github)
    assert (outside / "game.wav").read_bytes() == b"not scratch"


def test_a_folder_that_cannot_be_read_counts_as_changed_now(ws, monkeypatch):
    folder = ws / "scratch" / "deadnight" / "t"
    folder.mkdir(parents=True)
    age(folder)
    real = os.scandir

    def refused(path):
        raise PermissionError(path)

    monkeypatch.setattr(os, "scandir", refused)
    assert disk.newest_change(folder) > time.time() - 5
    monkeypatch.setattr(os, "scandir", real)


# --- the fakes are what is called ------------------------------------------------------------------------------------


def test_the_tripwire_stops_the_real_gh_and_the_real_process_list(ws, monkeypatch):
    """`issues.run_gh` and `sweep.list_processes` are the default arguments of `disk.guard`; both end in the tripwire,
    so a test that left a fake out would fail here, not reach the account."""
    with pytest.raises(AssertionError, match="real `gh`"):
        issues.run_gh(["auth", "status"])
    if os.name == "nt":
        with pytest.raises(AssertionError, match="real `powershell`"):
            sweep.list_processes()
    (ws / "scratch" / "deadnight" / "t").mkdir(parents=True)
    (ws / "scratch" / "deadnight" / "t" / disk.NOTE).write_text("Issue: Ryubara/deadnight#5\n")
    age(ws / "scratch")
    with pytest.raises(AssertionError, match="real `gh`"):
        disk.guard(
            ws,
            LIMITS,
            force=True,
            processes=lambda: [],
            free=lambda r: GB,
            run_sweep=fake_sweep([]),
            measure_items=False,
        )


def test_the_guard_decides_from_the_fake_it_is_given(ws, github):
    """One answer of the fake flips the outcome, and the calls are the ones the real `gh` answers."""
    github.issue(5, "OPEN")
    folder = capture_topic(ws, "flip", "Issue: Ryubara/deadnight#5\n")
    before = contents(folder)
    run_guard(ws, github)
    assert contents(folder) == before
    assert any(c[:2] == ["issue", "list"] and GAME_SLUG in c for c in github.calls)
    github.calls.clear()
    github.issue(5, "CLOSED")
    assert run_guard(ws, github).freed_bytes > 0
    assert not (folder / "take.wav").exists()
    assert github.calls and not [c for c in github.calls if c[1] != "list"]  # nothing but reads, nothing per topic


def test_the_process_list_given_is_the_one_read(ws, github):
    asked = []

    def listing():
        asked.append(1)
        return []

    run_guard(ws, github, processes=listing)
    assert len(asked) == 2  # before the sweep, and again before the scratch clean-up


def test_the_fake_refuses_pr_view_of_an_issue_as_the_real_gh_does(github):
    github.issue(5, "CLOSED")
    with pytest.raises(issues.IssueError, match="Could not resolve"):
        github(["pr", "view", "5", "--repo", GAME_SLUG, "--json", "state"])


# --- what goes ---------------------------------------------------------------------------------------------------


def test_a_topic_with_only_its_age_to_go_by_loses_only_the_old_list(ws, github):
    """#691 held these as "cannot tell": the age of a folder is no evidence about its logs, takes and screenshots."""
    folder = capture_topic(ws, "cannot-tell")
    age(folder, time.time() - 30 * DAY)
    report = run_guard(ws, github)
    assert report.freed and disk.BY_THE_CLOCK in report.freed[0].why
    assert not (folder / "web.zip").exists() and not (folder / "night.avi").exists()
    assert (folder / "take.wav").exists() and (folder / "run.log").exists()
    assert len(list((folder / "cap").iterdir())) == 25


@pytest.mark.parametrize(
    "name",
    [
        ("note", "Issue: Ryubara/deadnight#5\n", ""),
        ("note", "Issue: #5\n", ""),
        ("note", "- **Issue:** Ryubara/deadnight#5\n", ""),
        ("status", "", "# Deadnight #5: the apron lamps\n"),
        ("status", "", "# #5 arm length: the player arms\n"),
        ("status", "", "# audio-levels (Ryubara/deadnight#5)\n"),
        ("status", "", "\n\nPR #6 merged, issue #5 closed\n"),
    ],
    ids=["line", "bare", "bold", "heading", "number-first", "bracket", "third-line"],
)
def test_a_topic_past_its_issue_loses_its_captures_and_keeps_the_rest(ws, github, name):
    _, note, status = name
    github.issue(5, "CLOSED")
    github.pull(6, "MERGED")
    folder = capture_topic(ws, "audio-levels", note)
    if status:
        (folder / "STATUS.md").write_text(status, encoding="utf-8")
    keep = {"clip.mp4", "lone.png", "after.png", "REPORT.md", "kept/notes/big.zip"}
    age(folder)
    report = run_guard(ws, github)
    assert report.freed and "#5 finished" in report.freed[0].why
    left = set(contents(folder))
    assert keep <= left
    assert not {"take.wav", "run.log", "web.zip", "night.avi", "clip/frame_00012.png"} & left
    assert not [p for p in left if p.startswith("cap/")]  # 25 unnumbered shots: a frame folder


def test_a_topic_with_no_note_of_its_issue_is_still_judged_by_its_branch(ws, github):
    github.pull(4, "MERGED", branch="old-branch")
    folder = capture_topic(ws, "old-branch")
    assert "branch" in run_guard(ws, github).freed[0].why
    assert not (folder / "take.wav").exists()


def test_a_named_number_that_does_not_exist_is_no_reason_to_delete(ws, github):
    folder = capture_topic(ws, "typo", "Issue: Ryubara/deadnight#99999\n")
    before = contents(folder)
    run_guard(ws, github)
    assert contents(folder) == before


def test_numbers_in_prose_that_are_nothing_hold_nothing(ws, github):
    github.issue(5, "CLOSED")
    note = "Issue: Ryubara/deadnight#5\nThe colour #123456 and godotengine/godot#100 stay open upstream.\n"
    folder = capture_topic(ws, "prose", note)
    run_guard(ws, github)
    assert not (folder / "take.wav").exists()


@pytest.mark.parametrize(
    ("rel", "stays"),
    [
        ("sheets8/flare_00.png", True),
        ("pr/img/after.png", True),
        ("attach/after.png", True),
        ("source/take.wav", True),
        ("source/deep/web.zip", True),
        ("ref/room.wav", True),
        ("cap/contact_sheet.png", True),
        ("cap/before_after.png", True),
        ("cap/compare_a.png", True),
        ("cap/frame_sheet_0001.png", True),
        ("cap/out.mp4", True),
        ("cap/shot_z.png", False),
        ("cap/one.jpg", False),
        ("cap/tour00000001.png", False),
        ("few/tour00000001.png", False),
        ("few/f0001.jpg", False),
        ("web/index.pck", False),
        ("web/index.side.wasm", False),
        ("web/index.html", False),
        ("web/index.js", False),
        ("out/run.err", False),
        ("out/run.out", False),
        ("out/capture.mkv", False),
        ("out/archive.tar.gz", False),
    ],
)
def test_what_goes_and_what_stays_in_a_finished_topic(ws, github, rel, stays):
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    target = folder / rel
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(b"x")
    if rel.startswith("web/"):
        (folder / "web" / "index.wasm").write_bytes(b"w")
    age(folder)
    run_guard(ws, github)
    assert target.exists() is stays


def test_nineteen_screenshots_in_a_folder_are_screenshots_and_twenty_are_frames(ws, github):
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    for name, count in (("nineteen", 19), ("twenty", 20)):
        (folder / name).mkdir()
        for number in range(count):
            (folder / name / f"view_{chr(97 + number)}.png").write_bytes(b"i")
    age(folder)
    run_guard(ws, github)
    assert len(list((folder / "nineteen").iterdir())) == 19
    assert list((folder / "twenty").iterdir()) == []


def test_html_beside_no_wasm_is_a_report_and_stays(ws, github):
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    (folder / "report").mkdir()
    (folder / "report" / "index.html").write_text("<p>12 ms</p>")
    age(folder)
    run_guard(ws, github)
    assert (folder / "report" / "index.html").exists()


def test_the_wavs_of_a_voice_topic_stay(ws, github):
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "audio-add-the-voice-lines", "Issue: Ryubara/deadnight#5\n")
    run_guard(ws, github)
    assert (folder / "take.wav").exists() and not (folder / "run.log").exists()


def test_a_checkout_inside_a_topic_is_left_alone(ws, github):
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    baseline = folder / "baseline"
    (baseline / "game").mkdir(parents=True)
    (baseline / ".git").write_text("gitdir: elsewhere\n")
    (baseline / "game" / "art.zip").write_bytes(b"z")
    age(folder)
    run_guard(ws, github)
    assert (baseline / "game" / "art.zip").exists()


def test_can_go_globs_lose_their_backticks_and_prose_is_not_a_glob(ws, github):
    github.issue(5, "CLOSED")
    note = "Issue: Ryubara/deadnight#5\nCan go: `extra/*.dat`\nCan go: frames once the clip is made\n"
    folder = capture_topic(ws, "finished", note)
    (folder / "extra").mkdir()
    (folder / "extra" / "a.dat").write_bytes(b"d")
    (folder / "frames").mkdir()
    (folder / "frames" / "a.dat").write_bytes(b"d")
    age(folder)
    run_guard(ws, github)
    assert not (folder / "extra" / "a.dat").exists()
    assert (folder / "frames" / "a.dat").exists()


def test_a_dry_run_of_the_new_rules_deletes_nothing(ws, github):
    github.issue(5, "CLOSED")
    folder = capture_topic(ws, "finished", "Issue: Ryubara/deadnight#5\n")
    before = contents(folder)
    report = disk.guard(
        ws,
        LIMITS,
        apply=False,
        force=True,
        gh=github,
        processes=lambda: [],
        free=lambda root: int(100 * GB),
        run_sweep=fake_sweep([]),
        measure_items=False,
    )
    assert report.freed_bytes > 0 and contents(folder) == before
