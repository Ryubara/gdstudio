"""`gds worktree sweep` (kit issue #241) on real git repositories in a temporary folder: a remote, a checkout under
repos/ and worktrees under worktrees/. Only GitHub (pull requests, issue states) and the process list are faked."""

from __future__ import annotations

import json
import os
import subprocess
import time
from pathlib import Path

import pytest

from gds_tools import issues, sweep
from gds_tools.sweep import Settings

SLUG = "acme/proj"
LONG_AGO = 100 * 3600  # added to the clock so every file is "old"


def git(cwd: Path, *args: str) -> str:
    done = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, check=True)
    return done.stdout.strip()


class FakeGh:
    """`gh pr list` and `gh issue view` from tables the test fills in."""

    def __init__(self) -> None:
        self.pulls: list[dict] = []
        self.issues: dict[int, str] = {}
        self.down = False

    def pull(self, branch: str, number: int, state: str, head: str = "") -> None:
        self.pulls.append({"number": number, "state": state, "headRefName": branch, "headRefOid": head})

    def __call__(self, args: list[str]) -> str:
        if self.down:
            raise issues.IssueError("gh could not run: offline")
        if args[:2] == ["pr", "list"]:
            return json.dumps(self.pulls)
        if args[:2] == ["issue", "view"]:
            return json.dumps({"state": self.issues[int(args[2])]})
        raise AssertionError(args)


