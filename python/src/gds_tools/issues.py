"""`gds issue`: issues are started oldest first, through one tool (docs/starting-work.md).

Only the oldest open issues that nobody works on may be started: the window. An issue is out of the line when it is
`S-in-progress`, `S-pending-review`, `S-blocked` or `S-needs-info`, or when an open pull request closes it (a pull
request that exists is in progress, so it never needs a label of its own). `P-critical` issues go first, oldest first
among them; the maintainer alone sets that label. "Oldest" is the lowest issue number.

A blocked issue says why: `block` writes the label and a `Blocked (<who>, <date>): waits on #N ...` line in the body,
`unblock` lifts both, and `list` shows the reason and which blocks outlived their cause (`parse_block`). The
coordinator's Stop hook (`.claude/hooks/guards.py`, `stop_idle`) loads this module by path to find the issues that may
start and have no agent, so it stays standard library only.

`start` checks the window, labels and assigns the issue, comments, and writes the start to a ledger in
`<workspace>/cache/issues-started.json`; the hook (`.claude/hooks/guards.py`) refuses to start a task agent whose
prompt does not name an issue in that ledger. Every `gh` call goes through a runner that tests replace with recorded
JSON, so nothing here needs the network to be tested.
"""

from __future__ import annotations

import contextlib
import json
import os
import re
import subprocess
import tomllib
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from pathlib import Path

IN_PROGRESS = "S-in-progress"
READY = "S-ready-to-start"
TRIAGE = "S-needs-triage"
BLOCKED = "S-blocked"
NEEDS_INFO = "S-needs-info"
PENDING_REVIEW = "S-pending-review"
CRITICAL = "P-critical"
DEFAULT_WINDOW = 5
DEFAULT_LEDGER = "cache/issues-started.json"
#: The hook's cache of `gh` reads, beside the ledger; every command that changes an issue removes it.
IDLE_CACHE = "idle-check.json"
MAINTAINER = "maintainer"

#: Labels that take an issue out of the line (somebody is on it, or it cannot start).
BUSY_LABELS = (IN_PROGRESS, PENDING_REVIEW)

Gh = Callable[[list[str]], str]

