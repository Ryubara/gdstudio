"""`gds disk`: the always-on disk guard (docs/studio/workspace.md#disk).

The C: drive of the workspace reached 120 MB free with some 25 agents at work: Godot imports were truncated, a
pre-commit hook emptied a source file, test runs failed. `gds worktree sweep` existed, but nothing watched the disk.

The guard is two numbers and three clean-ups:

- **soft** (`soft_gb`): below it, `gds disk guard` frees space: the worktree sweep, the Godot import caches
  (`.godot/imported`) of worktrees nobody has touched for `imports_idle_hours` and no process names, and the downloads
  and raw captures of scratch topics past their issue or pull request;
- **hard** (`hard_gb`): below it, no new task agent and no new worktree starts (the hooks and `gds issue start`
  refuse, with the free space and the biggest folders), until space is back.

It never deletes a running agent's worktree, nothing unpublished (the sweep's rules), nothing in a folder with a
`.keep`, no `kept/` folder of the sweep, no note, nothing of a scratch topic that names open work or that a process
names, and nothing it could not check: a read that fails holds, it never clears. Every run writes
`cache/disk-guard.json`, which the hooks read for their messages and the GDStudio mod shows in the status line, with
the folders over their budget.

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

from gds_tools import issues, sweep, workspace
from gds_tools.worktrees import WorktreeError

GB = 1024**3
STATUS = "cache/disk-guard.json"
LOCK = "cache/disk-guard.lock"
#: The note a scratch topic keeps: `PR:` and `Issue:` lines (the work it serves) and `Can go: <glob> ...` lines.
NOTE = "SCRATCH.md"
#: The running notes most topics keep instead; the work is named in the first `HEAD_LINES` lines of either note.
STATUS_NOTE = "STATUS.md"
HEAD_LINES = 6
#: Folders of the sweep's kept files: never deleted.
KEPT = re.compile(r"(?i)^kept(-\d+)?$")
#: `gh issue list` and `gh pr list` stop at their limit with no error: a full page is no answer (`Pulls._numbers`).
LIST_LIMIT = 5000
IMAGES = (".png", ".jpg", ".jpeg", ".bmp", ".exr", ".webp")
#: Files a repository carries, copied into a topic with its tree: not notes of the topic. `LICENSE.md` of the game cites
#: its tracking issue, and it held 127 topics and 6 GB of the 28.6 GB of #691 until it was left out.
REPO_NOTES = ("license.md", "readme.md", "changelog.md", "credits.md", "contributing.md", "agents.md", "claude.md")
#: What marks a folder as a copy of a repository: none of its `*.md` is a note of the topic.
REPO_MARKS = ("project.godot", ".git", "license.md")
#: The start of the reason `topic_finished` gives when only the clock says a topic is over: `CAPTURES` needs more.
BY_THE_CLOCK = "no pull request named"
_WORK_LINE = re.compile(r"(?im)^[ \t>*-]*(?:\*\*)?(?:PRs?|Pull requests?|Issues?)(?:\*\*)?[ \t]*:(.+)$")
_CAN_GO_LINE = re.compile(r"(?im)^[ \t>*-]*(?:\*\*)?Can go(?:\*\*)?[ \t]*:[ \t]*(.+)$")
#: `#7`, `Deadnight #7`, `kit PR #7`, `gdstudio#7`, `owner/repo#7`: what stands before the `#` is for `references`.
_NUMBER = re.compile(r"(?i)(?:(?P<owner>[\w.-]+)/)?(?P<repo>[\w.-]+)?(?:[ \t]+(?:PR|issue))?[ \t]?#(?P<n>\d{1,6})\b")
_URL = re.compile(r"(?i)github\.com/(?P<slug>[\w.-]+/[\w.-]+)/(?:issues|pull)/(?P<n>\d+)")


@dataclass(frozen=True)
class Limits:
    """`[disk]` of hooks.toml."""

    soft_gb: float = 40.0
    hard_gb: float = 10.0
    worktree_budget_gb: float = 4.0
    scratch_budget_gb: float = 2.0
    imports_idle_hours: float = 2.0
    #: A scratch topic changed this recently stays, whatever its issue says. #691 judged by 12 hours by hand.
    scratch_grace_hours: float = 12.0
    #: How long a scratch topic that names no pull request (no `PR:` line, and no pull request of that branch name) is
    #: held after its last change; then its downloads go like those of a finished topic. Most topics are named for
    #: their subject (`grenade-feel`), so without this their captures stayed for ever. 0 keeps them for ever.
    unknown_topic_days: float = 3.0
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
    #: The rest of what #691 freed by hand (6.9 GB of WAV and AVI, 1.3 GB of logs, 17.5 GB of frames): only from a topic
    #: known to be over, by its issue, its pull request or its branch. A topic with nothing but its age to go by, which
    #: #691 held as "cannot tell", loses only the list above.
    capture_files: tuple[str, ...] = (
        "*.gz",
        "*.xz",
        "*.mkv",
        "*.wav",
        "*.log",
        "*.out",
        "*.err",
        "*.clean",
        "*[0-9][0-9][0-9][0-9].jpg",
        "*[0-9][0-9][0-9][0-9].jpeg",
        "*[0-9][0-9][0-9][0-9].exr",
    )
    #: This many images in one folder are frames, whatever their names (a capture numbers its frames or names its
    #: views); fewer are screenshots and stay.
    frame_folder_min: int = 20
    #: Images that stay however many there are: sheets, comparisons, and what a pull request attached.
    keep_images: tuple[str, ...] = ("*sheet*", "*contact*", "*montage*", "*compare*", "*before_after*")
    keep_image_dirs: tuple[str, ...] = ("sheets*", "pr", "attach")
    #: Folders of inputs, not output: nothing in them is ever deleted (a `source` WAV is an asset, not a capture).
    keep_dirs: tuple[str, ...] = ("source", "sources", "ref", "refs", "reference", "references")
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
        f"(docs/studio/workspace.md#disk). Nothing new starts until space is back. `gds disk guard` frees what the "
        f"rules "
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


Ref = tuple[str, int]  # (owner/repo, number); the owner/repo is empty when the note does not say and nothing tells
SlugOf = Callable[[str], str]  # (a folder of repos/ or scratch/) -> its owner/repo, empty when it is no repository


def references(text: str, group: str, slug_of: SlugOf) -> list[Ref]:
    """Every issue or pull request a text names. `#7` means the repository of the topic's group, `kit #7` and
    `gdstudio #7` the kit, `owner/repo#7` and a GitHub link what they say."""
    found = [(m["slug"], int(m["n"])) for m in _URL.finditer(text)]
    for match in _NUMBER.finditer(text):
        repo, number = (match["repo"] or "").lower(), int(match["n"])
        if match["owner"]:
            found.append((f"{match['owner']}/{match['repo']}", number))
        elif repo == "kit":
            found.append((slug_of(workspace.KIT), number))
        else:
            found.append((slug_of(repo) or slug_of(group) if repo else slug_of(group), number))
    return list(dict.fromkeys(found))


def work_of(notes: dict[str, str], group: str, slug_of: SlugOf) -> tuple[list[Ref], list[Ref]]:
    """The work a topic says it serves: what its `PR:` and `Issue:` lines declare, which must resolve, and what the
    first lines of its notes name, which may also be a colour or another project's bug."""
    declared: list[Ref] = []
    heads: list[Ref] = []
    for name in (NOTE, STATUS_NOTE):
        text = notes.get(name, "")
        declared += [ref for line in _WORK_LINE.findall(text) for ref in references(line, group, slug_of)]
        heads += references("\n".join(text.splitlines()[:HEAD_LINES]), group, slug_of)
    return list(dict.fromkeys(declared)), list(dict.fromkeys(heads))


