"""The maintainer's approval of a hold lift (docs/studio/hooks-hold.md#hold): whether the maintainer, typing in the
coordinator's own session, approved taking `S-hold` off one pull request. The guard in `guards/merges.py` asks this
before it lets the coordinator run `gh pr|issue edit <N> --remove-label S-hold`.

The session's transcript (`transcript_path` in the hook's input) is the record. Only an entry the maintainer typed
counts: a `user` entry whose `origin` kind is `human`, not meta, not a sidechain and not a tool result. A prompt a
plugin submits (tether's, origin kind `plugin`), an agent's report or a monitor event (`task-notification`), a peer's
message, hook output and reminders (`isMeta`) and tool results all fail that test. Inside a typed message, pasted text
(`<pasted_content>` blocks), quoted lines, fenced code and text in quotation marks are dropped before it is read, so
the coordinator's own words quoted back do not approve anything.

What approves pull request N, read sentence by sentence (a sentence ends at `.`, `!`, `?` or `;` before a space, or
at a line break; a clause after "but" is read on its own for a named number; an aside in parentheses is read on its
own unless it carries a refusal word, which keeps it in its sentence), in the maintainer's own words with no set
wording:
- a sentence that names N (`#N`, `N`, `repo#N`, `.../pull/N`) and says to lift, remove, release, approve, land or
  merge it, or yes; or
- a sentence that names N's topic and says yes: when the coordinator's last message lists N as an item (`1. #N jump
  arms: ...`), the item's label (its words before the first colon, dash, comma, full stop or parenthesis, at most
  three) names N wherever all of them stand in one sentence; or
- a line after a list marker (`1.`, `1)`) with no other digit that says yes, answering that item of the coordinator's
  numbered list when the item names N; or
- a sentence with no digit and no listed topic in it that says yes, approve or go ahead ("I approve of all the PRs
  mentioned"), answering the coordinator's last message before it, which named N and the hold or an approval. It
  covers every number that message named, however long the maintainer's message is; a line after a list marker
  answers only its own item.
A list marker's digit is never a named number. A question, a negation or a condition (no, not, don't, wait, keep, if,
once, after, until...) in that sentence does not approve, and a sentence that names N or its topic with one, or a
marked line answering N's item with a refusal word, vetoes N for the whole message. Unsure is no: the guard then
refuses as it always did.

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
HUMAN = "human"  # the origin kind of an entry the maintainer typed

_PASTED = re.compile(r"<pasted_content\b[^>]*>.*?(?:</pasted_content\b[^>]*>|\Z)", re.DOTALL | re.IGNORECASE)
_FENCED = re.compile(r"```.*?(?:```|\Z)", re.DOTALL)
_QUOTED = re.compile(r"\"[^\"\n]*\"|“[^”\n]*”|(?<!\w)'[^'\n]*'(?!\w)")
_QUOTE_LINE = re.compile(r"^\s*>.*$", re.MULTILINE)
_ENDS = r"(?<=[.!?;])(?=\s)|(?<=\n)"
_SENTENCES = re.compile(_ENDS + r"|\bbut\b", re.IGNORECASE)  # clauses, read for a named number
_WHOLE = re.compile(_ENDS)  # whole sentences, read for a yes to the list: "yes but not yet" stays one
_YES = re.compile(
    r"\b(yes|yep|yeah|yup|ok|okay|sure|approved?|approving|go ahead|go for it|do it|green light|lgtm"
    r"|lift(?:ed)?|remove[d]?|release[d]?|unhold|take (?:it|them|that|those) off|land|merge|ship"
    r"|take (?:(?:the|that|this|those|these|its|their) )?(?:s-)?holds? off"
    r"|looks? (?:good|great|fine)|(?:is|are) (?:good|great|fine)|good to go)\b",
    re.IGNORECASE,
)
# "hold off" refuses as a verb ("hold off on 7"), not as the label or the hold taken off ("S-hold off 7", "take the
# hold off 7"): gdstudio #1332.
_HOLD_OFF = r"(?<!s-)(?<!the )(?<!that )(?<!this )(?<!its )(?<!their )hold off"
_REFUSAL = (
    r"\b(no|not|nope|never|dont|cant|wont|wait|keep|stop|" + _HOLD_OFF + r"|later|cancel|instead"
    r"|if|unless|until|once|after|before|when|whether)\b|n['’]t\b"
)
_REFUSES = re.compile(_REFUSAL, re.IGNORECASE)  # a refusal word: it keeps an aside in its sentence
_NO = re.compile(_REFUSAL + r"|\?", re.IGNORECASE)
# An aside: "(can you check the hands?)" after an approval is a remark of its own (gdstudio #1467); an unclosed one
# runs to the end of its sentence.
_ASIDE = re.compile(r"\([^()\n]*(?:\)|$)")
# A list marker at a line's start, "3." or "3)": its digit names no pull request, it points at an item of a list.
_MARKER = re.compile(r"^[ \t]*(\d{1,2})[.)](?=\s)", re.MULTILINE)
_ITEM = re.compile(r"^[ \t]*(?:(\d{1,2})[.)]|[-*+])[ \t]+")  # an item of the coordinator's list
_POINTER = re.compile(r"\S*github\.com/\S+|[\w.-]*(?:/[\w.-]+)?#\d+")  # how an item points at a pull request
_LABEL_ENDS = re.compile(r"[:;,.?!()–—]|\s-\s")
_WORD = re.compile(r"[a-z]+")
_FILLING = (
    "a an and the of on in for to with new pr prs pull request requests s hold holds lift its it this that is are one"
)
_FILLER = frozenset(_FILLING.split())  # words an item's label leaves out
_TOPIC_MOST = 3  # a topic is the first three words of an item's label
_NUMBER = re.compile(r"\d")
# "#1369 through #1378" names every number between, both ends included; a short run only.
_RANGE = re.compile(r"(?<![\w.#/-])#?(\d+)\s*(?:through|thru|to|-|–|—)\s*#?(\d+)(?![\w])", re.IGNORECASE)
_RANGE_MOST = 30
_HOLD = re.compile(r"\b(?:hold|approv\w*)\b", re.IGNORECASE)  # the reply asked about a hold or an approval


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
    for low, high in _RANGE.findall(text):
        if int(low) <= number <= int(high) and int(high) - int(low) <= _RANGE_MOST:
            return True
    for found in [*pattern.finditer(text), *url.finditer(text)]:
        named = found.group("repo")
        if named is None:
            return True
        same_name = repo and named.lower().split("/")[-1] == repo.lower().split("/")[-1]
        if same_name and ("/" not in named or named.lower() == repo.lower()):
            return True
    return False


def _sentences(text: str, pattern: re.Pattern[str] = _SENTENCES) -> list[str]:
    """The text's sentences (or clauses), each aside without a refusal word taken out and read as one of its own."""
    parts = []
    for part in pattern.split(text):
        if not part or not part.strip():
            continue
        asides = [aside.group() for aside in _ASIDE.finditer(part) if not _REFUSES.search(aside.group())]
        for aside in asides:
            part = part.replace(aside, " ", 1)
        parts += [piece for piece in (part, *asides) if piece.strip()]
    return parts


