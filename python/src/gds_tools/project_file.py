"""Merge Godot `project.godot` files: a template that extends another holds only what it adds.

`gds new game` reads the chain base first and merges by section and key (new-game.md#adding-a-template):
a later file's key wins, the list of enabled plugins is joined, and the result is written in Godot's own order
(the top keys, then the sections by name). A value is kept as the text it has, so a multi-line one (the input map) is
never re-written and the merge cannot change what the editor would save.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

SECTION = re.compile(r"^\[([^\[\]\s]+)\]\s*$")
KEY = re.compile(r"^([A-Za-z0-9_][\w/.\-]*)\s*=")
QUOTED = re.compile(r'"((?:[^"\\]|\\.)*)"')
#: The one list the merge joins instead of replacing: the plugins the editor enables.
JOINED = ("editor_plugins", "enabled")


@dataclass
class ProjectFile:
    """A parsed file: the leading comments, the keys before the first section, and `sections[name][key]` = the key's
    text (its `key=value` line or lines)."""

    header: list[str] = field(default_factory=list)
    top: list[str] = field(default_factory=list)
    sections: dict[str, dict[str, str]] = field(default_factory=dict)


def parse(text: str) -> ProjectFile:
    """Split `text` into its header comments, top keys and sections; a line that is no section and starts no key
    belongs to the value before it."""
    parsed = ProjectFile()
    current: dict[str, str] | None = None
    last: list[str] | None = None  # the value being read: its lines
    store: dict[str, list[str]] = {}
    for line in text.replace("\r\n", "\n").split("\n"):
        header = SECTION.match(line)
        key = KEY.match(line)
        if header:
            current = parsed.sections.setdefault(header.group(1), {})
            store = {}
            last = None
        elif key:
            last = [line]
            if current is None:
                parsed.top.append(line)
            else:
                store[key.group(1)] = last
                current[key.group(1)] = line
        elif last is not None and line.strip() and current is not None:
            last.append(line)
            name = next(k for k, v in store.items() if v is last)
            current[name] = "\n".join(last)
        elif current is None and line.startswith(";"):
            parsed.header.append(line)
        elif not line.strip():
            last = None
    return parsed


def _joined(old: str, new: str) -> str:
    """Two `enabled=PackedStringArray(...)` lines as one, each plugin once, in order."""
    plugins: list[str] = []
    for value in (old, new):
        plugins.extend(p for p in QUOTED.findall(value) if p not in plugins)
    return "enabled=PackedStringArray(" + ", ".join(f'"{p}"' for p in plugins) + ")"


def render(parsed: ProjectFile) -> str:
    """The file in Godot's order: header, top keys, then the sections by name, one blank line between."""
    blocks: list[str] = []
    if parsed.header:
        blocks.append("\n".join(parsed.header))
    if parsed.top:
        blocks.append("\n".join(parsed.top))
    for name in sorted(parsed.sections):
        blocks.append(f"[{name}]\n\n" + "\n".join(parsed.sections[name].values()))
    return "\n\n".join(blocks) + "\n"


def merge(texts: list[str]) -> str:
    """The files merged, the first one the base: a later key wins in place, a new key goes to the end of its section."""
    merged = ProjectFile()
    for text in texts:
        parsed = parse(text)
        merged.header = merged.header or parsed.header
        for line in parsed.top:
            name = KEY.match(line).group(1)  # type: ignore[union-attr]
            merged.top = [line if KEY.match(old).group(1) == name else old for old in merged.top]  # type: ignore[union-attr]
            if line not in merged.top:
                merged.top.append(line)
        for section, keys in parsed.sections.items():
            target = merged.sections.setdefault(section, {})
            for key, value in keys.items():
                if (section, key) == JOINED and key in target:
                    value = _joined(target[key], value)
                target[key] = value
    return render(merged)
