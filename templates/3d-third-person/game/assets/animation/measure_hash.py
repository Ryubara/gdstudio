"""The hash a limb overlap report carries of the measure that made it (kit #1479).

    python -B measure_hash.py [--self-test] [<body.glb> ...]

A report (`bodies_overlap.json`, `<file>_overlap.json`) holds numbers `limb_overlap.py` read from a clip file on some
bodies. It already names the clip file by its SHA-256. It also names what made the numbers, so a Godot suite can tell
when they are no longer the numbers the game's own script would read (`tests/fixtures/bodies_overlap.gd`):

- `measure_sha256`: the SHA-256 of `limb_overlap.py`'s code in a normal form (`normal_form`). The whole script
  counts, since the cut into parts, the samples, the rays and the rate rule (`clip_rate`) all move the numbers. The
  normal form drops what cannot move them: comments, docstrings, blank lines, the spaces between tokens and the
  line breaks and indentation inside brackets. So a comment, a reworded docstring or a call wrapped over other lines
  keeps the hash, and any change to a token (a string's text among them) or to a statement's indentation changes it.
- `bodies_sha256`: the SHA-256 of each body file measured, by the body's name. The numbers are read on the body's
  skin, so a rebuilt body is a body not measured.

Not covered: the Blender that ran the measure (the kit pins one, and a game cannot see the pin), a trailing comma
a formatter adds or takes away (a token) and a line joined with a backslash (the scripts have none).

No `bpy` here: `limb_overlap.py` imports this in Blender and `own/build_own.py` in plain Python. The Godot fixture
has the same normal form in GDScript; `CASES` holds texts with the hash both must give (`--self-test` here,
`tests/assets/test_bodies_overlap.gd` there).
"""

import hashlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
## The measure whose code a report names.
SCRIPT = HERE / "limb_overlap.py"

## Texts and the hash of their normal form, the same list as `CASES` in `tests/assets/test_bodies_overlap.gd`.
_PLAIN = 'def depth(a, b):\n    for way in RAYS:\n        hit = cast(a, way)\n    return f"{a} in {b}"\n'
CASES = {
    "plain": (_PLAIN, "59642f049fac6d004894f80f5e508c346cde0204f5a711c558fb805f39816282"),
    "comments, a docstring, blank lines and a wrapped call": (
        (
            '"""A module."""\n\n# a comment\ndef depth(a, b):  # how deep\n    """A docstring: with a # in it.\n\n'
            '    And a second line.\n    """\n    for way in RAYS:\n\n        hit = cast(\n            a,\n'
            '            way\n        )\n    return f"{a} in {b}"\r\n'
        ),
        "59642f049fac6d004894f80f5e508c346cde0204f5a711c558fb805f39816282",
    ),
    "a statement moved out of the loop": (
        'def depth(a, b):\n    for way in RAYS:\n        pass\n    hit = cast(a, way)\n    return f"{a} in {b}"\n',
        "7eb04ae1521637aa5c7485252915c10fb68e3d970d8652bd9a27ce4f2bbfa70e",
    ),
    "a string with a space more": (
        'def depth(a, b):\n    for way in RAYS:\n        hit = cast(a, way)\n    return f"{a}  in {b}"\n',
        "ec0de1182c6f8931d5a0f9a7ee62c400d65bf4ef173f5608ec5f3d69ee5b84cb",
    ),
}


def _word(char):
    """A character of a name or a number: two tokens made of these need the space between them."""
    return char == "_" or ord(char) > 127 or (char.isascii() and char.isalnum())


def normal_form(text):
    """A Python source's tokens with nothing that cannot change what it computes: no comment, no docstring (a
    triple-quoted string that starts a statement), no blank line, one space only between two names or numbers, no
    line break or indentation inside brackets. Each statement starts on its own line at its own indentation."""
    out = []
    depth = 0  # open brackets
    fresh = True  # at the start of a statement: nothing of it is out yet
    indent = 0
    last = "\n"
    i, size = 0, len(text)
    while i < size:
        char = text[i]
        if char == "\n":
            if depth == 0:
                fresh, indent = True, 0
            i += 1
        elif char in " \t\r":
            if fresh:
                indent += 1
            i += 1
        elif char == "#":
            while i < size and text[i] != "\n":
                i += 1
        else:
            token = char
            if char in "'\"":
                quote = char * 3 if text[i : i + 3] == char * 3 else char
                end = i + len(quote)
                while end < size and text[end : end + len(quote)] != quote:
                    end += 2 if text[end] == "\\" else 1
                end = min(end + len(quote), size)
                token = text[i:end]
                if fresh and len(quote) == 3:
                    i = end
                    continue
            elif char in "([{":
                depth += 1
            elif char in ")]}":
                depth = max(depth - 1, 0)
            if fresh:
                out.append("\n" + " " * indent)
                fresh = False
            elif _word(last) and _word(token[0]) and not _word(text[i - 1]):
                out.append(" ")
            out.append(token)
            last = token[-1]
            i += len(token)
    return "".join(out)


def text_sha256(text):
    return hashlib.sha256(normal_form(text).encode("utf-8")).hexdigest()


def script_sha256(path=SCRIPT):
    """The hash of the measure's code a report carries as `measure_sha256`."""
    return text_sha256(Path(path).read_text(encoding="utf-8"))


def bodies_sha256(paths):
    """Each measured body file's SHA-256 by the body's name (the file's name without `.glb`, as the measure names
    it), which a report carries as `bodies_sha256`."""
    return {Path(path).stem: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in sorted(map(str, paths))}


def self_test():
    failed = False
    for name, (text, expected) in CASES.items():
        found = text_sha256(text)
        print(f"{'ok' if found == expected else 'DIFFERENT'} {name}: {found}")
        failed = failed or found != expected
    return failed


if __name__ == "__main__":
    arguments = sys.argv[1:]
    if "--self-test" in arguments:
        sys.exit(1 if self_test() else 0)
    print(f"measure_sha256 {script_sha256()}")
    for body, digest in bodies_sha256(arguments).items():
        print(f"bodies_sha256 {body} {digest}")