def read_notes(path: Path) -> dict[str, str] | None:
    """The notes of a topic, by path inside it; None when one cannot be read (a note in use is a topic in use). Every
    `*.md` at any depth, but not what a repository carries (`REPO_NOTES`) or the inside of a copy of one (`REPO_MARKS`):
    a topic is held by what its agent wrote, not by the game's licence file."""
    notes: dict[str, str] = {}
    for folder, dirs, files in os.walk(path):
        here = {name.lower() for name in [*dirs, *files]}
        if folder != str(path) and here.intersection(REPO_MARKS):
            dirs[:] = []
            continue
        dirs[:] = [d for d in dirs if not (Path(folder) / d).is_symlink() and not (Path(folder) / d).is_junction()]
        for name in files:
            if name.lower().endswith(".md") and name.lower() not in REPO_NOTES:
                target = Path(folder) / name
                try:
                    notes[target.relative_to(path).as_posix()] = target.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    return None
    return notes


def topic_can_go(note: str) -> list[str]:
    """The globs of the `Can go:` lines. A glob has a wildcard, a dot or a slash; the other words are prose."""
    words = [w.strip("`'\"") for line in _CAN_GO_LINE.findall(note) for w in line.replace(",", " ").split()]
    return [w for w in words if any(c in w for c in "*?/.") and w != "."]


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
            return time.time()  # unknown: count it as touched now
    return newest