_REF = re.compile(r"^(?:(?P<repo>[\w.-]+/[\w.-]+))?#?(?P<number>\d+)$")
_CLOSES = re.compile(
    r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s+(?:https://github\.com/)?((?:[\w.-]+/[\w.-]+)?)(?:#|/issues/)(\d+)",
    re.IGNORECASE,
)


class IssueError(Exception):
    """An issue command that cannot run, or a start the rules refuse."""


@dataclass
class Prepared:
    """The work made ready for an issue before the agent gets it: a branch in its own worktree (gds_tools.worktrees).
    `undo` takes it away again when the rest of the start fails."""

    branch: str
    path: str
    lines: list[str]
    undo: Callable[[], None]


# --------------------------------------------------------------------------------------------------------------------
# References, settings, the gh runner
# --------------------------------------------------------------------------------------------------------------------


def parse_ref(text: str, default_repo: str | None = None) -> tuple[str, int]:
    """`owner/repo#N` (or `owner/repo/N`, `#N`, `N` with a default repository) as (repository, number)."""
    found = _REF.match(text.strip().replace("/issues/", "#"))
    if not found:
        raise IssueError(f"{text!r} is not an issue: write it as owner/repo#N")
    repo = found.group("repo") or default_repo
    if not repo:
        raise IssueError(f"{text!r} names no repository: write owner/repo#N")
    return repo, int(found.group("number"))


def ledger_key(repo: str, number: int) -> str:
    """The ledger's key for an issue; the hook builds the same one from a prompt's `Issue:` line."""
    return f"{repo}#{number}".lower()


def run_gh(args: list[str]) -> str:
    """The real runner: `gh <args>`, its output; IssueError when it fails."""
    try:
        done = subprocess.run(["gh", *args], capture_output=True, text=True, encoding="utf-8", timeout=120)
    except (OSError, subprocess.SubprocessError) as error:
        raise IssueError(f"gh could not run: {error}") from error
    if done.returncode != 0:
        raise IssueError(f"gh {' '.join(args[:3])} failed: {done.stderr.strip() or done.stdout.strip()}")
    return done.stdout


@dataclass(frozen=True)
class Settings:
    """`[issues]` of the kit's hooks.toml, replaced key by key by a game's `.claude/hooks.local.toml`."""

    window: int = DEFAULT_WINDOW
    ledger: str = DEFAULT_LEDGER


def load_settings(kit: Path | None, game: Path | None = None) -> Settings:
    """The window size and ledger path: the kit's defaults, then the game's own overrides (hooks.local.toml)."""
    values: dict = {}
    files = [kit / ".claude" / "hooks" / "hooks.toml" if kit else None]
    files.append(game / ".claude" / "hooks.local.toml" if game else None)
    for path in files:
        if path and path.is_file():
            values.update(tomllib.loads(path.read_text(encoding="utf-8")).get("issues", {}))
    window = int(values.get("window", DEFAULT_WINDOW))
    if window < 1:
        raise IssueError(f"[issues] window must be at least 1, not {window}")
    return Settings(window=window, ledger=str(values.get("ledger", DEFAULT_LEDGER)))


# --------------------------------------------------------------------------------------------------------------------
# The window
# --------------------------------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Issue:
    number: int
    title: str
    labels: frozenset[str]
    assignees: tuple[str, ...] = ()
    body: str = ""

    @classmethod
    def from_json(cls, data: dict) -> Issue:
        return cls(
            number=int(data["number"]),
            title=data.get("title", ""),
            labels=frozenset(label["name"] for label in data.get("labels", [])),
            assignees=tuple(a["login"] for a in data.get("assignees", [])),
            body=data.get("body") or "",
        )


@dataclass(frozen=True)
class PullRequest:
    number: int
    title: str
    labels: frozenset[str]
    closes: frozenset[int]  # issues of the same repository that merging it closes

    @classmethod
    def from_json(cls, repo: str, data: dict) -> PullRequest:
        """A pull request from `gh pr list --json number,title,body,labels,closingIssuesReferences`: the issues it
        closes are GitHub's own list plus any `Fixes #N` / `Closes #N` / `Resolves #N` in the body."""
        closes = set()
        for ref in data.get("closingIssuesReferences") or []:
            owner = (ref.get("repository") or {}).get("owner", {}).get("login", "")
            name = (ref.get("repository") or {}).get("name", "")
            if not owner or f"{owner}/{name}".lower() == repo.lower():
                closes.add(int(ref["number"]))
        for other, number in _CLOSES.findall(data.get("body") or ""):
            if not other or other.lower() == repo.lower():
                closes.add(int(number))
        return cls(
            number=int(data["number"]),
            title=data.get("title", ""),
            labels=frozenset(label["name"] for label in data.get("labels", [])),
            closes=frozenset(closes),
        )


# --------------------------------------------------------------------------------------------------------------------
# Blocks: the label, and the reason in the body
# --------------------------------------------------------------------------------------------------------------------

# `Blocked (coordinator, 2026-11-02): waits on #227 (the bot issues) ...` or `... waits on the maintainer: ...`, on a
# line of its own in the issue body. `gds issue block` writes it; the coordinator wrote it by hand before it existed.
_BLOCK_LINE = re.compile(r"(?im)^[ \t>*_-]*Blocked[ \t]*\(([^)\n]*)\)[ \t]*:[ \t]*(.*?)[ \t]*$")
_WAITS_ON = re.compile(r"(?i)^waits?\s+on\s+(.*)$")
_CLAUSE_END = re.compile(r"[:;(]| [-–—] |\.\s")
_BLOCKER = re.compile(r"(?<![\w/])((?:[\w.-]+/[\w.-]+)?)#(\d+)")


@dataclass(frozen=True)
class Block:
    """The reason an issue is blocked, from its body."""

    who: str
    date: str
    reason: str  # the text after the colon
    maintainer: bool  # it waits on the maintainer: no closed issue lifts that
    waits_on: tuple[tuple[str, int], ...]  # (repository or "" for the same one, number) of the issues it waits on

    def lifted(self, repo: str, open_numbers: set[int]) -> bool:
        """True when every issue it waits on is in this repository and closed. A block on the maintainer, on no
        recognisable issue, or on an issue of another repository (not known here) is never lifted by this."""
        if self.maintainer or not self.waits_on:
            return False
        return all(not other or other.lower() == repo.lower() for other, _ in self.waits_on) and not any(
            number in open_numbers for _, number in self.waits_on
        )

    def line(self) -> str:
        return f"Blocked ({self.who}, {self.date}): {self.reason}"


def parse_block(body: str) -> Block | None:
    """The last `Blocked (<who>, <date>): waits on ...` line of an issue body, or None when it has none."""
    found = _BLOCK_LINE.findall(body or "")
    if not found:
        return None
    meta, reason = found[-1]
    who, _, date = (part.strip() for part in meta.partition(","))
    wait = _WAITS_ON.match(reason.strip())
    after = wait.group(1) if wait else ""
    maintainer = bool(re.match(r"(?i)(the\s+)?maintainers?\b", after))
    clause = after[: m.start()] if (m := _CLAUSE_END.search(after)) else after
    refs = () if maintainer else tuple((repo, int(number)) for repo, number in _BLOCKER.findall(clause))
    return Block(who=who, date=date, reason=reason.strip(), maintainer=maintainer, waits_on=refs)


def without_blocks(body: str) -> str:
    """The body without its `Blocked (...)` lines, trailing blank lines dropped."""
    kept = [line for line in (body or "").replace("\r\n", "\n").split("\n") if not _BLOCK_LINE.match(line)]
    return "\n".join(kept).rstrip()


@dataclass(frozen=True)
class Progress:
    """An issue somebody is working on, and how we know: its label, an open pull request, or both."""

    issue: Issue
    labelled: bool
    pull_requests: tuple[int, ...] = ()


@dataclass
class Window:
    repo: str
    size: int
    allowed: list[Issue] = field(default_factory=list)  # may start now, in the order to take them
    later: list[Issue] = field(default_factory=list)  # ready, but behind the window
    in_progress: list[Progress] = field(default_factory=list)
    blocked: list[Issue] = field(default_factory=list)
    blocks: dict[int, Block] = field(default_factory=dict)  # the reason of each blocked issue that gives one
    unblocked: list[Issue] = field(default_factory=list)  # blocked, but everything it waits on has closed
    waiting: list[Issue] = field(default_factory=list)
    by_number: dict[int, Issue] = field(default_factory=dict)

    def allows(self, number: int) -> bool:
        return any(issue.number == number for issue in self.allowed)

    def why_not(self, number: int) -> str:
        """Why an issue may not start, in a sentence."""
        if number not in self.by_number:
            return "is not an open issue of this repository"
        for item in self.in_progress:
            if item.issue.number == number:
                how = [f"has the {IN_PROGRESS} label"] if IN_PROGRESS in item.issue.labels else []
                if PENDING_REVIEW in item.issue.labels:
                    how.append(f"has the {PENDING_REVIEW} label")
                how += [f"is closed by the open pull request #{pr}" for pr in item.pull_requests]
                return "is already in progress (" + "; ".join(how) + ")"
        if any(i.number == number for i in self.blocked):
            return f"is {BLOCKED}"
        if any(i.number == number for i in self.waiting):
            return f"is {NEEDS_INFO}"
        ahead = [i for i in self.allowed + self.later if i.number == number]
        rank = (self.allowed + self.later).index(ahead[0]) + 1
        return f"is number {rank} in the line, and only the first {self.size} may start"


def compute_window(repo: str, issues: list[Issue], prs: list[PullRequest], size: int = DEFAULT_WINDOW) -> Window:
    """Who may start: the `size` oldest open issues nobody works on, `P-critical` ones first (oldest first among them).

    Out of the line: `S-in-progress`, `S-pending-review`, an open pull request that closes the issue, `S-blocked`,
    `S-needs-info`. A pull request needs no label of its own: it exists, so its issues are in progress."""
    window = Window(repo=repo, size=size, by_number={i.number: i for i in issues})
    open_numbers = set(window.by_number) | {pr.number for pr in prs}  # an issue may wait on a pull request
    closing: dict[int, list[int]] = {}
    for pr in sorted(prs, key=lambda p: p.number):
        for number in pr.closes:
            closing.setdefault(number, []).append(pr.number)
    line: list[Issue] = []
    for issue in sorted(issues, key=lambda i: i.number):
        labelled = bool(issue.labels & set(BUSY_LABELS))
        if labelled or issue.number in closing:
            window.in_progress.append(Progress(issue, labelled, tuple(closing.get(issue.number, ()))))
        elif BLOCKED in issue.labels:
            window.blocked.append(issue)
            block = parse_block(issue.body)
            if block:
                window.blocks[issue.number] = block
                if block.lifted(repo, open_numbers):
                    window.unblocked.append(issue)
        elif NEEDS_INFO in issue.labels:
            window.waiting.append(issue)
        else:
            line.append(issue)
    line.sort(key=lambda i: (CRITICAL not in i.labels, i.number))
    window.allowed, window.later = line[:size], line[size:]
    return window


def refusal(repo: str, number: int, window: Window) -> str:
    """The message of a refused start: why, and the issues that may start instead."""
    lines = [f"{repo}#{number} cannot start: it {window.why_not(number)}."]
    if window.allowed:
        lines.append("Issues start oldest first. Start one of these (P-critical first, then the oldest):")
        lines += [
            f"  #{i.number}  {i.title}" + (f"  [{CRITICAL}]" if CRITICAL in i.labels else "") for i in window.allowed
        ]
        lines.append("`gds issue list` shows the whole line. Only the maintainer sets P-critical.")
    else:
        lines.append("No issue is ready to start.")
    return "\n".join(lines)


def fetch(repo: str, gh: Gh) -> tuple[list[Issue], list[PullRequest]]:
    """The open issues and open pull requests of a repository, from `gh` (pull requests are not in `gh issue list`)."""
    issues = json.loads(
        gh(
            [
                "issue",
                "list",
                "-R",
                repo,
                "--state",
                "open",
                "--limit",
                "1000",
                "--json",
                "number,title,labels,assignees,body",
            ]
        )
        or "[]"
    )
    prs = json.loads(
        gh(
            [
                "pr",
                "list",
                "-R",
                repo,
                "--state",
                "open",
                "--limit",
                "1000",
                "--json",
                "number,title,body,labels,closingIssuesReferences",
            ]
        )
        or "[]"
    )
    return [Issue.from_json(i) for i in issues], [PullRequest.from_json(repo, p) for p in prs]


# --------------------------------------------------------------------------------------------------------------------
# The ledger: who started what (read by the hook)
# --------------------------------------------------------------------------------------------------------------------


def load_ledger(path: Path) -> dict[str, dict]:
    """The started issues by ledger key; an empty ledger when the file is missing or unreadable."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    started = data.get("started", {}) if isinstance(data, dict) else {}
    return started if isinstance(started, dict) else {}


def save_ledger(path: Path, started: dict[str, dict]) -> None:
    """Write the ledger in one replace, so a reader never sees half a file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    temp.write_text(json.dumps({"started": started}, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    os.replace(temp, path)


def prune_ledger(started: dict[str, dict], repo: str, open_numbers: set[int]) -> list[str]:
    """Drop the entries of `repo` whose issue is no longer open (merging a `Fixes` pull request closed it)."""
    gone = [
        k
        for k, e in started.items()
        if e.get("repo", "").lower() == repo.lower() and e.get("number") not in open_numbers
    ]
    for key in gone:
        del started[key]
    return gone


# --------------------------------------------------------------------------------------------------------------------
# The commands
# --------------------------------------------------------------------------------------------------------------------


def start(
    repo: str,
    number: int,
    agent: str,
    *,
    gh: Gh,
    ledger: Path,
    size: int = DEFAULT_WINDOW,
    branch: str = "",
    now: datetime | None = None,
    areas_for: Callable[[frozenset[str]], list[str]] | None = None,
    prepare: Callable[[Issue], Prepared] | None = None,
) -> list[str]:
    """Start an issue if it is in the window: make its branch and worktree, label, assign, comment, ledger. Returns the
    lines to print. `areas_for` maps the issue's labels to the areas of the mistakes glossary, which the ledger keeps
    for the SubagentStart hook. `prepare` makes the branch and worktree after the window allows the start and before
    anything on GitHub changes, so a worktree that cannot be made leaves the issue where it was."""
    issues, prs = fetch(repo, gh)
    window = compute_window(repo, issues, prs, size)
    started = load_ledger(ledger)
    if prune_ledger(started, repo, {i.number for i in issues}):
        save_ledger(ledger, started)
    if not window.allows(number):
        raise IssueError(refusal(repo, number, window))
    issue = window.by_number[number]
    prepared = prepare(issue) if prepare else None
    try:
        edit = ["issue", "edit", str(number), "-R", repo, "--add-label", IN_PROGRESS, "--add-assignee", "@me"]
        for label in (READY, TRIAGE):
            if label in issue.labels:
                edit += ["--remove-label", label]
        gh(edit)
        gh(["issue", "comment", str(number), "-R", repo, "--body", f"Started by agent {agent}"])
        areas = areas_for(issue.labels) if areas_for else []
        started = load_ledger(ledger)
        started[ledger_key(repo, number)] = {
            "repo": repo,
            "number": number,
            "issue": f"{repo}#{number}",
            "agent": agent,
            "time": (now or datetime.now(UTC)).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "branch": prepared.branch if prepared else branch,
            "areas": areas,
            **({"worktree": prepared.path} if prepared else {}),
        }
        save_ledger(ledger, started)
        forget_reads(ledger)
    except BaseException:
        if prepared:
            prepared.undo()
        raise
    return [
        f"started {repo}#{number} ({issue.title}) for agent {agent}",
        *([f"areas: {', '.join(areas)} (their checks are put into the agent's context at start)"] if areas else []),
        *(prepared.lines if prepared else []),
        "Put these lines in the agent's prompt (the hook looks for the first):"
        if prepared
        else "Put this line in the agent's prompt (the hook looks for it):",
        *([f"Worktree: {prepared.path}"] if prepared else []),
        f"Issue: {repo}#{number}",
    ]


def release(repo: str, number: int, *, gh: Gh, ledger: Path, agent: str = "") -> list[str]:
    """Put an issue back in the line (work stopped): `S-ready-to-start`, unassigned, out of the ledger."""
    issues, prs = fetch(repo, gh)
    issue = next((i for i in issues if i.number == number), None)
    if issue is None:
        raise IssueError(f"{repo}#{number} is not an open issue")
    gh(
        ["issue", "edit", str(number), "-R", repo, "--remove-label", IN_PROGRESS, "--add-label", READY]
        + ["--remove-assignee", "@me"]
    )
    who = f" by agent {agent}" if agent else ""
    gh(["issue", "comment", str(number), "-R", repo, "--body", f"Released{who}: work stopped, ready to start again"])
    started = load_ledger(ledger)
    started.pop(ledger_key(repo, number), None)
    save_ledger(ledger, started)
    forget_reads(ledger)
    lines = [f"released {repo}#{number}: back in the line as {READY}"]
    covering = [pr.number for pr in prs if number in pr.closes]
    if covering:
        lines.append(f"note: the open pull request #{covering[0]} still closes it, so it still counts as in progress")
    return lines


def forget_reads(ledger: Path) -> None:
    """Drops the Stop hook's cache of `gh` reads (beside the ledger): an issue just changed, so the next check looks."""
    with contextlib.suppress(OSError):
        ledger.with_name(IDLE_CACHE).unlink()


def block_line(who: str, on: str, why: str, today: str, repo: str) -> str:
    """The line `gds issue block` writes: `Blocked (<who>, <date>): waits on #N: <why>` (or on the maintainer)."""
    if on.strip().lower() == MAINTAINER:
        waits = "the maintainer"
    else:
        other, number = parse_ref(on, repo)
        waits = f"#{number}" if other.lower() == repo.lower() else f"{other}#{number}"
    return f"Blocked ({who}, {today}): waits on {waits}: {' '.join(why.split())}"


def block(
    repo: str,
    number: int,
    on: str,
    why: str,
    *,
    gh: Gh,
    ledger: Path,
    who: str = "coordinator",
    now: datetime | None = None,
) -> list[str]:
    """Take an issue out of the line with a reason: `S-blocked` and a `Blocked (...)` line in the body (one it had is
    replaced). `on` is `maintainer` or the issue (or pull request) it waits on, which must be open."""
    if not why.strip():
        raise IssueError("--why needs the reason, in a sentence")
    issues, prs = fetch(repo, gh)
    window = compute_window(repo, issues, prs)
    issue = window.by_number.get(number)
    if issue is None:
        raise IssueError(f"{repo}#{number} is not an open issue")
    busy = [p for p in window.in_progress if p.issue.number == number]
    if busy:
        raise IssueError(
            f"{repo}#{number} {window.why_not(number)}: release it (`gds issue release`) before blocking it"
        )
    line = block_line(who, on, why, (now or datetime.now(UTC)).strftime("%Y-%m-%d"), repo)
    if on.strip().lower() != MAINTAINER:
        open_numbers = set(window.by_number) | {pr.number for pr in prs}
        other, blocker = parse_ref(on, repo)
        if other.lower() == repo.lower() and (blocker == number or blocker not in open_numbers):
            raise IssueError(
                f"{repo}#{number} cannot wait on #{blocker}: that is not another open issue or pull request"
            )
    body = without_blocks(issue.body)
    edit = ["issue", "edit", str(number), "-R", repo, "--body", (body + "\n\n" if body else "") + line]
    edit += ["--add-label", BLOCKED]
    for label in (READY, TRIAGE):
        if label in issue.labels:
            edit += ["--remove-label", label]
    gh(edit)
    forget_reads(ledger)
    return [
        f"blocked {repo}#{number}: {line}",
        "It leaves the line; `gds issue list` shows the reason and lifts it when #N closes.",
    ]


def unblock(repo: str, number: int, *, gh: Gh, ledger: Path, now: datetime | None = None) -> list[str]:
    """Put a blocked issue back in the line: the label and the `Blocked (...)` line go, `S-ready-to-start` comes back,
    and a comment keeps the reason that was lifted."""
    issues, _ = fetch(repo, gh)
    issue = next((i for i in issues if i.number == number), None)
    if issue is None:
        raise IssueError(f"{repo}#{number} is not an open issue")
    if BLOCKED not in issue.labels:
        raise IssueError(f"{repo}#{number} is not {BLOCKED}")
    old = parse_block(issue.body)
    edit = ["issue", "edit", str(number), "-R", repo, "--remove-label", BLOCKED, "--add-label", READY]
    if old:
        edit += ["--body", without_blocks(issue.body)]
    gh(edit)
    day = (now or datetime.now(UTC)).strftime("%Y-%m-%d")
    gh(
        [
            "issue",
            "comment",
            str(number),
            "-R",
            repo,
            "--body",
            f"Unblocked ({day})" + (f"; it was: {old.line()}" if old else ""),
        ]
    )
    forget_reads(ledger)
    return [f"unblocked {repo}#{number}: back in the line as {READY}"]


def done(repo: str, number: int, *, ledger: Path) -> list[str]:
    """Clear an issue's ledger entry. Not needed after a merge: the entry goes when the issue is closed."""
    started = load_ledger(ledger)
    if started.pop(ledger_key(repo, number), None) is None:
        return [f"{repo}#{number} was not in the ledger"]
    save_ledger(ledger, started)
    return [f"cleared {repo}#{number} from the ledger"]


def describe(repo: str, window: Window, prs: list[PullRequest], started: dict[str, dict]) -> list[str]:
    """`gds issue list`: the window, what is in progress and who owns it, what is blocked."""
    lines = [f"{repo}: open issues, oldest first (window of {window.size})", "", "May start now:"]
    lines += [
        f"  #{i.number:<5} {i.title}" + (f"  [{CRITICAL}]" if CRITICAL in i.labels else "") for i in window.allowed
    ] or ["  none"]
    if window.later:
        shown = ", ".join(f"#{i.number}" for i in window.later[:12]) + (" ..." if len(window.later) > 12 else "")
        lines.append(f"Behind the window ({len(window.later)}): {shown}")
    lines += ["", "In progress:"]
    for item in window.in_progress:
        entry = started.get(ledger_key(repo, item.issue.number))
        who = (
            [f"agent {entry['agent']} since {entry.get('time', '?')}"]
            if entry
            else ([f"assigned to {', '.join(item.issue.assignees)}"] if item.issue.assignees else [])
        )
        progress = [f"PR #{n}" for n in item.pull_requests]
        if not who and not progress:
            who = ["NO OWNER: not started through `gds issue start`, no assignee, no pull request"]
        lines.append(f"  #{item.issue.number:<5} {item.issue.title}  -- " + "; ".join(who + progress))
    if not window.in_progress:
        lines.append("  none")
    unblocked = {i.number for i in window.unblocked}
    still = [i for i in window.blocked if i.number not in unblocked]
    if still:
        lines += ["", "Blocked:"]
        for i in still:
            block = window.blocks.get(i.number)
            why = (
                f"{block.line()[:160]}"
                if block
                else f"no reason recorded: `gds issue block {window.repo}#{i.number} --on <#N|{MAINTAINER}> --why ...`"
            )
            lines.append(f"  #{i.number:<5} {i.title}  -- {why}")
    if window.unblocked:
        lines += [
            "",
            f"Unblocked: label to remove (what they waited on has closed; `gds issue unblock {window.repo}#N`):",
        ]
        lines += [f"  #{i.number:<5} {i.title}  -- {window.blocks[i.number].line()[:160]}" for i in window.unblocked]
    if window.waiting:
        lines += ["", "Waiting for information:"] + [f"  #{i.number:<5} {i.title}" for i in window.waiting]
    labelled = [pr for pr in prs if IN_PROGRESS in pr.labels]
    if labelled:
        lines += ["", f"Pull requests carrying {IN_PROGRESS} (a pull request is in progress by existing; remove it):"]
        lines += [f"  #{pr.number:<5} {pr.title}" for pr in labelled]
    return lines


def list_issues(repo: str, *, gh: Gh, ledger: Path, size: int = DEFAULT_WINDOW) -> list[str]:
    issues, prs = fetch(repo, gh)
    started = load_ledger(ledger)
    if prune_ledger(started, repo, {i.number for i in issues}):
        save_ledger(ledger, started)
    return describe(repo, compute_window(repo, issues, prs, size), prs, started)


def default_repo(gh: Gh) -> str:
    """The repository of the current folder, from `gh repo view`."""
    return gh(["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"]).strip()
