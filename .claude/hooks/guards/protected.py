"""Nothing secret printed into the transcript, no protected or generated file edited by hand, and the maintainer's
hold switch (docs/studio/hooks.md#hold) never turned on or off by a session."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from .shell import program
from .workspace import matches, workspace_of

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


# --- the maintainer's hold switch (docs/studio/hooks.md#hold; merges.py lets the coordinator lift while it is on) ---

_SWITCH_FILE = "gdstudio.local.toml"
_SWITCH_KEY = "coordinator" + "_may_lift"  # split, so this file never holds the assignment it refuses
# The key followed by an assignment (TOML, Python, JSON, a shell `=`): naming the key passes, setting it does not.
_SETS_KEY = re.compile(re.escape(_SWITCH_KEY) + r"""["']?\s*[=:]""")
_READERS = {"cat", "type", "head", "tail", "less", "more", "grep", "rg", "findstr", "wc", "stat", "file", "ls", "dir"}
_READERS |= {"get-content", "gc", "select-string", "sls", "test-path", "get-item", "gi", "get-childitem", "gci", "git"}
_COPIERS = {"cp", "copy", "copy-item", "cpi"}
_REDIRECT = re.compile(r"(?:^|[^-=])\d?>>?(.*)$")
_TURN = (
    "the hold switch is the maintainer's: only they turn it on or off, by hand in an editor, never a session "
    "(docs/studio/hooks.md#hold)"
)


def _names_file(word: str) -> bool:
    return _SWITCH_FILE in word.replace("\\", "/")


def _is_workspace(word: str, cwd: Path) -> bool:
    """Whether a copy's destination is the workspace folder, where a file of that name becomes the switch."""
    workspace = workspace_of(cwd)
    if workspace is None or "$" in word:
        return False
    try:
        return (cwd / word).resolve() == workspace.resolve()
    except (OSError, ValueError):
        return False


def check_switch_shell(words: list[str], cwd: Path) -> list[str]:
    """A shell command that would write the switch's file: one that names it and is not a read, a redirect into it,
    or a copy onto it or into the workspace folder. A read and a copy away from it (a throwaway workspace) pass."""
    if not any(_names_file(w) for w in words):
        return []
    for i, word in enumerate(words):
        found = _REDIRECT.search(word) if ">" in word else None
        if found and _names_file(found.group(1) or (words[i + 1] if i + 1 < len(words) else "")):
            return [_TURN]
    name = program(words)
    if name in _COPIERS:
        destination = [w for w in words[1:] if not w.startswith("-")][-1:]
        if destination and (_names_file(destination[0]) or _is_workspace(destination[0], cwd)):
            return [_TURN]
        return []
    return [] if name in _READERS else [_TURN]


def check_switch_text(text: str) -> list[str]:
    """Text a session sends (a shell line, a file's new content) that sets the switch's key."""
    return [_TURN] if _SETS_KEY.search(text) else []


def check_switch_edit(payload: dict[str, Any]) -> list[str]:
    """An Edit, Write, MultiEdit or NotebookEdit whose new text sets the switch's key, in any file: a script written
    to flip it is refused here, since the shell line that runs it no longer names the key."""
    inp = payload.get("tool_input") or {}
    texts = [inp.get(key) or "" for key in ("content", "new_string", "new_source")]
    texts += [(edit or {}).get("new_string") or "" for edit in inp.get("edits") or []]
    return check_switch_text("\n".join(texts))
