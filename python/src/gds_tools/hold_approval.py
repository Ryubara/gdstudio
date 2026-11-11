"""The maintainer's approval of a hold lift (docs/studio/hooks-hold.md#hold): whether the maintainer, typing in the
coordinator's own session, approved taking `S-hold` off one pull request. The guard in `guards/merges.py` asks this
before it lets the coordinator run `gh pr|issue edit <N> --remove-label S-hold`.

The session's transcript (`transcript_path` in the hook's input) is the record. Only an entry the maintainer typed
counts: a `user` entry whose `origin` kind is `human`, not meta, not a sidechain and not a tool result. A prompt a
plugin submits (tether's, origin kind `plugin`), an agent's report or a monitor event (`task-notification`), a peer's
message, hook output and reminders (`isMeta`) and tool results all fail that test. Inside a typed message, pasted text
(`<pasted_content>` blocks), quoted lines, fenced code and text in quotation marks are dropped before it is read, so
the coordinator's own words quoted back do not approve anything.

What approves pull request N, read sentence by sentence (a sentence ends at `.`, `!`, `?` or `;` before a space, a
line break or "but"):
- a sentence that names N (`#N`, `N`, `repo#N`, `.../pull/N`) and says to lift, remove, release, approve, land or
  merge it, or yes; or
- a short message (at most 20 words) with no digit in it and says yes or go ahead, answering the coordinator's last
  message before it, which named N and the hold.
A question, a negation or a condition (no, not, don't, wait, keep, if, once, after, until...) in that sentence or short
message does not approve. Unsure is no: the guard then refuses as it always did.

An approval counts for 24 hours and for one lift of that pull request: the lift log records the approving message's
time, and a lift whose approval is already in the log is refused. Standard library only: the hooks load this file by
its path (`load_kit_module`), without the `gds` package.
"""

from __future__ import annotations

import json
import re
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from pathlib import Path

LOG = "scratch/hold-lifts.log"  # every lift the guard lets through, relative to the workspace
WINDOW = timedelta(hours=24)  # how long a maintainer's approval stays good
SHORT = 20  # the most words a bare yes may have
HUMAN = "human"  # the origin kind of an entry the maintainer typed

_PASTED = re.compile(r"<pasted_content\b[^>]*>.*?(?:</pasted_content\b[^>]*>|\Z)", re.DOTALL | re.IGNORECASE)
_FENCED = re.compile(r"```.*?(?:```|\Z)", re.DOTALL)
_QUOTED = re.compile(r"\"[^\"\n]*\"|“[^”\n]*”|(?<!\w)'[^'\n]*'(?!\w)")
_QUOTE_LINE = re.compile(r"^\s*>.*$", re.MULTILINE)
_SENTENCES = re.compile(r"(?<=[.!?;])(?=\s)|(?<=\n)|\bbut\b", re.IGNORECASE)
_YES = re.compile(
    r"\b(yes|yep|yeah|yup|ok|okay|sure|approved?|approving|go ahead|go for it|do it|green light|lgtm"
    r"|lift(?:ed)?|remove[d]?|release[d]?|unhold|take (?:it|them|the holds?|that|those) off|land|merge|ship)\b",
    re.IGNORECASE,
)
_NO = re.compile(
    r"\b(no|not|nope|never|dont|cant|wont|wait|keep|stop|hold off|later|cancel|instead"
    r"|if|unless|until|once|after|before|when|whether)\b|n['’]t\b|\?",
    re.IGNORECASE,
)
_NUMBER = re.compile(r"\d")
_HOLD = re.compile(r"\bhold\b", re.IGNORECASE)


@dataclass(frozen=True)
class Approval:
    """A maintainer's message that approved one lift: its timestamp as the transcript has it, and how it approved."""

    timestamp: str
    how: str  # "named" (the message names the pull request) or "answered" (a yes to the coordinator's list)


def _text(content: object) -> str:
    """The text of a message's content (a string, or a list of blocks of which only text blocks count)."""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")
    return ""


def own_words(text: str) -> str:
    """What the maintainer wrote themselves: pasted blocks, fenced code, quoted lines and quoted spans dropped (an
    unclosed paste or fence drops everything after it)."""
    for pattern in (_PASTED, _FENCED, _QUOTE_LINE, _QUOTED):
        text = pattern.sub(" ", text)
    return text


def typed_by_maintainer(entry: dict) -> bool:
    """Whether a transcript entry is a message the maintainer typed in this session."""
    origin = entry.get("origin")
    return (
        entry.get("type") == "user"
        and isinstance(origin, dict)
        and origin.get("kind") == HUMAN
        and not entry.get("isMeta")
        and not entry.get("isSidechain")
        and "toolUseResult" not in entry
        and not entry.get("sourceToolUseID")
        and (entry.get("message") or {}).get("role") == "user"
    )