@pytest.fixture
def world(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> dict:
    for key, value in (("NAME", "t"), ("EMAIL", "a@example.org")):
        monkeypatch.setenv(f"GIT_AUTHOR_{key}", value)
        monkeypatch.setenv(f"GIT_COMMITTER_{key}", value)
    origin, root = tmp_path / "origin.git", tmp_path / "ws"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
    seed = tmp_path / "seed"
    seed.mkdir()
    git(seed, "init", "-q", "-b", "main")
    (seed / "README.md").write_text("proj\n", encoding="utf-8")
    git(seed, "add", "-A")
    git(seed, "commit", "-q", "-m", "docs: Add a readme")
    git(seed, "remote", "add", "origin", str(origin))
    git(seed, "push", "-q", "origin", "main")
    (root / "repos").mkdir(parents=True)
    (root / "worktrees" / "proj").mkdir(parents=True)
    checkout = root / "repos" / "proj"
    subprocess.run(["git", "clone", "-q", str(origin), str(checkout)], check=True)
    # The slug is read from the configured url; fetches still go to the local remote.
    git(checkout, "config", "remote.origin.url", f"https://github.com/{SLUG}.git")
    git(checkout, "config", f"url.{origin.as_posix()}.insteadOf", f"https://github.com/{SLUG}.git")
    return {"root": root, "checkout": checkout, "gh": FakeGh(), "origin": origin}


def add_worktree(world: dict, name: str, *, branch: bool = True, commit: bool = False, push: bool = False) -> Path:
    path = world["root"] / "worktrees" / "proj" / name
    if branch:
        git(world["checkout"], "worktree", "add", "-q", "--no-track", "-b", name, str(path), "origin/main")
    else:
        git(world["checkout"], "worktree", "add", "-q", "--detach", str(path), "origin/main")
    if commit:
        (path / f"{name}.txt").write_text("work\n", encoding="utf-8")
        git(path, "add", "-A")
        git(path, "commit", "-q", "-m", "docs: Add work")
    if push:
        git(path, "push", "-q", "origin", name)
    return path


def run_sweep(world: dict, *, apply: bool = True, late: bool = True, **kwargs) -> sweep.Report:
    kwargs.setdefault("settings", Settings(grace_minutes=0))
    kwargs.setdefault("processes", lambda: [])
    clock = time.time() + (LONG_AGO if late else 0)
    return sweep.sweep(world["root"], apply=apply, gh=world["gh"], now=clock, **kwargs)


def outcome(report: sweep.Report, name: str) -> sweep.Outcome:
    return next(o for o in report.outcomes if o.entry.name == name)


def test_a_merged_branch_is_removed_with_its_local_branch(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    head = git(path, "rev-parse", "HEAD")
    git(world["checkout"], "update-ref", "-d", "refs/remotes/origin/net-lobby")  # GitHub deleted it after the merge
    git(world["origin"], "branch", "-D", "net-lobby")
    world["gh"].pull("net-lobby", 7, "MERGED", head)
    report = run_sweep(world)
    assert outcome(report, "net-lobby").action == "removed"
    assert not path.exists()
    assert "net-lobby" not in git(world["checkout"], "branch", "--list")
    assert "net-lobby" not in git(world["checkout"], "worktree", "list")


def test_a_dry_run_changes_nothing(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    (path / "art.blend").write_bytes(b"blend")
    world["gh"].pull("net-lobby", 7, "MERGED", git(path, "rev-parse", "HEAD"))
    report = run_sweep(world, apply=False)
    found = outcome(report, "net-lobby")
    assert found.action == "would-remove" and found.kept == ["art.blend"]
    assert path.is_dir() and not (world["root"] / "scratch").exists()
    assert "would be removed" in report.lines()[-1]


def test_an_open_pull_request_is_left(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    world["gh"].pull("net-lobby", 7, "OPEN", git(path, "rev-parse", "HEAD"))
    found = outcome(run_sweep(world), "net-lobby")
    assert found.action == "left" and "#7 is open" in found.reason
    assert path.is_dir()


def test_a_reopened_branch_with_an_open_pull_request_wins_over_an_old_merged_one(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    world["gh"].pull("net-lobby", 3, "MERGED", "0" * 40)
    world["gh"].pull("net-lobby", 9, "OPEN", git(path, "rev-parse", "HEAD"))
    assert outcome(run_sweep(world), "net-lobby").action == "left"


def test_commits_on_no_remote_branch_keep_the_worktree(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    pushed = git(path, "rev-parse", "HEAD")
    (path / "more.txt").write_text("not pushed\n", encoding="utf-8")
    git(path, "add", "-A")
    git(path, "commit", "-q", "-m", "docs: Add more")
    git(world["checkout"], "update-ref", "-d", "refs/remotes/origin/net-lobby")
    git(world["origin"], "branch", "-D", "net-lobby")
    world["gh"].pull("net-lobby", 7, "MERGED", pushed)
    found = outcome(run_sweep(world), "net-lobby")
    assert found.action == "refused" and "1 commit(s) are on no remote branch" in found.reason
    assert path.is_dir() and (path / "more.txt").is_file()


def test_pushed_commits_of_a_branch_without_a_pull_request_do_not_stop_the_sweep(world):
    path = add_worktree(world, "probe", commit=True, push=True)
    found = outcome(run_sweep(world), "probe")  # nothing claims it and it has been idle: finished, and safe
    assert found.action == "removed" and "no pull request yet" in found.reason
    assert not path.exists()


def test_a_process_using_the_worktree_keeps_it(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    other = add_worktree(world, "net-lobby-before", commit=True, push=True)
    world["gh"].pull("net-lobby", 7, "MERGED", git(path, "rev-parse", "HEAD"))
    world["gh"].pull("net-lobby-before", 8, "MERGED", git(other, "rev-parse", "HEAD"))
    command = f'godot --headless --path "{path.as_posix()}/game" -s probe.gd'
    report = run_sweep(world, processes=lambda: [(4242, command, "")])
    used = outcome(report, "net-lobby")
    assert used.action == "refused" and "process 4242" in used.reason
    assert path.is_dir()
    assert outcome(report, "net-lobby-before").action == "removed"  # a longer name that starts the same is no match


def test_a_process_with_the_worktree_as_its_working_directory_keeps_it(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    world["gh"].pull("net-lobby", 7, "MERGED", git(path, "rev-parse", "HEAD"))
    inner = path / "game"
    inner.mkdir()
    report = run_sweep(world, processes=lambda: [(77, "claude", str(inner))])
    assert outcome(report, "net-lobby").action == "refused"


def test_users_of_matches_git_bash_and_windows_spellings(tmp_path):
    folder = tmp_path / "hud"
    folder.mkdir()
    text = str(folder.resolve())
    spellings = [text, text.replace("\\", "/"), text.replace("\\", "\\\\")]
    if len(text) > 1 and text[1] == ":":
        spellings.append("/" + text[0].lower() + text[2:].replace("\\", "/"))
    for spelling in spellings:
        assert sweep.users_of(folder, [(1, f"tool {spelling} --x", "")]), spelling
    assert not sweep.users_of(folder, [(1, f"tool {text}-before --x", "")])


def test_a_detached_worktree_is_removed_when_idle_and_left_when_touched(world):
    old = add_worktree(world, "review-12", branch=False)
    fresh = add_worktree(world, "baseline-12", branch=False)
    settings = Settings(idle_hours=6, grace_minutes=0)
    found = outcome(run_sweep(world, settings=settings, late=False), "baseline-12")
    assert found.action == "left" and "idle rule" in found.reason
    assert fresh.is_dir() and old.is_dir()
    assert outcome(run_sweep(world, settings=settings, late=True, only=["review-12"]), "review-12").action == "removed"
    assert not old.exists() and fresh.is_dir()


def test_the_idle_rule_can_be_turned_off(world):
    path = add_worktree(world, "review-12", branch=False)
    found = outcome(run_sweep(world, settings=Settings(use_idle=False, grace_minutes=0)), "review-12")
    assert found.action == "left" and path.is_dir()


def test_a_worktree_touched_within_the_grace_is_left(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    world["gh"].pull("net-lobby", 7, "MERGED", git(path, "rev-parse", "HEAD"))
    found = outcome(run_sweep(world, settings=Settings(grace_minutes=30), late=False), "net-lobby")
    assert found.action == "left" and "grace 30 min" in found.reason
    assert path.is_dir()


def test_artwork_notes_and_probes_are_copied_and_generated_files_are_not(world):
    path = add_worktree(world, "art-walls", commit=True, push=True)
    (path / "game" / "art").mkdir(parents=True)
    (path / "game" / "art" / "wall.blend").write_bytes(b"BLENDER")
    (path / "game" / "art" / "wall.glb").write_bytes(b"glTF")
    (path / "game" / "art" / "wall.png").write_bytes(b"png")
    (path / "REVIEW.md").write_text("verdict\n", encoding="utf-8")
    (path / "game" / "probes").mkdir()
    (path / "game" / "probes" / "probe.gd").write_text("extends Node\n", encoding="utf-8")
    (path / "game" / "probes" / "probe.gd.uid").write_text("uid://abc\n", encoding="utf-8")
    (path / "game" / ".godot" / "imported").mkdir(parents=True)
    (path / "game" / ".godot" / "imported" / "wall.ctex").write_bytes(b"cache")
    (path / "game" / "__pycache__").mkdir()
    (path / "game" / "__pycache__" / "x.pyc").write_bytes(b"pyc")
    (path / "README.md").write_text("proj, edited\n", encoding="utf-8")  # a tracked file, changed
    world["gh"].pull("art-walls", 7, "MERGED", git(path, "rev-parse", "HEAD"))
    found = outcome(run_sweep(world), "art-walls")
    assert found.action == "removed"
    kept = world["root"] / "scratch" / "proj" / "art-walls" / "kept"
    assert found.kept_dir == kept
    assert sorted(found.kept) == [
        "README.md",
        "REVIEW.md",
        "game/art/wall.blend",
        "game/art/wall.glb",
        "game/art/wall.png",
        "game/probes/probe.gd",
    ]
    assert (kept / "game" / "art" / "wall.blend").read_bytes() == b"BLENDER"
    assert (kept / "REVIEW.md").read_text(encoding="utf-8") == "verdict\n"
    assert "proj, edited" in (kept / "tracked.patch").read_text(encoding="utf-8")
    listing = (kept / "kept.md").read_text(encoding="utf-8")
    assert "game/art/wall.blend" in listing and "generated file(s)" in listing
    assert not list(kept.rglob("*.uid")) and not (kept / "game" / ".godot").exists()
    assert not list(kept.rglob("*.pyc"))
    assert not path.exists()


def test_a_worktree_with_nothing_to_keep_leaves_no_kept_folder(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    (path / "scene.gd.uid").write_text("uid://x\n", encoding="utf-8")
    world["gh"].pull("net-lobby", 7, "MERGED", git(path, "rev-parse", "HEAD"))
    assert outcome(run_sweep(world), "net-lobby").action == "removed"
    assert not (world["root"] / "scratch").exists()


def test_a_second_sweep_of_the_same_name_does_not_overwrite_the_first_kept_folder(world):
    for _ in range(2):
        path = add_worktree(world, "art-walls", commit=True, push=True)
        (path / "wall.blend").write_bytes(b"x")
        world["gh"] = FakeGh()
        world["gh"].pull("art-walls", 7, "MERGED", git(path, "rev-parse", "HEAD"))
        assert outcome(run_sweep(world), "art-walls").action == "removed"
        git(world["origin"], "branch", "-D", "art-walls")
    base = world["root"] / "scratch" / "proj" / "art-walls"
    assert (base / "kept" / "wall.blend").is_file() and (base / "kept-2" / "wall.blend").is_file()


def test_too_many_files_to_keep_refuse_the_removal(world):
    path = add_worktree(world, "art-walls", commit=True, push=True)
    (path / "big.blend").write_bytes(b"x" * 4096)
    world["gh"].pull("art-walls", 7, "MERGED", git(path, "rev-parse", "HEAD"))
    found = outcome(run_sweep(world, settings=Settings(grace_minutes=0, max_keep_bytes=1024)), "art-walls")
    assert found.action == "refused" and "over the limit" in found.reason
    assert path.is_dir() and (path / "big.blend").is_file()


def test_a_closed_issue_finishes_its_branch_and_an_open_one_keeps_it(world):
    closed = add_worktree(world, "net-old")
    started = add_worktree(world, "net-new")
    ledger = world["root"] / "cache" / "issues-started.json"
    issues.save_ledger(
        ledger,
        {
            "acme/proj#5": {"branch": "net-old", "repo": SLUG, "number": 5},
            "acme/proj#6": {"branch": "net-new", "repo": SLUG, "number": 6},
        },
    )
    world["gh"].issues = {5: "CLOSED", 6: "OPEN"}
    report = run_sweep(world)
    assert outcome(report, "net-old").action == "removed" and "issue #5 closed" in outcome(report, "net-old").reason
    assert (
        outcome(report, "net-new").action == "left" and "issue #6 is in progress" in outcome(report, "net-new").reason
    )
    assert not closed.exists() and started.is_dir()


def test_a_closed_issue_is_found_after_the_ledger_forgot_it(world):
    path = add_worktree(world, "net-old")
    ledger = world["root"] / "cache" / "issues-started.json"
    issues.save_ledger(ledger, {"acme/proj#5": {"branch": "net-old", "repo": SLUG, "number": 5}})
    world["gh"].issues = {5: "OPEN"}
    assert (
        outcome(run_sweep(world, apply=False), "net-old").action == "left"
    )  # remembered in cache/worktree-issues.json
    issues.save_ledger(ledger, {})  # the issue closed and the ledger was pruned
    world["gh"].issues = {5: "CLOSED"}
    assert outcome(run_sweep(world), "net-old").action == "removed"
    assert not path.exists()


def test_when_github_cannot_be_asked_branch_worktrees_stay_and_detached_ones_are_swept(world):
    branch = add_worktree(world, "net-lobby", commit=True, push=True)
    detached = add_worktree(world, "review-3", branch=False)
    world["gh"].down = True
    report = run_sweep(world)
    assert outcome(report, "net-lobby").action == "left" and "GitHub" in outcome(report, "net-lobby").reason
    assert outcome(report, "review-3").action == "removed"
    assert branch.is_dir() and not detached.exists()
    assert any("pull requests unknown" in note for note in report.notes)


def test_only_and_repo_limit_the_sweep(world):
    a = add_worktree(world, "review-1", branch=False)
    b = add_worktree(world, "review-2", branch=False)
    report = run_sweep(world, only=["review-2"])
    assert [o.entry.name for o in report.outcomes] == ["review-2"]
    assert a.is_dir() and not b.exists()
    assert run_sweep(world, repos=["other"]).outcomes == []


def test_locked_worktrees_are_never_removed(world):
    locked = add_worktree(world, "review-9", branch=False)
    git(world["checkout"], "worktree", "lock", str(locked))
    report = run_sweep(world)
    assert outcome(report, "review-9").action == "left" and "locked" in outcome(report, "review-9").reason
    assert locked.is_dir()


def test_the_default_branch_is_never_finished(tmp_path):
    entry = sweep.Entry("proj", tmp_path / "main", "main", "0" * 40, False)
    claims = sweep.Claims({}, lambda args: "")
    verdict, why = sweep.decide(
        entry, default="main", pulls=[], claims=claims, slug=SLUG, idle_seconds=10**9, settings=Settings()
    )
    assert verdict == "left" and "main is checked out" in why


def test_a_worktree_folder_that_is_not_one_is_ignored(world):
    stray = world["root"] / "worktrees" / "proj" / "scratch"
    stray.mkdir()
    (stray / "notes.txt").write_text("not a worktree\n", encoding="utf-8")
    assert run_sweep(world).outcomes == []
    assert (stray / "notes.txt").is_file()


def test_only_one_sweep_runs_at_a_time(world):
    root = world["root"]
    with sweep.lock(root), pytest.raises(sweep.Locked), sweep.lock(root):
        pass
    with sweep.lock(root):  # released
        pass
    lock = root / sweep.LOCK
    lock.write_text("999", encoding="utf-8")
    old = time.time() - sweep.LOCK_STALE_SECONDS - 60
    os.utime(lock, (old, old))
    with sweep.lock(root):  # a killed sweep's lock is taken over
        pass


@pytest.mark.parametrize(
    ("path", "generated"),
    [
        ("game/.godot/imported/a.ctex", True),
        ("game/scripts/player.gd.uid", True),
        ("game/art/wall.png.import", True),
        ("tools/__pycache__/x.cpython-313.pyc", True),
        ("game/reports/report_3/index.html", True),
        ("export/web/index.pck", True),
        ("game/art/wall.blend", False),
        ("game/art/wall.glb", False),
        ("game/art/wall.png", False),
        ("REVIEW.md", False),
        ("STATUS.md", False),
        ("game/probes/probe.gd", False),
        ("probe.log", False),
    ],
)
def test_what_counts_as_generated(path, generated):
    assert sweep.is_generated(path) is generated


def test_the_disk_check_is_silent_with_room_and_names_the_biggest_folders_without(world):
    add_worktree(world, "review-1", branch=False)
    big = world["root"] / "scratch" / "proj" / "captures"
    big.mkdir(parents=True)
    (big / "movie.avi").write_bytes(b"x" * 100_000)
    ok = sweep.disk_lines(world["root"], warn_gb=0)
    assert len(ok) == 1 and "ok" in ok[0] and "GB free" in ok[0]
    low = sweep.disk_lines(world["root"], warn_gb=10**9, top=2)
    assert "WARNING" in low[0] and "gds worktree sweep" in low[0]
    assert any("scratch/proj/captures" in line for line in low)
    assert len(low) <= 3


def test_the_report_names_each_removal_and_the_space(world):
    path = add_worktree(world, "art-walls", commit=True, push=True)
    (path / "a.blend").write_bytes(b"x" * 2048)
    world["gh"].pull("art-walls", 7, "MERGED", git(path, "rev-parse", "HEAD"))
    text = "\n".join(run_sweep(world).lines())
    assert "removed" in text and "proj/art-walls" in text and "pull request #7 merged" in text
    assert "1 file(s) kept in" in text and "1 removed" in text and "files kept for 1 worktree(s)" in text


def test_a_keep_marker_protects_a_scratch_folder_and_the_disk_check_says_so(world):
    art = world["root"] / "scratch" / "proj" / "key-art"
    (art / "renders").mkdir(parents=True)
    (art / "renders" / "icon.png").write_bytes(b"x" * 100_000)
    assert not sweep.protected(art)
    (art / ".keep").write_text("store assets\n", encoding="utf-8")
    assert sweep.protected(art) and sweep.protected(art / "renders") and sweep.protected(art / "renders" / "icon.png")
    assert not sweep.protected(world["root"] / "scratch" / "proj" / "other")
    low = sweep.disk_lines(world["root"], warn_gb=10**9, top=3)
    assert any("scratch/proj/key-art" in line and "protected by .keep" in line for line in low)


def test_a_branch_name_used_again_does_not_inherit_the_old_pull_request(world):
    old = add_worktree(world, "docs-lesson", commit=True, push=True)
    old_head = git(old, "rev-parse", "HEAD")
    git(world["checkout"], "worktree", "remove", "--force", str(old))
    git(world["checkout"], "branch", "-D", "docs-lesson")
    git(world["origin"], "branch", "-D", "docs-lesson")
    world["gh"].pull("docs-lesson", 3, "MERGED", old_head)  # squash-merged long ago; GitHub deleted the branch
    git(world["checkout"], "update-ref", "-d", "refs/remotes/origin/docs-lesson")
    fresh = add_worktree(world, "docs-lesson")  # the same name again, from main, nothing done yet
    found = outcome(run_sweep(world, late=False), "docs-lesson")
    assert found.action == "left" and "no pull request yet" in found.reason
    assert fresh.is_dir()


def test_a_merged_branch_whose_issue_is_still_open_waits_for_the_idle_time(world):
    path = add_worktree(world, "net-lobby", commit=True, push=True)
    world["gh"].pull("net-lobby", 7, "MERGED", git(path, "rev-parse", "HEAD"))
    issues.save_ledger(
        world["root"] / "cache" / "issues-started.json",
        {"acme/proj#5": {"branch": "net-lobby", "repo": SLUG, "number": 5}},
    )
    world["gh"].issues = {5: "OPEN"}
    settings = Settings(idle_hours=6, grace_minutes=0)
    found = outcome(run_sweep(world, settings=settings, late=False), "net-lobby")
    assert found.action == "left" and "issue #5 is still in progress" in found.reason
    assert outcome(run_sweep(world, settings=settings, late=True), "net-lobby").action == "removed"
