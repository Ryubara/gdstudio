"""`gds worktree sweep`: remove finished worktrees and keep what is worth keeping (docs/workspace.md#sweep).

Worktrees were removed by hand after a merge, and under load that step was skipped: reviewers' and probes' detached
worktrees had no owner at all, and each one held a Godot import cache of tens to hundreds of MB, until the disk was
at 8 GB free. The sweep does the step for everyone, and is safe to run at any time, by any session, in the
background.

A worktree is **finished** when its branch's pull request merged (or closed), when the issue it was made for closed,
or when nothing has touched it for `idle_hours` and no open pull request or started issue claims it (a reviewer's or
a probe's detached worktree). Finished is not yet removed. A finished worktree is **refused** while a process uses
it, while it has commits that are on no remote branch (and not in the merged pull request), or while its files to
keep cannot be copied. A worktree touched in the last `grace_minutes` is left, because the agent that owns it may be
between two commands. Everything else is **left**.

Before a worktree is removed, every file of it that is changed or untracked and not generated is copied to
`<workspace>/scratch/<repo>/<branch>/kept/`, with a `kept.md` listing it and a `tracked.patch` of the changes to
tracked files: artwork, notes, probes. Generated files (`.godot/`, `*.uid`, `__pycache__/`, import and export
output) are not kept. The report says what was removed, kept, refused and left, and the space freed.
"""

from __future__ import annotations

import contextlib
import fnmatch
import json
import os
import re
import shutil
import stat
import subprocess
import time
from collections.abc import Callable, Iterable, Iterator, Sequence
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from gds_tools import issues
from gds_tools.worktrees import WorktreeError, default_branch

#: Directories whose contents are rebuilt by a tool: never kept.
GENERATED_DIRS = frozenset(
    {
        ".godot",
        ".import",
        ".mono",
        ".gradle",
        "__pycache__",
        "node_modules",
        ".venv",
        "venv",
        ".pytest_cache",
        ".ruff_cache",
        ".mypy_cache",
        "export",
        "exports",
        "build",
        "dist",
    }
)
#: File names (globs) a tool writes: Godot's `.uid` and `.import` files, bytecode, export output, scraps.
GENERATED_FILES = (
    "*.uid",
    "*.import",
    "*.pyc",
    "*.pck",
    "*.exe",
    "*.apk",
    "*.aab",
    "*.wasm",
    "*.tmp",
    ".DS_Store",
    "Thumbs.db",
)
#: GdUnit4's test reports (`reports/report_<n>/`).
GENERATED_REPORT = re.compile(r"(^|/)report_\d+(/|$)")

LEDGER = issues.DEFAULT_LEDGER
SEEN = "cache/worktree-issues.json"  # branch -> issue, remembered after the ledger forgets a closed issue
LOCK = "cache/worktree-sweep.lock"
LOCK_STALE_SECONDS = 1800

GIT_TIMEOUT = 120
#: Windows: a child process of a background job must not open a console window of its own.
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)

Git = Callable[[list[str], Path], str]
Processes = Callable[[], list[tuple[int, str, str]]]


def is_generated(rel: str) -> bool:
    """Whether a repository-relative path is generated output (never kept)."""
    rel = rel.replace("\\", "/").strip("/")
    parts = rel.split("/")
    if any(part in GENERATED_DIRS for part in parts):
        return True
    if GENERATED_REPORT.search(rel):
        return True
    return any(fnmatch.fnmatch(parts[-1], pattern) for pattern in GENERATED_FILES)


def git(args: list[str], cwd: Path) -> str:
    """A git command's output; a failure raises WorktreeError with git's own words."""
    try:
        done = subprocess.run(
            ["git", "--no-optional-locks", *args],  # `git status` must not rewrite the index: it is the activity clock
            cwd=cwd,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdin=subprocess.DEVNULL,
            timeout=GIT_TIMEOUT,
            creationflags=NO_WINDOW,
        )
    except (OSError, subprocess.SubprocessError) as error:
        raise WorktreeError(f"cannot run git {' '.join(args[:2])}: {error}") from error
    if done.returncode != 0:
        raise WorktreeError(f"`git {' '.join(args)}` failed: {(done.stderr or done.stdout).strip()}")
    return done.stdout