def maintainer_messages(path: Path) -> Iterator[tuple[dict, str]]:
    """Each message the maintainer typed, oldest first, with the text of the coordinator's last message before it."""
    last_reply, reply_id = "", None
    try:
        lines = path.open(encoding="utf-8", errors="replace")
    except OSError:
        return
    with lines:
        for line in lines:
            if '"assistant"' not in line and f'"{HUMAN}"' not in line:
                continue  # cheap: most of a transcript is neither
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict):
                continue
            if entry.get("type") == "assistant" and not entry.get("isSidechain"):
                message = entry.get("message") or {}
                text = _text(message.get("content"))
                if text.strip():
                    same = message.get("id") is not None and message.get("id") == reply_id
                    last_reply, reply_id = (f"{last_reply}\n{text}" if same else text), message.get("id")
            elif typed_by_maintainer(entry):
                yield entry, last_reply


def names(text: str, number: int, repo: str | None) -> bool:
    """Whether a text names pull request `number`: `#N`, `N`, `.../pull/N`, or `name#N` and `owner/name#N` when the
    name is the repository's (a name given for an unknown repository does not count)."""
    pattern = re.compile(rf"(?<![\w.#/-])(?:(?P<repo>[\w.-]+(?:/[\w.-]+)?)#|#)?(?<![\d.]){number}(?![\w])")
    url = re.compile(rf"github\.com/(?P<repo>[\w.-]+/[\w.-]+)/(?:pull|issues)/{number}(?![\w])", re.IGNORECASE)
    for found in [*pattern.finditer(text), *url.finditer(text)]:
        named = found.group("repo")
        if named is None:
            return True
        same_name = repo and named.lower().split("/")[-1] == repo.lower().split("/")[-1]
        if same_name and ("/" not in named or named.lower() == repo.lower()):
            return True
    return False


def _sentences(text: str) -> list[str]:
    return [part for part in _SENTENCES.split(text) if part and part.strip()]


def approves(text: str, reply: str, number: int, repo: str | None) -> str:
    """How a maintainer's message (its own words) approves lifting the hold on `number`, '' when it does not."""
    for sentence in _sentences(text):
        if names(sentence, number, repo) and _YES.search(sentence) and not _NO.search(sentence):
            return "named"
    words = text.split()
    if (
        words
        and len(words) <= SHORT
        and _YES.search(text)
        and not _NO.search(text)
        and not _NUMBER.search(text)
        and _HOLD.search(reply)
        and names(reply, number, repo)
    ):
        return "answered"
    return ""


def _when(stamp: object) -> datetime | None:
    try:
        when = datetime.fromisoformat(str(stamp).replace("Z", "+00:00"))
    except ValueError:
        return None
    return when if when.tzinfo else None


def find(
    transcript: str | Path | None,
    number: int,
    repo: str | None,
    used: set[str] | frozenset[str] = frozenset(),
    now: datetime | None = None,
) -> Approval | None:
    """The newest unused approval of a lift of `number` in a session's transcript within the window; None when there
    is none, when the transcript is missing or unreadable, or when a timestamp cannot be read."""
    if not transcript:
        return None
    now = now or datetime.now(UTC)
    found = None
    for entry, reply in maintainer_messages(Path(transcript)):
        stamp = str(entry.get("timestamp") or "")
        when = _when(stamp)
        if when is None or not (now - WINDOW <= when <= now + timedelta(minutes=5)) or stamp in used:
            continue
        how = approves(own_words(_text((entry.get("message") or {}).get("content"))), reply, number, repo)
        if how:
            found = Approval(stamp, how)
    return found


def log_name(number: int, repo: str | None) -> str:
    """How the log names a pull request."""
    return f"{repo}#{number}" if repo else f"#{number}"


def used_approvals(log_text: str, number: int, repo: str | None) -> set[str]:
    """The approving messages' timestamps the log already spent on this pull request (any repository spelling)."""
    used = set()
    for line in log_text.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[2] == "approved" and parts[1].endswith(f"#{number}"):
            spelled = parts[1].rsplit("#", 1)[0]
            if not spelled or not repo or spelled.lower() == repo.lower():
                used.add(parts[3])
    return used


def log_line(stamp: str, number: int, repo: str | None, approval: Approval, session: str) -> str:
    """One line of the lift log: when, which pull request, the approving message's time (never its text), how."""
    return f"{stamp}  {log_name(number, repo)}  approved {approval.timestamp} ({approval.how})  session {session}\n"
