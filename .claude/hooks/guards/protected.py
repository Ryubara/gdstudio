"""Nothing secret printed into the transcript, no protected or generated file edited by hand, and no session writing a
session transcript, where the maintainer's approval of a hold lift is read (docs/studio/hooks-hold.md#hold)."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from .shell import program, segments
from .workspace import matches

_DUMPS = {"env", "printenv"}
_PRINTERS = {
    "echo",
    "printf",
    "write-output",
    "write-host",
    "print",
    "cat",
    "type",
    "printenv",
}


def check_secrets(words: list[str], command: str, config: dict[str, Any]) -> list[str]:
    """Nothing that prints a secret into the transcript: an echo of a key-like variable, or an environment dump."""
    name = program(words)
    pattern = config.get("protect", {}).get("secret_names")
    if name in _DUMPS and len(words) == 1:
        return ["dumping the environment would print secrets; read the one variable you need without printing it"]
    if name in ("get-childitem", "gci", "ls", "dir") and any(w.lower().rstrip("\\/") in ("env:",) for w in words[1:]):
        return ["listing env: would print secrets; test for the variable instead (`[bool]$env:NAME`)"]
    if pattern and name in _PRINTERS and re.search(pattern, " ".join(words[1:])):
        return ['that would print a secret into the transcript; check it is set (`[ -n "$NAME" ]`) instead']
    return []


def check_edit(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """Protected and generated files are never edited by hand."""
    inp = payload.get("tool_input") or {}
    path = inp.get("file_path") or inp.get("notebook_path") or ""
    if not path:
        return []
    rules = config.get("protect", {})
    if matches(path, rules.get("paths", [])):
        return [f"{path} is protected (secrets, caches, git internals or a pinned tool)"]
    project = Path(payload.get("cwd") or ".")
    try:
        rel = Path(path).resolve().relative_to(project.resolve()).as_posix()
    except ValueError:
        return []
    if matches(rel, rules.get("generated", [])):
        return [f"{rel}: {rules.get('generated_hint', 'it is generated')}"]
    return []


# --- the session transcripts (docs/studio/hooks-hold.md#hold; merges.py reads the maintainer's approval there) ---

# A transcript: a `.jsonl` file under a `.claude/projects/` folder (Edit and Write of one are refused by `[protect]`).
_TRANSCRIPT = re.compile(r"\.claude[/\\]+projects[/\\].*\.jsonl", re.IGNORECASE)
# An entry spelled as the maintainer's own: an origin of kind human. Built in pieces, so this file never holds it.
_HUMAN_ORIGIN = re.compile(r"""["']?kind["']?\s*[:=]\s*\\?["']""" + "hu" + r"""man\\?["']""", re.IGNORECASE)
_READERS = {"cat", "type", "head", "tail", "less", "more", "grep", "rg", "findstr", "wc", "stat", "file", "ls", "dir"}
_READERS |= {"get-content", "gc", "select-string", "sls", "test-path", "get-item", "gi", "get-childitem", "gci", "jq"}
_WRITERS = {"tee", "set-content", "sc", "add-content", "ac", "out-file", "truncate", "dd", "rm", "del", "remove-item"}
_COPIERS = {"cp", "copy", "copy-item", "cpi", "mv", "move", "move-item", "mi", "ren", "rename-item"}
_REDIRECT = re.compile(r"(?:^|[^-=])\d?>>?(.*)$")
_FORGE = (
    "a session transcript is the record of what the maintainer typed, where a hold lift's approval is read: no "
    "session writes one or spells an entry as the maintainer's (docs/studio/hooks-hold.md#hold)"
)


def _names_transcript(word: str) -> bool:
    return bool(_TRANSCRIPT.search(word))


def check_transcript_shell(words: list[str]) -> list[str]:
    """A shell command that would write a transcript: a redirect into one, a writing program or `sed -i` naming one,
    or a copy or move onto one. Reading one (any program that is not a writer) passes."""
    if not any(_names_transcript(w) for w in words):
        return []
    for i, word in enumerate(words):
        found = _REDIRECT.search(word) if ">" in word else None
        if found and _names_transcript(found.group(1) or (words[i + 1] if i + 1 < len(words) else "")):
            return [_FORGE]
    name = program(words)
    if name in _COPIERS:
        destination = [w for w in words[1:] if not w.startswith("-")][-1:]
        return [_FORGE] if destination and _names_transcript(destination[0]) else []
    if name in _WRITERS or (name == "sed" and any(w.startswith("-i") or w == "--in-place" for w in words[1:])):
        return [_FORGE]
    return []


def check_transcript_text(command: str) -> list[str]:
    """A shell line that spells an entry as the maintainer's and is not only reads (a `grep` for it passes)."""
    if not _HUMAN_ORIGIN.search(command):
        return []
    parts = segments(command)
    return [] if parts and all(words and program(words) in _READERS for words in parts) else [_FORGE]


def check_transcript_edit(payload: dict[str, Any]) -> list[str]:
    """An Edit, Write, MultiEdit or NotebookEdit whose new text spells an entry as the maintainer's, in any file: a
    script written to forge one is refused here, since the shell line that runs it no longer shows it."""
    inp = payload.get("tool_input") or {}
    texts = [inp.get(key) or "" for key in ("content", "new_string", "new_source")]
    texts += [(edit or {}).get("new_string") or "" for edit in inp.get("edits") or []]
    return [_FORGE] if _HUMAN_ORIGIN.search("\n".join(texts)) else []