WorkState = Callable[[str, int], str]  # (owner/repo, number) -> OPEN | MERGED | CLOSED | MISSING | UNKNOWN
BranchPulls = Callable[[str, str], list[str]]  # (repo folder name, branch) -> states of its pull requests
OpenNames = Callable[[str], bool | None]  # (scratch/<group>/<name>) -> does open work name it; None: not known


def topic_finished(
    root: Path,
    topic: Topic,
    limits: Limits,
    *,
    work_state: WorkState,
    branch_pulls: BranchPulls,
    running: Sequence[tuple[int, str, str]],
    now: float,
    slug_of: SlugOf = lambda folder: "",
    open_names: OpenNames = lambda path: False,
) -> tuple[bool, str]:
    """Whether a scratch topic is past its work: (finished, why). Deleting live work is the failure that matters, so
    every question here holds on doubt. A topic **stays** while a `.keep` protects it, a worktree of its name exists, a
    process names it (its path or its bare name: `process_naming`), it changed in the last `scratch_grace_hours`, any
    of its `*.md` names an open issue or pull request (the whole text of every note: `rookie-parity`'s live issue was
    in the prose of a third file), an open issue or pull request names its folder, its branch has an open pull request,
    or GitHub could not be read.

    Past those, a topic is **finished** when the work it says it serves (`work_of`: `PR:` and `Issue:` lines, the first
    lines of its notes) is all merged or closed, or, when it says nothing, when its folder name is a branch whose pull
    requests all merged or closed. A topic that names no work and whose name is no branch is finished once it has been
    idle `unknown_topic_days` (3), and then only for the `can_go` lists: the age of a folder says nothing of its work.
    In every case only downloads and captures go (`downloads_in`), never a note, `kept/`, `source` or `.keep`."""
    if sweep.protected(topic.path):
        return False, "protected by .keep"
    if (root / "worktrees" / topic.repo / topic.path.name).exists():
        return False, "its worktree still exists"
    if process_naming(topic.path, running):
        return False, "a process uses it"
    idle = now - newest_change(topic.path, time.time() + 60)
    if idle < limits.scratch_grace_hours * 3600:
        return False, f"changed {idle / 3600:.1f} h ago (grace {limits.scratch_grace_hours:g} h)"
    notes = read_notes(topic.path)
    if notes is None:
        return False, "a note could not be read"
    declared, heads = work_of({NOTE: topic.note, **notes}, topic.repo, slug_of)
    if any(not slug for slug, _ in declared):
        return False, "it names a number and its repository is unknown"

    def ours(slug: str) -> bool:  # another project's bug stays open for ever and says nothing about this topic
        return bool(slug) and slug_of(slug.rsplit("/", 1)[-1].lower()).lower() == slug.lower()

    for slug, number in {ref for text in notes.values() for ref in references(text, topic.repo, slug_of)}:
        if ours(slug) and work_state(slug, number) in ("OPEN", "UNKNOWN"):
            return False, f"{slug}#{number}, which it names, is open or unknown"
    work = declared + [r for r in heads if r not in declared and ours(r[0]) and work_state(*r) != "MISSING"]
    named = open_names(topic.path.relative_to(root).as_posix())
    if named is not False:
        return False, "open work names it, or open work could not be read"
    pulls = branch_pulls(topic.repo, topic.path.name)
    if "UNKNOWN" in pulls:
        return False, "the pull requests of its branch could not be read"
    if any(s not in ("MERGED", "CLOSED") for s in pulls):
        return False, "its branch has an open pull request"
    if work:
        if any(work_state(slug, number) not in ("MERGED", "CLOSED") for slug, number in work):
            return False, "a pull request or issue it names is open or unknown"
        return True, ", ".join(f"{slug}#{number}" for slug, number in work[:3]) + " finished"
    if pulls:
        return True, "the pull request of its branch finished"
    days = limits.unknown_topic_days
    if days <= 0:
        return False, "no pull request is known for it (name one with a `PR:` line in SCRATCH.md)"
    if idle < days * 86400:
        return False, (
            f"no pull request is known for it and it changed {idle / 86400:.1f} days ago "
            f"(held {days:g} days; name a pull request with a `PR:` line in SCRATCH.md)"
        )
    return True, f"{BY_THE_CLOCK}, idle {idle / 86400:.1f} days (held {days:g})"