def size_of(path: Path, deadline: float | None = None) -> int:
    """The bytes of a folder (links are not followed); 0 for what cannot be read. Stops at `deadline` (time.time())."""
    total, stack = 0, [path]
    while stack:
        if deadline is not None and time.time() > deadline:
            break
        try:
            with os.scandir(stack.pop()) as entries:
                for entry in entries:
                    try:
                        if entry.is_symlink() or entry.is_junction():
                            continue
                        if entry.is_dir():
                            stack.append(Path(entry.path))
                        else:
                            total += entry.stat(follow_symlinks=False).st_size
                    except OSError:
                        continue
        except OSError:
            continue
    return total


def human(size: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} GB"


# --------------------------------------------------------------------------------------------------------------------
# What is running
# --------------------------------------------------------------------------------------------------------------------


def list_processes() -> list[tuple[int, str, str]]:
    """(pid, command line, working directory) of the running processes. The working directory is known on Linux
    only (/proc); on Windows and macOS only the command line is, which is why a worktree touched lately is also left."""
    found: list[tuple[int, str, str]] = []
    if os.name == "nt":
        script = "Get-CimInstance Win32_Process | Select-Object ProcessId,CommandLine | ConvertTo-Json -Compress"
        try:
            done = subprocess.run(
                ["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                stdin=subprocess.DEVNULL,
                timeout=60,
                creationflags=NO_WINDOW,
            )
            rows = json.loads(done.stdout or "[]")
        except (OSError, subprocess.SubprocessError, ValueError) as error:
            raise WorktreeError(f"cannot list the running processes: {error}") from error
        rows = [rows] if isinstance(rows, dict) else rows
        return [(int(r["ProcessId"]), r.get("CommandLine") or "", "") for r in rows if isinstance(r, dict)]
    proc = Path("/proc")
    if proc.is_dir():
        for entry in proc.iterdir():
            if not entry.name.isdigit():
                continue
            try:
                command = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
                cwd = os.readlink(entry / "cwd")
            except OSError:
                continue
            found.append((int(entry.name), command, cwd))
        return found
    try:
        done = subprocess.run(["ps", "-axo", "pid=,args="], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as error:
        raise WorktreeError(f"cannot list the running processes: {error}") from error
    for line in done.stdout.splitlines():
        pid, _, command = line.strip().partition(" ")
        if pid.isdigit():
            found.append((int(pid), command.strip(), ""))
    return found


def _forms(path: Path) -> list[str]:
    """The spellings a command line may use for a folder: lower case, `/` separators, and Git Bash's `/c/...`."""
    text = os.path.normcase(str(path.resolve())).replace("\\", "/").lower().rstrip("/")
    forms = [text]
    if re.match(r"^[a-z]:/", text):
        forms.append("/" + text[0] + text[2:])
    return forms


def users_of(path: Path, processes: Iterable[tuple[int, str, str]]) -> list[tuple[int, str]]:
    """The processes that name the folder in their command line, or have it (or a folder in it) as their working
    directory. A longer folder name that only starts the same (`hud` and `hud-before`) is not a match."""
    forms = _forms(path)
    patterns = [re.compile(re.escape(form) + r"(?![\w.-])") for form in forms]
    used = []
    for pid, command, cwd in processes:
        low = re.sub(r"/+", "/", command.replace("\\", "/").lower())  # `C:\\x` in an escaped command line too
        here = cwd.replace("\\", "/").lower().rstrip("/")
        inside = bool(here) and any(here == form or here.startswith(form + "/") for form in forms)
        if inside or any(p.search(low) for p in patterns):
            used.append((pid, command.strip()[:120]))
    return used


# --------------------------------------------------------------------------------------------------------------------
# One worktree
# --------------------------------------------------------------------------------------------------------------------


@dataclass
class Entry:
    """A worktree of `git worktree list`, directly under `worktrees/<repo>/`."""

    repo: str
    path: Path
    branch: str  # '' when detached
    head: str
    locked: bool

    @property
    def name(self) -> str:
        return self.path.name

    @property
    def label(self) -> str:
        return f"{self.repo}/{self.name}"


@dataclass
class Outcome:
    entry: Entry
    action: str  # removed | would-remove | left | refused
    reason: str
    size: int = 0
    kept: list[str] = field(default_factory=list)
    kept_dir: Path | None = None


@dataclass
class Report:
    outcomes: list[Outcome] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    dry_run: bool = False

    def with_action(self, *actions: str) -> list[Outcome]:
        return [o for o in self.outcomes if o.action in actions]

    @property
    def freed(self) -> int:
        return sum(o.size for o in self.with_action("removed", "would-remove"))

    def lines(self) -> list[str]:
        lines = [*self.notes]
        verb = "would remove" if self.dry_run else "removed"
        for o in self.with_action("removed", "would-remove"):
            keep = f"; {len(o.kept)} file(s) kept in {o.kept_dir.as_posix()}" if o.kept and o.kept_dir else ""
            lines.append(f"{verb:12} {o.entry.label} ({human(o.size)}): {o.reason}{keep}")
        for o in self.with_action("refused"):
            lines.append(f"{'refused':12} {o.entry.label}: {o.reason}")
        for o in self.with_action("left"):
            lines.append(f"{'left':12} {o.entry.label}: {o.reason}")
        done = self.with_action("removed", "would-remove")
        kept = sum(1 for o in done if o.kept)
        gone = (
            f"{len(done)} would be removed ({human(self.freed)} to free)"
            if self.dry_run
            else (f"{len(done)} removed ({human(self.freed)} freed)")
        )
        lines.append(
            f"summary: {gone}, {len(self.with_action('refused'))} refused, {len(self.with_action('left'))} left; "
            f"files kept for {kept} worktree(s)"
        )
        return lines


@dataclass(frozen=True)
class Pull:
    number: int
    state: str  # OPEN | MERGED | CLOSED
    head: str


def listing(checkout: Path, base: Path, run: Git = git) -> list[Entry]:
    """The worktrees of `checkout` whose folder is directly under `base` (`git worktree list`)."""
    entries = []
    out = run(["worktree", "list", "--porcelain"], checkout)
    for block in out.split("\n\n"):
        fields: dict[str, str] = {}
        for line in block.splitlines():
            key, _, value = line.partition(" ")
            fields[key] = value
        if "worktree" not in fields:
            continue
        folder = Path(fields["worktree"]).resolve()
        if not folder.is_dir() or os.path.normcase(str(folder.parent)) != os.path.normcase(str(base.resolve())):
            continue
        branch = fields.get("branch", "").removeprefix("refs/heads/")
        entries.append(Entry(checkout.name, folder, branch, fields.get("HEAD", ""), "locked" in fields))
    return entries


def remote_slug(checkout: Path, run: Git = git) -> str:
    """`owner/repo` of the checkout's origin."""
    url = run(["config", "--get", "remote.origin.url"], checkout).strip()
    found = re.search(r"github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?$", url)
    if not found:
        raise WorktreeError(f"origin of {checkout.name} is not a GitHub repository: {url}")
    return found.group(1)


def pulls_by_branch(slug: str, gh: issues.Gh) -> dict[str, list[Pull]]:
    """Every pull request of the repository by head branch name, oldest first."""
    out = gh(
        [
            "pr",
            "list",
            "--repo",
            slug,
            "--state",
            "all",
            "--limit",
            "1000",
            "--json",
            "number,state,headRefName,headRefOid",
        ]
    )
    found: dict[str, list[Pull]] = {}
    for row in json.loads(out or "[]"):
        found.setdefault(row["headRefName"], []).append(Pull(row["number"], row["state"], row.get("headRefOid", "")))
    for rows in found.values():
        rows.sort(key=lambda p: p.number)
    return found


def changed_files(path: Path, run: Git = git) -> list[tuple[str, str]]:
    """(status, path) of every changed or untracked file: `git status --porcelain=v1 -z --untracked-files=all`."""
    out = run(["status", "--porcelain=v1", "-z", "--untracked-files=all"], path)
    parts, files, i = out.split("\0"), [], 0
    while i < len(parts):
        item = parts[i]
        i += 1
        if len(item) < 4:
            continue
        code, name = item[:2], item[3:]
        if "R" in code or "C" in code:
            i += 1  # the old name follows
        files.append((code, name))
    return files


def last_activity(path: Path, files: Iterable[str], run: Git = git) -> float:
    """The newest change time of the worktree (time.time() scale): git's own files, the changed files, and the folders
    two levels down (a Godot editor or a test run touches `.godot/` and `game/`, which git does not see)."""
    stamps: list[float] = []

    def stamp(target: Path) -> None:
        with contextlib.suppress(OSError):
            stamps.append(target.stat().st_mtime)

    try:
        gitdir = Path(run(["rev-parse", "--absolute-git-dir"], path).strip())
        for name in ("HEAD", "index", "logs/HEAD"):
            stamp(gitdir / name)
    except WorktreeError:
        pass
    stamp(path)
    try:
        with os.scandir(path) as top:
            for child in top:
                if child.name == ".git" or not child.is_dir(follow_symlinks=False):
                    continue
                stamp(Path(child.path))
                with contextlib.suppress(OSError), os.scandir(child.path) as inner:
                    for sub in inner:
                        if sub.is_dir(follow_symlinks=False):
                            stamp(Path(sub.path))
    except OSError:
        pass
    for rel in files:
        stamp(path / rel)
    return max(stamps, default=0.0)


def concerns(entry: Entry, pull: Pull, run: Git = git) -> bool:
    """Whether a pull request of the branch's name is about the work in this worktree. A branch name is used again
    after its pull request merged and GitHub deleted it: a new worktree of that name has nothing to do with the old
    pull request unless the worktree holds its commits (the pull request head is the worktree head or an ancestor of
    it). An open pull request always counts."""
    if pull.state == "OPEN" or (pull.head and pull.head == entry.head):
        return True
    if not pull.head:
        return False
    try:
        run(["cat-file", "-e", f"{pull.head}^{{commit}}"], entry.path)
    except WorktreeError:
        return False
    try:  # the worktree holds the pull request's commits (a clean worktree of an older main does not)
        run(["merge-base", "--is-ancestor", pull.head, "HEAD"], entry.path)
        return True
    except WorktreeError:
        return False


def unpushed(entry: Entry, pulls: Sequence[Pull], run: Git = git) -> int:
    """How many commits of the worktree are on no remote branch and not in a merged pull request."""
    merged = []
    for pull in pulls:
        if pull.state != "MERGED" or not pull.head:
            continue
        if pull.head == entry.head:
            return 0
        try:  # the last commit GitHub merged counts as pushed when this clone has it
            run(["cat-file", "-e", f"{pull.head}^{{commit}}"], entry.path)
            merged.append(pull.head)
        except WorktreeError:
            continue
    out = run(["rev-list", "--count", "HEAD", "--not", "--remotes", *merged], entry.path)
    return int(out.strip() or 0)


# --------------------------------------------------------------------------------------------------------------------
# What is kept
# --------------------------------------------------------------------------------------------------------------------


def _walk_files(root: Path, rel: str) -> Iterator[str]:
    """The files a status entry names: the file itself, or those of a folder git lists whole (a nested repository)."""
    target = root / rel
    if target.is_dir():
        for folder, dirs, names in os.walk(target):
            dirs[:] = [d for d in dirs if d != ".git"]
            for name in names:
                yield (Path(folder) / name).relative_to(root).as_posix()
    elif target.is_file():
        yield rel


def files_to_keep(entry: Entry, status: Sequence[tuple[str, str]]) -> tuple[list[str], int, list[str]]:
    """(files to copy, number of generated files skipped, tracked files deleted) from the status entries."""
    keep: list[str] = []
    skipped, deleted = 0, []
    for code, name in status:
        if "D" in code and not (entry.path / name).exists():
            deleted.append(name)
            continue
        for rel in _walk_files(entry.path, name.rstrip("/")):
            if is_generated(rel):
                skipped += 1
            else:
                keep.append(rel)
    return sorted(set(keep)), skipped, sorted(deleted)


def keep_folder(root: Path, entry: Entry) -> Path:
    """`<workspace>/scratch/<repo>/<branch>/kept`, numbered when an earlier sweep already used the name."""
    name = (entry.branch or entry.name).replace("/", "-")
    base = root / "scratch" / entry.repo / name
    target = base / "kept"
    number = 2
    while target.exists() and any(target.iterdir()):
        target = base / f"kept-{number}"
        number += 1
    return target


def copy_kept(
    root: Path, entry: Entry, keep: Sequence[str], skipped: int, deleted: Sequence[str], why: str, run: Git = git
) -> Path:
    """Copy the files to keep, a patch of the tracked changes, and `kept.md` to the keep folder; returns the folder."""
    target = keep_folder(root, entry)
    target.mkdir(parents=True, exist_ok=True)
    for rel in keep:
        destination = target / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(entry.path / rel, destination)
    patch = ""
    with contextlib.suppress(WorktreeError):
        patch = run(["diff", "HEAD"], entry.path)
    if patch.strip():
        (target / "tracked.patch").write_text(patch, encoding="utf-8", newline="\n")
    lines = [
        f"# Kept from {entry.label}",
        "",
        f"Swept {datetime.now().astimezone():%Y-%m-%d %H:%M}: {why}. Branch `{entry.branch or '(detached)'}`, "
        f"commit `{entry.head[:9]}`, folder `{entry.path.as_posix()}`.",
        "",
        "Files copied, with the folder layout of the worktree:",
        "",
        *[f"- `{rel}` ({human((target / rel).stat().st_size)})" for rel in keep],
    ]
    if patch.strip():
        lines += [
            "",
            "`tracked.patch` is `git diff HEAD`: the changes to tracked files (text; binary files are copied).",
        ]
    if deleted:
        lines += ["", "Tracked files deleted in the worktree (not copied):", "", *[f"- `{rel}`" for rel in deleted]]
    if skipped:
        lines += [
            "",
            f"{skipped} generated file(s) (`.godot/`, `*.uid`, caches, import and export output) were not kept.",
        ]
    (target / "kept.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return target


def remove_tree(checkout: Path, entry: Entry, run: Git = git) -> None:
    """`git worktree remove --force`, then the leftovers (a path git cannot delete on Windows) and the local branch."""
    try:
        run(["worktree", "remove", "--force", str(entry.path)], checkout)
    except WorktreeError as error:
        if not entry.path.exists():
            with contextlib.suppress(WorktreeError):
                run(["worktree", "prune"], checkout)
        else:

            def writable(function, target, _info):  # a read-only file (git objects, Windows) blocks the delete
                os.chmod(target, stat.S_IWRITE)
                function(target)

            shutil.rmtree(entry.path, onerror=writable)
            if entry.path.exists():
                raise WorktreeError(f"{entry.path} cannot be deleted: {error}") from error
            with contextlib.suppress(WorktreeError):
                run(["worktree", "prune"], checkout)
    if entry.branch:
        with contextlib.suppress(WorktreeError):
            run(["branch", "-D", entry.branch], checkout)


# --------------------------------------------------------------------------------------------------------------------
# Which worktrees are finished
# --------------------------------------------------------------------------------------------------------------------


@dataclass
class Settings:
    idle_hours: float = 6.0
    use_idle: bool = True
    grace_minutes: float = 30.0
    max_keep_bytes: int = 1024 * 1024 * 1024


@dataclass
class Claims:
    """The started issues, by (repo slug, branch): the ledger's, plus what earlier sweeps remembered of it."""

    by_branch: dict[tuple[str, str], int]
    gh: issues.Gh
    states: dict[tuple[str, int], str] = field(default_factory=dict)

    def issue(self, slug: str, branch: str) -> int | None:
        return self.by_branch.get((slug.lower(), branch))

    def state(self, slug: str, number: int) -> str:
        """OPEN or CLOSED; OPEN when GitHub does not say (an unreachable GitHub never closes an issue)."""
        key = (slug.lower(), number)
        if key not in self.states:
            try:
                row = json.loads(self.gh(["issue", "view", str(number), "--repo", slug, "--json", "state"]))
                self.states[key] = str(row.get("state", "OPEN")).upper()
            except (issues.IssueError, ValueError):
                self.states[key] = "OPEN"
        return self.states[key]


def load_claims(root: Path, gh: issues.Gh) -> Claims:
    """The ledger's issue-to-branch entries merged into `cache/worktree-issues.json`, which outlives the ledger's
    pruning of a closed issue (a branch of a closed issue is exactly what the sweep must still find)."""
    seen_file = root / SEEN
    seen: dict[str, int] = {}
    with contextlib.suppress(OSError, ValueError):
        data = json.loads(seen_file.read_text(encoding="utf-8"))
        seen = {k: int(v) for k, v in data.items()} if isinstance(data, dict) else {}
    for entry in issues.load_ledger(root / LEDGER).values():
        branch, repo, number = entry.get("branch"), entry.get("repo"), entry.get("number")
        if branch and repo and isinstance(number, int):
            seen[f"{repo.lower()}:{branch}"] = number
    with contextlib.suppress(OSError):
        seen_file.parent.mkdir(parents=True, exist_ok=True)
        seen_file.write_text(json.dumps(seen, indent=1, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    by_branch = {(k.rsplit(":", 1)[0], k.rsplit(":", 1)[1]): v for k, v in seen.items() if ":" in k}
    return Claims(by_branch, gh)


def decide(
    entry: Entry,
    *,
    default: str,
    pulls: Sequence[Pull] | None,
    claims: Claims,
    slug: str,
    idle_seconds: float,
    settings: Settings,
) -> tuple[str, str]:
    """("finished", why) or ("left", why): is the work of this worktree done? `pulls` is None when GitHub could not
    be asked: then only a detached worktree (which has no pull request) can be finished."""
    if entry.branch and entry.branch == default:
        return "left", f"{default} is checked out here"
    if entry.locked:
        return "left", "locked (git worktree lock)"
    idle_text = f"nothing touched it for {idle_seconds / 3600:.1f} h"
    if entry.branch:
        if pulls is None:
            return "left", "GitHub could not be asked about its pull request"
        issue = claims.issue(slug, entry.branch)
        opened = [p for p in pulls if p.state == "OPEN"]
        if opened:
            return "left", f"pull request #{opened[0].number} is open"
        merged = [p for p in pulls if p.state == "MERGED"]
        closed = [p for p in pulls if p.state == "CLOSED"]
        issue_open = bool(issue) and claims.state(slug, issue) == "OPEN"
        if merged and issue_open:
            # A started issue that is still open may go on in this worktree (a second pull request, a branch name
            # that was used again): wait for the idle time, not just the grace.
            if settings.use_idle and idle_seconds >= settings.idle_hours * 3600:
                return "finished", f"pull request #{merged[-1].number} merged, issue #{issue} open, {idle_text}"
            return "left", f"pull request #{merged[-1].number} merged, but issue #{issue} is still in progress"
        if merged:
            return "finished", f"pull request #{merged[-1].number} merged"
        if issue_open:
            return "left", f"issue #{issue} is in progress"
        if closed:
            return "finished", f"pull request #{closed[-1].number} closed"
        if issue:
            return "finished", f"issue #{issue} closed"
        why_not = "no pull request yet"
    else:
        why_not = "detached"
    if not settings.use_idle:
        return "left", f"{why_not}; the idle rule is off"
    if idle_seconds >= settings.idle_hours * 3600:
        return "finished", f"{why_not}, {idle_text}"
    return "left", f"{why_not}; touched {idle_seconds / 3600:.1f} h ago (idle rule: {settings.idle_hours:g} h)"


# --------------------------------------------------------------------------------------------------------------------
# The sweep
# --------------------------------------------------------------------------------------------------------------------


class Locked(Exception):
    """Another sweep is running."""


@contextlib.contextmanager
def lock(root: Path):
    """One sweep at a time: an exclusive lock file, taken over when it is older than half an hour (a killed sweep)."""
    path = root / LOCK
    path.parent.mkdir(parents=True, exist_ok=True)
    for _ in range(2):
        try:
            handle = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        except FileExistsError:
            try:
                age = time.time() - path.stat().st_mtime
            except OSError:
                continue
            if age < LOCK_STALE_SECONDS:
                raise Locked(f"another sweep is running ({path})") from None
            with contextlib.suppress(OSError):
                path.unlink()
            continue
        os.write(handle, str(os.getpid()).encode())
        os.close(handle)
        break
    else:
        raise Locked(f"cannot take {path}")
    try:
        yield
    finally:
        with contextlib.suppress(OSError):
            path.unlink()


def sweep(
    root: Path,
    *,
    apply: bool = True,
    settings: Settings | None = None,
    only: Sequence[str] = (),
    repos: Sequence[str] = (),
    run: Git = git,
    gh: issues.Gh = issues.run_gh,
    processes: Processes = list_processes,
    now: float | None = None,
    deadline_seconds: float | None = None,
) -> Report:
    """Sweep every worktree under `<root>/worktrees/<repo>/` of the repositories in `<root>/repos/`.

    `apply=False` is a dry run: nothing is copied, removed or fetched into the checkouts' working trees (a `git fetch`
    only refreshes the remote-tracking branches the unpushed-commit check reads). `only` limits it to worktree folder
    names, `repos` to repository names."""
    settings = settings or Settings()
    started = time.time()
    clock = now if now is not None else started
    report = Report(dry_run=not apply)
    try:
        running = processes()
    except WorktreeError as error:
        report.notes.append(f"nothing swept: {error}")
        return report
    claims = load_claims(root, gh)
    base = root / "worktrees"
    repos_dir = root / "repos"
    for checkout in sorted(p for p in repos_dir.iterdir() if (p / ".git").exists()) if repos_dir.is_dir() else []:
        if repos and checkout.name not in repos:
            continue
        folder = base / checkout.name
        if not folder.is_dir():
            continue
        try:
            entries = listing(checkout, folder, run)
        except WorktreeError as error:
            report.notes.append(f"{checkout.name}: worktrees not listed ({error})")
            continue
        entries = [e for e in entries if not only or e.name in only]
        if not entries:
            continue
        if apply:
            with contextlib.suppress(WorktreeError):
                run(["worktree", "prune"], checkout)
        with contextlib.suppress(WorktreeError):
            run(["fetch", "--quiet", "origin"], entries[0].path)
        try:
            slug = remote_slug(checkout, run)
            pulls = pulls_by_branch(slug, gh)
        except (WorktreeError, issues.IssueError, ValueError) as error:
            report.notes.append(
                f"{checkout.name}: pull requests unknown ({error}); only detached worktrees can be swept"
            )
            slug, pulls = "", None
        default = default_branch(checkout, run)
        for entry in entries:
            if deadline_seconds is not None and time.time() - started > deadline_seconds:
                report.notes.append("deadline reached: the rest waits for the next sweep")
                return report
            report.outcomes.append(
                _one(root, checkout, entry, apply, settings, run, running, pulls, claims, slug, default, clock)
            )
    return report


def _one(
    root: Path,
    checkout: Path,
    entry: Entry,
    apply: bool,
    settings: Settings,
    run: Git,
    running: list[tuple[int, str, str]],
    pulls_by_name: dict[str, list[Pull]] | None,
    claims: Claims,
    slug: str,
    default: str,
    clock: float,
) -> Outcome:
    pulls = None
    if pulls_by_name is not None:
        pulls = [p for p in pulls_by_name.get(entry.branch, []) if concerns(entry, p, run)]
    try:
        status = changed_files(entry.path, run)
        idle = max(0.0, clock - last_activity(entry.path, [name for _, name in status], run))
    except WorktreeError as error:
        return Outcome(entry, "left", f"cannot read its state ({error})")
    verdict, why = decide(
        entry, default=default, pulls=pulls, claims=claims, slug=slug, idle_seconds=idle, settings=settings
    )
    if verdict != "finished":
        return Outcome(entry, "left", why)
    if idle < settings.grace_minutes * 60:
        return Outcome(
            entry, "left", f"{why}, but touched {idle / 60:.0f} min ago (grace {settings.grace_minutes:g} min)"
        )
    used = users_of(entry.path, running)
    if used:
        pid, command = used[0]
        return Outcome(entry, "refused", f"{why}, but process {pid} uses it: {command}")
    try:
        ahead = unpushed(entry, pulls or [], run)
    except (WorktreeError, ValueError) as error:
        return Outcome(entry, "refused", f"{why}, but its commits cannot be checked ({error})")
    if ahead:
        return Outcome(
            entry, "refused", f"{why}, but {ahead} commit(s) are on no remote branch and in no merged pull request"
        )
    keep, skipped, deleted = files_to_keep(entry, status)
    kept_bytes = sum((entry.path / rel).stat().st_size for rel in keep if (entry.path / rel).exists())
    if kept_bytes > settings.max_keep_bytes:
        return Outcome(
            entry,
            "refused",
            f"{why}, but {human(kept_bytes)} of files to keep is over the limit of {human(settings.max_keep_bytes)}: "
            "copy them by hand, or raise --max-keep-mb",
        )
    size = size_of(entry.path)
    if not apply:
        return Outcome(entry, "would-remove", why, size, keep, keep_folder(root, entry) if keep else None)
    kept_dir = None
    try:
        if keep or deleted:
            kept_dir = copy_kept(root, entry, keep, skipped, deleted, why, run)
        remove_tree(checkout, entry, run)
    except (OSError, WorktreeError) as error:
        return Outcome(entry, "refused", f"{why}, but it could not be removed ({error})", 0, keep, kept_dir)
    return Outcome(entry, "removed", why, size, keep, kept_dir)


# --------------------------------------------------------------------------------------------------------------------
# Disk space (gds doctor)
# --------------------------------------------------------------------------------------------------------------------

LOW_DISK_GB = 20
#: A file with this name in a scratch folder protects the folder from every clean-up: the store and branding assets
#: (Steam, itch.io and Discord: the app icon and key art) are kept this way.
KEEP_MARKER = ".keep"


def protected(path: Path) -> bool:
    """Whether the folder (or a folder above it, inside `scratch/`) holds a `.keep` marker. Nothing in the kit deletes
    from `scratch/`; a clean-up anyone writes (the sweep, a script, an agent) must skip what this says is protected."""
    for folder in (path, *path.parents):
        if (folder / KEEP_MARKER).is_file():
            return True
        if folder.name == "scratch":
            break
    return False


def disk_lines(root: Path, *, warn_gb: float = LOW_DISK_GB, top: int = 5, seconds: float = 90) -> list[str]:
    """Free space of the workspace's disk, and when it is under `warn_gb`, the biggest worktrees and scratch folders."""
    free = shutil.disk_usage(root).free
    gb = free / 1024**3
    if gb >= warn_gb:
        return [f"  ok      disk: {gb:.1f} GB free"]
    lines = [
        f"  WARNING disk: {gb:.1f} GB free, under {warn_gb:g} GB. Finished worktrees are removed by "
        "`gds worktree sweep` (docs/workspace.md#sweep); the biggest folders:"
    ]
    deadline = time.time() + seconds
    sizes: list[tuple[int, Path]] = []
    for group in (root / "worktrees", root / "scratch"):
        if not group.is_dir():
            continue
        for first in (p for p in group.iterdir() if p.is_dir() and not p.is_symlink()):
            for second in first.iterdir():
                sizes.append((size_of(second, deadline) if second.is_dir() else second.stat().st_size, second))
    sizes.sort(key=lambda item: item[0], reverse=True)
    for size, path in sizes[:top]:
        note = "  (protected by .keep: do not delete)" if protected(path) else ""
        lines.append(f"            {human(size):>9}  {path.relative_to(root).as_posix()}{note}")
    if time.time() > deadline:
        lines.append("            (sizes are partial: the measurement stopped after a time limit)")
    return lines
