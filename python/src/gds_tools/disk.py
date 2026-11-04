"""`gds disk`: the always-on disk guard (docs/workspace.md#disk).

The C: drive of the workspace reached 120 MB free with some 25 agents at work: Godot imports were truncated, a
pre-commit hook emptied a source file, test runs failed. `gds worktree sweep` existed, but nothing watched the disk.

The guard is two numbers and three clean-ups:

- **soft** (`soft_gb`): below it, `gds disk guard` frees space: the worktree sweep, the Godot import caches
  (`.godot/imported`) of worktrees nobody has touched for `imports_idle_hours` and no process names, and the downloads
  of scratch topics past their pull request;
- **hard** (`hard_gb`): below it, no new task agent and no new worktree starts (the hooks and `gds issue start`
  refuse, with the free space and the biggest folders), until space is back.

It never deletes a running agent's worktree, nothing unpublished (the sweep's rules), nothing in a folder with a
`.keep`, no `kept/` folder of the sweep, no note. Every run writes `cache/disk-guard.json`, which the hooks read for
their messages and the GDStudio mod shows in the status line, with the folders over their budget.

The limits live in the kit's `.claude/hooks/hooks.toml` (`[disk]`), so the hooks and this command read one source.
"""

from __future__ import annotations

import contextlib
import fnmatch
import json
import os
import re
import shutil
import stat
import time
import tomllib
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from gds_tools import issues, sweep
from gds_tools.worktrees import WorktreeError

GB = 1024**3
STATUS = "cache/disk-guard.json"
LOCK = "cache/disk-guard.lock"
#: The note a scratch topic keeps: `PR: owner/repo#N` (the pull request it serves) and `Can go: <glob> ...` lines.
NOTE = "SCRATCH.md"
#: Folders of the sweep's kept files: never deleted.
KEPT = re.compile(r"^kept(-\d+)?$")
_PR_LINE = re.compile(r"(?im)^[ \t>*-]*PR[ \t]*:[ \t]*`?([\w.-]+/[\w.-]+)#(\d+)`?")
_CAN_GO_LINE = re.compile(r"(?im)^[ \t>*-]*Can go[ \t]*:[ \t]*(.+)$")


@dataclass(frozen=True)
class Limits:
    """`[disk]` of hooks.toml."""

    soft_gb: float = 40.0
    hard_gb: float = 10.0
    worktree_budget_gb: float = 4.0
    scratch_budget_gb: float = 2.0
    imports_idle_hours: float = 2.0
    scratch_grace_hours: float = 2.0
    #: Folder names inside a finished scratch topic whose whole content can go (downloaded CI artifacts and the like).
    can_go_dirs: tuple[str, ...] = ("artifacts", "downloads", "ci-artifacts", "dl", ".godot")
    #: File names (globs) inside a finished scratch topic that can go: archives, web exports, raw movie output, and the
    #: numbered frames Movie Maker writes (26 GB of the 50 GB of scratch when the disk filled; the clip, the contact
    #: sheet and the pull request's attachments are what is kept).
    can_go_files: tuple[str, ...] = (
        "*.zip",
        "*.7z",
        "*.tar",
        "*.tar.gz",
        "*.tgz",
        "*.avi",
        "*.pck",
        "*.wasm",
        "*[0-9][0-9][0-9][0-9].png",
    )
    top: int = 5
    measure_seconds: float = 240.0


def load_limits(kit: Path | None) -> Limits:
    """The `[disk]` table of `<kit>/.claude/hooks/hooks.toml`; the defaults when it is missing."""
    path = kit / ".claude" / "hooks" / "hooks.toml" if kit else None
    table: dict = {}
    if path and path.is_file():
        with contextlib.suppress(OSError, tomllib.TOMLDecodeError):
            table = tomllib.loads(path.read_text(encoding="utf-8")).get("disk", {})
    known = Limits.__dataclass_fields__
    values = {k: (tuple(v) if isinstance(v, list) else v) for k, v in table.items() if k in known}
    return Limits(**values)


def free_bytes(root: Path) -> int:
    return shutil.disk_usage(root).free


def level(free: int, limits: Limits) -> str:
    """`hard`, `soft` or `ok` for a number of free bytes."""
    if free < limits.hard_gb * GB:
        return "hard"
    if free < limits.soft_gb * GB:
        return "soft"
    return "ok"