def _stem(word: str) -> str:
    return word[:-1] if len(word) > 3 and word.endswith("s") else word


def _words(text: str) -> set[str]:
    """A text's words, lower case, a plural's `s` dropped."""
    return {_stem(word) for word in _WORD.findall(text.lower())}


def items(reply: str) -> list[tuple[int | None, str]]:
    """The items of the lists in the coordinator's message: (its number, or None for a bullet; its text, with the
    indented lines under it)."""
    found: list[tuple[int | None, str]] = []
    open_item = False
    for line in reply.splitlines():
        start = _ITEM.match(line)
        if start:
            found.append((int(start.group(1)) if start.group(1) else None, line[start.end() :]))
            open_item = True
        elif open_item and line[:1] in (" ", "\t") and line.strip():
            found[-1] = (found[-1][0], f"{found[-1][1]}\n{line}")
        else:
            open_item = False
    return found


def topic(item: str) -> set[str]:
    """An item's topic: the first words of its label (the text before its first colon, dash, comma, full stop or
    parenthesis, with its pointers and filler words left out); empty when it has none."""
    plain = _POINTER.sub(" ", re.sub(r"[*`_]", " ", item))
    for segment in _LABEL_ENDS.split(plain):
        words = [_stem(word) for word in _WORD.findall(segment.lower()) if word not in _FILLER]
        if words:
            return set(words[:_TOPIC_MOST])
    return set()


def _points_at(item: str, number: int, repo: str | None) -> bool:
    """Whether an item's first pointer (`#N`, `repo#N`, a URL) is pull request `number`: the item's topic is its."""
    first = _POINTER.search(item)
    return bool(first) and names(first.group(), number, repo)


def _plain_yes(sentence: str) -> bool:
    return bool(_YES.search(sentence)) and not _NO.search(sentence) and not _NUMBER.search(sentence)


def approves(text: str, reply: str, number: int, repo: str | None) -> str:
    """How a maintainer's message (its own words) approves lifting the hold on `number`, '' when it does not."""
    listed = items(reply)
    numbered = {mark: body for mark, body in listed if mark is not None}
    marked, plain = [], []  # lines answering an item of the numbered list; every other line
    for line in text.split("\n"):
        mark = _MARKER.match(line)
        if mark and numbered:
            marked.append((int(mark.group(1)), line[mark.end() :]))
        else:
            plain.append(line[mark.end() :] if mark else line)
    own = [body for mark, body in marked if mark in numbered and names(numbered[mark], number, repo)]
    topics = [words for words in (topic(body) for _, body in listed if _points_at(body, number, repo)) if words]

    def topical(clause: str) -> bool:
        return any(words <= _words(clause) for words in topics)

    clauses = _sentences("\n".join([*plain, *(body for _, body in marked)]))
    if any((names(clause, number, repo) or topical(clause)) and _NO.search(clause) for clause in clauses):
        return ""  # "don't lift 7" or "the jump arms are not right" anywhere in the message vetoes 7
    for body in own:
        if any(_REFUSES.search(clause) and not _NUMBER.search(clause) for clause in _sentences(body)):
            return ""  # "2) not yet" vetoes item 2's pull request
    for clause in clauses:
        if names(clause, number, repo) and _YES.search(clause):
            return "named"
    for clause in clauses:
        if topical(clause) and _YES.search(clause):
            return "topic"
    if not (_HOLD.search(reply) and names(_MARKER.sub(" ", reply), number, repo)):
        return ""
    for body in own:
        if any(_plain_yes(sentence) for sentence in _sentences(body, _WHOLE)):
            return "answered"
    every_topic = [words for words in (topic(body) for _, body in listed) if words]
    for sentence in _sentences("\n".join(plain), _WHOLE):
        if _plain_yes(sentence) and not any(words <= _words(sentence) for words in every_topic):
            return "answered"  # a yes naming a listed topic answers that item alone
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