def process_naming(path: Path, running: Sequence[tuple[int, str, str]]) -> list[int]:
    """The processes that use a topic's folder (`sweep.users_of`) or say its bare name: a relative path, an agent's or
    a job's name. On the process list #691 saved a bare name held 6 of 476 topics, none of them finished: a false hold
    costs some disk for a while, a missed one costs live work."""
    used = [pid for pid, _ in sweep.users_of(path, running)]
    bare = re.compile(r"(?<![\w.-])" + re.escape(path.name.lower()) + r"(?![\w.-])")
    return used + [pid for pid, command, _ in running if bare.search(command.lower())]


def _stays(entry: os.DirEntry, limits: Limits) -> bool:
    """Whether nothing under this folder entry may be deleted: a kept folder, a folder of inputs, a marker or a link."""
    low = entry.name.lower()
    if entry.is_symlink() or entry.is_junction():
        return True
    if entry.is_dir():
        return bool(KEPT.match(low)) or low in limits.keep_dirs or sweep.protected(Path(entry.path))
    return low.endswith(".md") or low == sweep.KEEP_MARKER


def _free_of_keepers(folder: Path, limits: Limits) -> bool:
    """Whether a folder can be deleted whole: nothing in it, at any depth, is a note, a kept folder or a link. Whatever
    cannot be read counts as a keeper."""
    stack = [folder]
    while stack:
        try:
            with os.scandir(stack.pop()) as entries:
                for entry in entries:
                    if _stays(entry, limits) or entry.name == ".git":
                        return False
                    if entry.is_dir():
                        stack.append(Path(entry.path))
        except OSError:
            return False
    return True


