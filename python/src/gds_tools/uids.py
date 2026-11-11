"""`gds template uids`: the `.uid` file beside each script and shader of a Godot project, written as Godot writes it.

Godot 4.4+ keeps a script's or shader's resource uid in `<file>.uid` (`uid://<text>` and a newline). The editor writes
it when it opens a project, but a template's folder is not a project anyone opens, so agents made the files by hand and
some held text Godot never writes (kit #1129). The text is `ResourceUID.id_to_text`: the id (a random non-negative
63-bit integer, `ResourceUID.create_id`) in base 34, most significant digit first, with the digits `a`-`y` then
`0`-`8`. Godot's `text_to_id` also reads a `z` or a `9`, but to a number whose text is another string, and a text too
long for 63 bits wraps; a valid file is one whose text Godot would write back unchanged. The pinned Godot keeps every
file written here byte for byte on import (`python/tests/test_uids.py`).
"""

from __future__ import annotations

import secrets
from dataclasses import dataclass, field
from pathlib import Path

PREFIX = "uid://"
#: Godot's digits, in order: `char_count = 'z' - 'a'` letters, then `'9' - '0'` numbers (core/io/resource_uid.cpp).
DIGITS = "abcdefghijklmnopqrstuvwxy012345678"
BASE = len(DIGITS)
#: The largest id: Godot masks a new id to 63 bits so that it stays positive.
MAX_ID = 2**63 - 1
#: The files Godot gives a uid file to.
SUFFIXES = frozenset({".gd", ".gdshader"})
#: Folders whose files are not the project's own sources: Godot's cache, git, test reports. An addon's files are its
#: own (synced or third-party, with the uid files their source ships) and are never written here.
SKIPPED = frozenset({".godot", ".git", "reports", "addons"})


def id_to_text(number: int) -> str:
    """`ResourceUID.id_to_text`: `uid://` and the id in Godot's base 34."""
    if not 0 <= number <= MAX_ID:
        raise ValueError(f"{number} is not a resource uid (0 to 2^63 - 1)")
    digits = []
    while True:
        number, digit = divmod(number, BASE)
        digits.append(DIGITS[digit])
        if not number:
            break
    return PREFIX + "".join(reversed(digits))


def text_to_id(text: str) -> int | None:
    """The id a valid `uid://` text stands for, or None for one Godot would not write."""
    if not text.startswith(PREFIX) or len(text) == len(PREFIX):
        return None
    number = 0
    for char in text[len(PREFIX) :]:
        digit = DIGITS.find(char)
        if digit < 0:
            return None
        number = number * BASE + digit
    if number > MAX_ID or id_to_text(number) != text:  # too big, or a leading zero digit (`uid://ab`)
        return None
    return number


def is_valid(text: str) -> bool:
    return text_to_id(text) is not None


def new_uid() -> str:
    """A new uid's text, as `ResourceUID.create_id` makes one: random, 63 bits."""
    return id_to_text(secrets.randbits(63))


def read(path: Path) -> str:
    """A uid file's text without the newline (and the byte-order mark some editors add)."""
    return path.read_text(encoding="utf-8-sig").strip()


def write(path: Path) -> str:
    """Write a new uid to `path` as Godot does: UTF-8 without a byte-order mark, one `\\n`."""
    text = new_uid()
    path.write_bytes((text + "\n").encode("ascii"))
    return text


def sources(project: Path) -> list[Path]:
    """Every script and shader of the project that Godot gives a uid file, outside the skipped folders."""
    return [
        path
        for path in sorted(project.rglob("*"))
        if path.suffix in SUFFIXES
        and path.is_file()
        and not any(part in SKIPPED for part in path.relative_to(project).parts)
    ]


def uid_file(source: Path) -> Path:
    return source.with_name(source.name + ".uid")


@dataclass
class Result:
    written: list[Path] = field(default_factory=list)
    #: Uid files whose text Godot would not write, left as they were.
    invalid: list[Path] = field(default_factory=list)


def write_missing(project: Path, *, replace_invalid: bool = False) -> Result:
    """Write the missing uid file of each script and shader of `project` (a folder of `.gd`/`.gdshader` files; a
    template's `game/` holds only part of a project). A valid existing file is never changed; an invalid one is
    reported, and replaced only with `replace_invalid` (a `.tscn` that names its old text then loads by path)."""
    result = Result()
    taken = set()
    for source in sources(project):
        path = uid_file(source)
        if path.is_file():
            text = read(path)
            if is_valid(text):
                taken.add(text)
                continue
            if not replace_invalid:
                result.invalid.append(path)
                continue
        text = write(path)
        while text in taken:  # a repeat of a 63-bit random number: never seen, but cheap to rule out
            text = write(path)
        taken.add(text)
        result.written.append(path)
    return result
