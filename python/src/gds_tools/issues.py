"""`gds issue`: issues are started oldest first, through one tool (docs/starting-work.md).

Only the oldest open issues that nobody works on may be started: the window. An issue is out of the line when it is
`S-in-progress`, `S-pending-review`, `S-blocked` or `S-needs-info`, or when an open pull request closes it (a pull
request that exists is in progress, so it never needs a label of its own). `P-critical` issues go first, oldest first
among them; the maintainer alone sets that label. "Oldest" is the lowest issue number.

`start` checks the window, labels and assigns the issue, comments, and writes the start to a ledger in
`<workspace>/cache/issues-started.json`; the hook (`.claude/hooks/guards.py`) refuses to start a task agent whose
prompt does not name an issue in that ledger. Every `gh` call goes through a runner that tests replace with recorded
JSON, so nothing here needs the network to be tested.
"""

from __future__ import annotations

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

    @classmethod
    def from_json(cls, data: dict) -> Issue:
        return cls(
            number=int(data["number"]),
            title=data.get("title", ""),
            labels=frozenset(label["name"] for label in data.get("labels", [])),
            assignees=tuple(a["login"] for a in data.get("assignees", [])),
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
                "number,title,labels,assignees",
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
) -> list[str]:
    """Start an issue if it is in the window: label, assign, comment, ledger. Returns the lines to print. `areas_for`
    maps the issue's labels to the areas of the mistakes glossary, which the ledger keeps for the SubagentStart hook."""
    issues, prs = fetch(repo, gh)
    window = compute_window(repo, issues, prs, size)
    started = load_ledger(ledger)
    if prune_ledger(started, repo, {i.number for i in issues}):
        save_ledger(ledger, started)
    if not window.allows(number):
        raise IssueError(refusal(repo, number, window))
    issue = window.by_number[number]
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
        "branch": branch,
        "areas": areas,
    }
    save_ledger(ledger, started)
    return [
        f"started {repo}#{number} ({issue.title}) for agent {agent}",
        *([f"areas: {', '.join(areas)} (their checks are put into the agent's context at start)"] if areas else []),
        "Put this line in the agent's prompt (the hook looks for it):",
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
    lines = [f"released {repo}#{number}: back in the line as {READY}"]
    covering = [pr.number for pr in prs if number in pr.closes]
    if covering:
        lines.append(f"note: the open pull request #{covering[0]} still closes it, so it still counts as in progress")
    return lines


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
    if window.blocked:
        lines += ["", "Blocked:"] + [f"  #{i.number:<5} {i.title}" for i in window.blocked]
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