def _is_capture(path: Path, topic: Path, images: int, web: bool, limits: Limits, captures: bool) -> bool:
    """Whether a file is a raw capture or a download: `images` is how many images its folder holds, `web` whether the
    folder is a web export, `captures` whether the topic is known to be over and not just old."""
    low, suffix = path.name.lower(), path.suffix.lower()
    if suffix in IMAGES:
        folders = [part.lower() for part in path.relative_to(topic).parts[:-1]]
        if any(fnmatch.fnmatch(low, g) for g in limits.keep_images) or any(
            fnmatch.fnmatch(part, g) for part in folders for g in limits.keep_image_dirs
        ):
            return False
        if captures and images >= limits.frame_folder_min:
            return True
    if suffix == ".wav" and "voice" in topic.name.lower():
        return False  # voice takes are the work, not a capture of it
    if captures and web and suffix in (".html", ".js"):
        return True
    return any(fnmatch.fnmatch(low, g) for g in (*limits.can_go_files, *(limits.capture_files if captures else ())))


def downloads_in(topic: Topic, limits: Limits, captures: bool = True) -> list[Path]:
    """What can go from a finished topic: the `can_go_dirs` folders, raw captures and frames (`_is_capture`; with
    `captures` off, only `can_go_files`) and the topic's own `Can go:` globs. Never a note (`*.md`), a `.keep`, the
    sweep's `kept/` folders, a `source` folder, a link or a git checkout, at any depth: a folder holding one of those is
    emptied around it, not deleted whole."""
    globs = topic_can_go(topic.note)
    found: list[Path] = []
    stack = [(topic.path, False)]  # a folder, and whether all of it was marked to go
    while stack:
        folder, marked = stack.pop()
        try:
            entries = list(os.scandir(folder))
        except OSError:
            continue
        if any(entry.name == ".git" for entry in entries):
            continue
        low = [entry.name.lower() for entry in entries]
        images = sum(1 for name in low if name.endswith(IMAGES))
        web = any(name.endswith(".wasm") for name in low)
        for entry in entries:
            path = Path(entry.path)
            rel = path.relative_to(topic.path).as_posix()
            with contextlib.suppress(OSError):
                if _stays(entry, limits):
                    continue
                goes = marked or any(fnmatch.fnmatch(rel, g) for g in globs)
                if entry.is_dir():
                    goes = goes or entry.name in limits.can_go_dirs
                    if goes and _free_of_keepers(path, limits):
                        found.append(path)
                    else:
                        stack.append((path, goes))
                elif goes or _is_capture(path, topic.path, images, web, limits, captures):
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
    work_state: WorkState,
    branch_pulls: BranchPulls,
    running: Sequence[tuple[int, str, str]],
    now: float,
    slug_of: SlugOf = lambda folder: "",
    open_names: OpenNames = lambda path: False,
) -> list[Freed]:
    """Delete the downloads and captures of every scratch topic past its work (`topic_finished`, `downloads_in`)."""
    freed: list[Freed] = []
    for topic in scratch_topics(root):
        done, why = topic_finished(
            root,
            topic,
            limits,
            work_state=work_state,
            branch_pulls=branch_pulls,
            running=running,
            now=now,
            slug_of=slug_of,
            open_names=open_names,
        )
        if not done:
            continue
        total, count = 0, 0  # one line per topic: a capture leaves thousands of frames
        for path in downloads_in(topic, limits, captures=not why.startswith(BY_THE_CLOCK)):
            try:
                size = sweep.size_of(path) if path.is_dir() else path.stat().st_size
                if apply:
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
    """Issue and pull request states of the workspace's repositories, asked once per repository per run: lists, not one
    call per number, because the guard runs every five minutes while the disk is low and hundreds of topics name work.
    `gh pr view` is no way to ask about an issue: it fails on an issue's number, and every such topic would stay
    unknown for ever."""

    def __init__(self, root: Path, gh: issues.Gh = issues.run_gh):
        self.root, self.gh = root, gh
        self.by_repo: dict[str, dict[str, list[sweep.Pull]] | None] = {}
        self.numbers: dict[str, dict[int, str] | None] = {}
        self.slugs: dict[str, str] = {}
        self.open_text: str | None = ""
        self.open_read = False

    def slug(self, folder: str) -> str:
        """`owner/repo` of `repos/<folder>`; empty when that is no repository."""
        if folder not in self.slugs:
            checkout = self.root / "repos" / folder
            try:
                self.slugs[folder] = sweep.remote_slug(checkout) if folder and (checkout / ".git").exists() else ""
            except WorktreeError:
                self.slugs[folder] = ""
        return self.slugs[folder]

    def _list(self, kind: str, slug: str, state: str, fields: str) -> list[dict]:
        command = [kind, "list", "--repo", slug, "--state", state, "--limit", str(LIST_LIMIT), "--json", fields]
        rows = json.loads(self.gh(command) or "[]")
        if len(rows) >= LIST_LIMIT:
            raise ValueError(f"{kind} list of {slug} reached its limit of {LIST_LIMIT}")
        return rows

    def _numbers(self, slug: str) -> dict[int, str] | None:
        """Every issue and pull request of a repository; None when GitHub could not be read."""
        key = slug.lower()
        if key not in self.numbers:
            try:
                rows = [row for kind in ("issue", "pr") for row in self._list(kind, slug, "all", "number,state")]
                self.numbers[key] = {int(row["number"]): str(row["state"]).upper() for row in rows}
            except (issues.IssueError, ValueError, KeyError, TypeError):
                self.numbers[key] = None
        return self.numbers[key]

    def _repo(self, folder: str) -> dict[str, list[sweep.Pull]] | None:
        """The pull requests by branch; empty for a group that is no repository; None when GitHub could not be read."""
        if folder not in self.by_repo:
            checkout = self.root / "repos" / folder
            try:
                slug = sweep.remote_slug(checkout) if (checkout / ".git").exists() else ""
                self.by_repo[folder] = sweep.pulls_by_branch(slug, self.gh) if slug else {}
            except (WorktreeError, issues.IssueError, ValueError):
                self.by_repo[folder] = None
        return self.by_repo[folder]

    def branch(self, folder: str, branch: str) -> list[str]:
        """The states of a branch's pull requests; `UNKNOWN` when they could not be read (never "no pull request")."""
        found = self._repo(folder)
        if found is None:
            return ["UNKNOWN"]
        return [p.state for p in found.get(branch, [])]

    def state(self, slug: str, number: int) -> str:
        """OPEN, MERGED or CLOSED; `MISSING` when the repository has no such number, `UNKNOWN` when it was not read."""
        found = self._numbers(slug)
        return "UNKNOWN" if found is None else found.get(number, "MISSING")

    def _open_bodies(self) -> str | None:
        """The bodies of every open issue and pull request of the workspace, lower case; None when one list failed."""
        repos = self.root / "repos"
        names = sorted(p.name for p in repos.iterdir() if (p / ".git").exists()) if repos.is_dir() else []
        bodies = []
        try:
            for slug in filter(None, map(self.slug, names)):
                for kind in ("issue", "pr"):
                    bodies += [str(row.get("body") or "") for row in self._list(kind, slug, "open", "number,body")]
        except (issues.IssueError, ValueError):
            return None
        return "\n".join(bodies).replace("\\", "/").lower()

    def names_topic(self, path: str) -> bool | None:
        """Whether open work names `scratch/<group>/<name>` (`progression`: open issue #1056 pointed at its decisions
        file); None when that could not be read. A longer folder name that starts the same is no match."""
        if not self.open_read:
            self.open_text, self.open_read = self._open_bodies(), True
        if self.open_text is None:
            return None
        return re.search(re.escape(path.lower()) + r"(?![\w.-])", self.open_text) is not None


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
            try:
                running = processes()  # the sweep can take 15 minutes: judge by what runs now
            except WorktreeError as error:
                report.notes.append(f"no scratch freed: {error}")
            else:
                report.freed += clear_scratch(
                    root,
                    limits,
                    apply=apply,
                    work_state=pulls.state,
                    branch_pulls=pulls.branch,
                    running=running,
                    now=clock,
                    slug_of=pulls.slug,
                    open_names=pulls.names_topic,
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
