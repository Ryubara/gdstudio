"""`gds brief <owner/repo>#N`: the sections of the docs a task agent reads before it starts, as `Read:` lines.

The coordinator runs it before every Agent call and puts the lines in the task agent's prompt, beside `Issue:` or
`PR:`; the Agent guard refuses a task agent with no `Read:` line or one naming a section that does not exist
(docs/studio/starting-work.md#starting-an-agent). The sections come from the issue's text, its area labels with their
descriptions and the paths it names, and for a pull request its changed files too (`lessons.propose`).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from gds_tools import lessons
from gds_tools.issues import Gh, IssueError

_REF = re.compile(r"^([\w.-]+/[\w.-]+)#(\d+)$")


@dataclass(frozen=True)
class Subject:
    """What a brief is made from: an issue or a pull request of GitHub."""

    repo: str
    number: int
    title: str
    body: str = ""
    labels: dict[str, str] = field(default_factory=dict)  # name: description
    files: tuple[str, ...] = ()  # a pull request's changed files
    pull: bool = False


def parse_ref(ref: str) -> tuple[str, int]:
    found = _REF.match(ref.strip())
    if not found:
        raise IssueError(f"{ref!r} is not owner/repo#N")
    return found.group(1), int(found.group(2))


def fetch(repo: str, number: int, gh: Gh) -> Subject:
    """The issue or pull request `repo#number` (`gh api` reads both through the issues endpoint), with a pull
    request's changed files."""
    try:
        data = json.loads(gh(["api", f"repos/{repo}/issues/{number}"]))
    except ValueError as error:
        raise IssueError(f"{repo}#{number}: GitHub's answer could not be read") from error
    pull = "pull_request" in data
    files: tuple[str, ...] = ()
    if pull:
        listed = gh(["api", "--paginate", f"repos/{repo}/pulls/{number}/files", "--jq", ".[].filename"])
        files = tuple(line.strip() for line in listed.splitlines() if line.strip())
    return Subject(
        repo=repo,
        number=number,
        title=data.get("title") or "",
        body=data.get("body") or "",
        labels={lb["name"]: lb.get("description") or "" for lb in data.get("labels", []) if isinstance(lb, dict)},
        files=files,
        pull=pull,
    )


def propose(kit: Path, subject: Subject, limit: int = 6) -> list[lessons.Proposal]:
    return lessons.propose(kit, subject.title, subject.body, subject.labels, list(subject.files), limit)


def text(kit: Path, subject: Subject, limit: int = 6, why: bool = False) -> str:
    """What `gds brief` prints: the `Read:` lines, or a note when no section fits."""
    found = propose(kit, subject, limit)
    if not found:
        return (
            f"No section of the docs fits {subject.repo}#{subject.number} ({subject.title!r}). Name the closest one by "
            f"hand (`gds learn <words>`), as `Read: <page>.md#<anchor>`."
        )
    return lessons.brief_text(found, why)