def read_status(root: Path) -> dict:
    """The last guard run's `cache/disk-guard.json`; empty when there is none."""
    with contextlib.suppress(OSError, ValueError):
        data = json.loads((root / STATUS).read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    return {}


def refusal(root: Path, limits: Limits, what: str, free: int | None = None) -> str | None:
    """Why `what` (a new agent, a new worktree) may not start: the disk is under the hard limit. None when it may."""
    free = free_bytes(root) if free is None else free
    if level(free, limits) != "hard":
        return None
    biggest = read_status(root).get("biggest", [])[: limits.top]
    names = "; ".join(f"{b['path']} {b['gb']:.1f} GB" for b in biggest if isinstance(b, dict) and "path" in b)
    return (
        f"{what} refused: the disk has {free / GB:.1f} GB free, under the hard limit of {limits.hard_gb:g} GB "
        f"(docs/workspace.md#disk). Nothing new starts until space is back. `gds disk guard` frees what the rules "
        f"allow (finished worktrees, idle import caches, scratch downloads past their pull request); tell the "
        f"coordinator and the maintainer what is left." + (f" The biggest folders: {names}." if names else "")
    )


# --------------------------------------------------------------------------------------------------------------------
# Measuring
# --------------------------------------------------------------------------------------------------------------------


@dataclass
class Item:
    path: str  # relative to the workspace, `/` separators
    kind: str  # worktree | scratch
    bytes: int
    budget_gb: float

    @property
    def gb(self) -> float:
        return self.bytes / GB

    @property
    def over(self) -> bool:
        return self.bytes > self.budget_gb * GB


def measure(root: Path, limits: Limits, deadline: float | None = None) -> list[Item]:
    """Every worktree (`worktrees/<repo>/<name>`) and scratch topic (`scratch/<group>/<name>`), biggest first."""
    items: list[Item] = []
    for group, kind, budget in (
        ("worktrees", "worktree", limits.worktree_budget_gb),
        ("scratch", "scratch", limits.scratch_budget_gb),
    ):
        base = root / group
        if not base.is_dir():
            continue
        for first in sorted(p for p in base.iterdir() if p.is_dir() and not p.is_symlink()):
            for second in sorted(first.iterdir()):
                with contextlib.suppress(OSError):
                    size = sweep.size_of(second, deadline) if second.is_dir() else second.stat().st_size
                    items.append(Item(second.relative_to(root).as_posix(), kind, size, budget))
    items.sort(key=lambda i: i.bytes, reverse=True)
    return items


# --------------------------------------------------------------------------------------------------------------------
# Clean-ups
# --------------------------------------------------------------------------------------------------------------------


@dataclass
class Freed:
    path: str
    bytes: int
    why: str


def delete_tree(path: Path) -> None:
    def writable(function, target, _info):  # a read-only file (Windows) blocks the delete
        os.chmod(target, stat.S_IWRITE)
        function(target)

    shutil.rmtree(path, onerror=writable)


def import_caches(tree: Path) -> list[Path]:
    """The `.godot/imported` folders of a worktree: at its root or one or two folders down (`game/.godot`)."""
    found = []
    for pattern in (".godot/imported", "*/.godot/imported", "*/*/.godot/imported"):
        found += [p for p in tree.glob(pattern) if p.is_dir() and not p.is_symlink()]
    return found


def clear_imports(
    root: Path,
    limits: Limits,
    *,
    apply: bool,
    running: Sequence[tuple[int, str, str]],
    now: float,
    activity: Callable[[Path], float] | None = None,
) -> list[Freed]:
    """Delete `.godot/imported` of every worktree nobody touched for `imports_idle_hours` and no process names. Godot
    rebuilds it on the next import (`--import`, or the editor), as it does in a fresh worktree. Main checkouts
    (`repos/`) are never touched."""
    activity = activity or (lambda tree: sweep.last_activity(tree, [], sweep.git))
    freed: list[Freed] = []
    base = root / "worktrees"
    if not base.is_dir():
        return freed
    for repo in sorted(p for p in base.iterdir() if p.is_dir()):
        for tree in sorted(p for p in repo.iterdir() if p.is_dir() and not p.is_symlink()):
            caches = import_caches(tree)
            if not caches or sweep.protected(tree):
                continue
            idle = now - activity(tree)
            if idle < limits.imports_idle_hours * 3600 or sweep.users_of(tree, running):
                continue
            for cache in caches:
                size = sweep.size_of(cache)
                why = f"import cache of a worktree untouched for {idle / 3600:.1f} h"
                if apply:
                    try:
                        delete_tree(cache)
                    except OSError:
                        continue
                freed.append(Freed(cache.relative_to(root).as_posix(), size, why))
    return freed


@dataclass
class Topic:
    path: Path
    repo: str  # the folder under scratch/: a repository name, or another group
    note: str


def topic_prs(note: str) -> list[tuple[str, int]]:
    return [(repo, int(n)) for repo, n in _PR_LINE.findall(note)]


def topic_can_go(note: str) -> list[str]:
    return [g for line in _CAN_GO_LINE.findall(note) for g in line.replace(",", " ").split() if g.strip("`")]


def newest_change(path: Path, deadline: float | None = None) -> float:
    """The newest modification time of anything in a folder (links are not followed)."""
    newest, stack = 0.0, [path]
    with contextlib.suppress(OSError):
        newest = path.stat().st_mtime
    while stack:
        if deadline is not None and time.time() > deadline:
            return time.time()  # unknown: count it as touched now
        try:
            with os.scandir(stack.pop()) as entries:
                for entry in entries:
                    with contextlib.suppress(OSError):
                        if entry.is_symlink() or entry.is_junction():
                            continue
                        newest = max(newest, entry.stat(follow_symlinks=False).st_mtime)
                        if entry.is_dir():
                            stack.append(Path(entry.path))
        except OSError:
            continue
    return newest


PrState = Callable[[str, int], str]  # (owner/repo, number) -> OPEN | MERGED | CLOSED | UNKNOWN
BranchPulls = Callable[[str, str], list[str]]  # (repo folder name, branch) -> states of its pull requests


def topic_finished(
    root: Path,
    topic: Topic,
    limits: Limits,
    *,
    pr_state: PrState,
    branch_pulls: BranchPulls,
    running: Sequence[tuple[int, str, str]],
    now: float,
) -> tuple[bool, str]:
    """Whether a scratch topic is past its pull request: (finished, why). A topic is finished when the pull requests
    its `SCRATCH.md` names (`PR: owner/repo#N`) all merged or closed, or, without such a line, when its folder name is
    a branch whose pull requests all merged or closed. It is never finished while a worktree of that name exists, a
    process names it, a `.keep` protects it, or it changed in the last `scratch_grace_hours`."""
    if sweep.protected(topic.path):
        return False, "protected by .keep"
    if (root / "worktrees" / topic.repo / topic.path.name).exists():
        return False, "its worktree still exists"
    if sweep.users_of(topic.path, running):
        return False, "a process uses it"
    named = topic_prs(topic.note)
    if named:
        states = [pr_state(repo, number) for repo, number in named]
        if any(s not in ("MERGED", "CLOSED") for s in states):
            return False, "a pull request it names is open or unknown"
        why = "pull request " + ", ".join(f"{r}#{n}" for r, n in named) + " finished"
    else:
        states = branch_pulls(topic.repo, topic.path.name)
        if not states:
            return False, "no pull request is known for it (name one with a `PR:` line in SCRATCH.md)"
        if any(s not in ("MERGED", "CLOSED") for s in states):
            return False, "its branch has an open pull request"
        why = "the pull request of its branch finished"
    idle = now - newest_change(topic.path, time.time() + 60)
    if idle < limits.scratch_grace_hours * 3600:
        return False, f"changed {idle / 3600:.1f} h ago (grace {limits.scratch_grace_hours:g} h)"
    return True, why


def downloads_in(topic: Topic, limits: Limits) -> list[Path]:
    """What can go from a finished topic: the `can_go_dirs` folders, the `can_go_files` files and the topic's own
    `Can go:` globs. Never a note (`*.md`), never the sweep's `kept/` folders."""
    globs = topic_can_go(topic.note)
    found: list[Path] = []
    stack = [topic.path]
    while stack:
        folder = stack.pop()
        try:
            entries = list(os.scandir(folder))
        except OSError:
            continue
        for entry in entries:
            path = Path(entry.path)
            rel = path.relative_to(topic.path).as_posix()
            with contextlib.suppress(OSError):
                if entry.is_symlink() or entry.is_junction():
                    continue
                if entry.is_dir():
                    if KEPT.match(entry.name) or sweep.protected(path):
                        continue
                    if entry.name in limits.can_go_dirs or any(fnmatch.fnmatch(rel, g) for g in globs):
                        found.append(path)
                    else:
                        stack.append(path)
                    continue
                if entry.name.lower().endswith(".md") or entry.name == sweep.KEEP_MARKER:
                    continue
                if any(fnmatch.fnmatch(entry.name.lower(), g) for g in limits.can_go_files) or any(
                    fnmatch.fnmatch(rel, g) for g in globs
                ):
                    found.append(path)
    return sorted(found)


def scratch_topics(root: Path) -> list[Topic]:
    """`scratch/<group>/<name>/` folders, with their `SCRATCH.md` (empty when there is none)."""
    topics = []
    base = root / "scratch"
    if not base.is_dir():
        return topics
    for group in sorted(p for p in base.iterdir() if p.is_dir() and not p.is_symlink()):
        for folder in sorted(p for p in group.iterdir() if p.is_dir() and not p.is_symlink()):
            note = ""
            with contextlib.suppress(OSError):
                note = (folder / NOTE).read_text(encoding="utf-8", errors="replace")
            topics.append(Topic(folder, group.name, note))
    return topics


def clear_scratch(
    root: Path,
    limits: Limits,
    *,
    apply: bool,
    pr_state: PrState,
    branch_pulls: BranchPulls,
    running: Sequence[tuple[int, str, str]],
    now: float,
) -> list[Freed]:
    """Delete the downloads of every scratch topic past its pull request (`topic_finished`, `downloads_in`)."""
    freed: list[Freed] = []
    for topic in scratch_topics(root):
        done, why = topic_finished(
            root, topic, limits, pr_state=pr_state, branch_pulls=branch_pulls, running=running, now=now
        )
        if not done:
            continue
        total, count = 0, 0  # one line per topic: a capture leaves thousands of frames
        for path in downloads_in(topic, limits):
            size = sweep.size_of(path) if path.is_dir() else path.stat().st_size
            if apply:
                try:
                    delete_tree(path) if path.is_dir() else path.unlink()
                except OSError:
                    continue
            total, count = total + size, count + 1
        if count:
            rel = topic.path.relative_to(root).as_posix()
            freed.append(Freed(rel, total, f"{count} scratch download(s): {why}"))
    return freed


# --------------------------------------------------------------------------------------------------------------------
# GitHub, cached per run
# --------------------------------------------------------------------------------------------------------------------


class Pulls:
    """Pull request states of the workspace's repositories, asked once per repository per run."""

    def __init__(self, root: Path, gh: issues.Gh = issues.run_gh):
        self.root, self.gh = root, gh
        self.by_repo: dict[str, dict[str, list[sweep.Pull]] | None] = {}
        self.numbers: dict[tuple[str, int], str] = {}

    def _repo(self, folder: str) -> dict[str, list[sweep.Pull]] | None:
        if folder not in self.by_repo:
            checkout = self.root / "repos" / folder
            try:
                slug = sweep.remote_slug(checkout) if (checkout / ".git").exists() else ""
                self.by_repo[folder] = sweep.pulls_by_branch(slug, self.gh) if slug else None
            except (WorktreeError, issues.IssueError, ValueError):
                self.by_repo[folder] = None
        return self.by_repo[folder]

    def branch(self, folder: str, branch: str) -> list[str]:
        found = self._repo(folder)
        return [p.state for p in found.get(branch, [])] if found else []

    def state(self, slug: str, number: int) -> str:
        key = (slug.lower(), number)
        if key not in self.numbers:
            try:
                row = json.loads(self.gh(["pr", "view", str(number), "--repo", slug, "--json", "state"]))
                self.numbers[key] = str(row.get("state", "UNKNOWN")).upper()
            except (issues.IssueError, ValueError):
                self.numbers[key] = "UNKNOWN"
        return self.numbers[key]


# --------------------------------------------------------------------------------------------------------------------
# The guard
# --------------------------------------------------------------------------------------------------------------------


@dataclass
class Report:
    free_before: int
    free_after: int
    level: str
    limits: Limits
    freed: list[Freed] = field(default_factory=list)
    items: list[Item] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    dry_run: bool = False

    @property
    def freed_bytes(self) -> int:
        return sum(f.bytes for f in self.freed)

    def status_line(self) -> str:
        """The one line the status line shows: free space, level, and the folders over their budget."""
        gb = self.free_after / GB
        mark = {"hard": f" HARD<{self.limits.hard_gb:g}", "soft": f" low<{self.limits.soft_gb:g}"}.get(self.level, "")
        over = [i for i in self.items if i.over][:3]
        tail = " | over budget: " + ", ".join(f"{_short(i.path)} {i.gb:.1f}G" for i in over) if over else ""
        return f"disk {gb:.1f}G free{mark}{tail}"

    def status(self) -> dict:
        return {
            "checked": datetime.now().astimezone().isoformat(timespec="seconds"),
            "free_gb": round(self.free_after / GB, 2),
            "level": self.level,
            "soft_gb": self.limits.soft_gb,
            "hard_gb": self.limits.hard_gb,
            "freed_gb": round(self.freed_bytes / GB, 2),
            "line": self.status_line(),
            "over_budget": [
                {"path": i.path, "gb": round(i.gb, 2), "budget_gb": i.budget_gb} for i in self.items if i.over
            ],
            "biggest": [{"path": i.path, "gb": round(i.gb, 2)} for i in self.items[: self.limits.top]],
        }

    def lines(self) -> list[str]:
        verb = "would free" if self.dry_run else "freed"
        out = [
            f"disk: {self.free_before / GB:.1f} GB free before, {self.free_after / GB:.1f} GB after "
            f"(soft {self.limits.soft_gb:g} GB, hard {self.limits.hard_gb:g} GB): {self.level}",
            *self.notes,
        ]
        out += [f"{verb:10} {sweep.human(f.bytes):>9}  {f.path}: {f.why}" for f in self.freed]
        out.append(f"{verb} {sweep.human(self.freed_bytes)} in all")
        over = [i for i in self.items if i.over]
        out += [f"over budget {sweep.human(i.bytes):>9}  {i.path} (budget {i.budget_gb:g} GB)" for i in over]
        out += [f"biggest    {sweep.human(i.bytes):>9}  {i.path}" for i in self.items[: self.limits.top]]
        return out


def _short(path: str) -> str:
    parts = path.split("/")
    return "/".join(parts[1:]) if len(parts) > 2 else path


def guard(
    root: Path,
    limits: Limits,
    *,
    apply: bool = True,
    force: bool = False,
    gh: issues.Gh = issues.run_gh,
    processes: sweep.Processes = sweep.list_processes,
    free: Callable[[Path], int] = free_bytes,
    run_sweep: Callable[[Path, bool, float], sweep.Report] | None = None,
    now: float | None = None,
    measure_items: bool = True,
) -> Report:
    """Check the free space; below `soft_gb` (or with `force`), free what the rules allow; measure the budgets; write
    `cache/disk-guard.json`. The sweep runs under its own lock: when another sweep holds it, that part is skipped."""
    clock = time.time() if now is None else now
    before = free(root)
    report = Report(before, before, level(before, limits), limits, dry_run=not apply)
    if report.level != "ok" or force:
        try:
            running = processes()
        except WorktreeError as error:
            report.notes.append(f"nothing freed: {error}")
            running = None
        if running is not None:
            idle = limits.imports_idle_hours if report.level == "hard" else sweep.Settings().idle_hours
            try:
                swept = (run_sweep or _run_sweep)(root, apply, idle)
                report.freed += [
                    Freed(o.entry.path.relative_to(root).as_posix(), o.size, f"worktree: {o.reason}")
                    for o in swept.with_action("removed", "would-remove")
                ]
            except sweep.Locked as error:
                report.notes.append(f"worktree sweep skipped: {error}")
            report.freed += clear_imports(root, limits, apply=apply, running=running, now=clock)
            pulls = Pulls(root, gh)
            report.freed += clear_scratch(
                root,
                limits,
                apply=apply,
                pr_state=pulls.state,
                branch_pulls=pulls.branch,
                running=running,
                now=clock,
            )
    report.free_after = free(root)
    report.level = level(report.free_after, limits)
    if measure_items:
        report.items = measure(root, limits, time.time() + limits.measure_seconds)
    write_status(root, report)
    return report


def _run_sweep(root: Path, apply: bool, idle_hours: float) -> sweep.Report:
    with sweep.lock(root):
        return sweep.sweep(root, apply=apply, settings=sweep.Settings(idle_hours=idle_hours), deadline_seconds=900)


def write_status(root: Path, report: Report) -> None:
    path = root / STATUS
    with contextlib.suppress(OSError):
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix(".tmp")
        temp.write_text(json.dumps(report.status(), indent=1) + "\n", encoding="utf-8", newline="\n")
        os.replace(temp, path)
