"""Code-quality numbers for the GDScript an eval delivery adds (docs/studio/agent-evals.md#quality).

A correctness suite says the code works; these numbers say how it is built: how long a script and a function get,
whether the public surface is documented, whether declarations are typed, and whether a per-frame function allocates.
They are line-based reads of the source (no Godot), so they are cheap, fixed and the same for every run. A function is
a `func` at the left margin and ends at the next line that starts at the left margin; an inner class is not looked
into. The rules are the project's own (`docs/engines/godot/gdscript.md`, `project-conventions.md`); the limits come
from the task's `[limits]` table.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

#: Functions the engine calls every frame: nothing in them may allocate.
HOT_FUNCTIONS = ("_process", "_physics_process", "_integrate_forces")

#: What allocates on every call: an object, a container literal, a string built, a node or child list fetched.
ALLOCATIONS = re.compile(
    r"\.new\(|\bstr\(|\.format\(|\"\s*%\s|\.duplicate\(|\bArray\(|\bDictionary\(|\bPacked\w+Array\(|"
    r"(?:[=(,:]|\breturn)\s*\[|(?:[=(,:]|\breturn)\s*\{|\bget_nodes_in_group\(|\bfind_children\(|\bget_children\(|"
    r"\bcreate_tween\(|\bCallable\(|\bfunc\s*\("
)

_FUNC = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\((.*)\)\s*(->\s*[\w.\[\], ]+)?\s*:")
_FUNC_OPEN = re.compile(r"^(?:static\s+)?func\s+(\w+)\s*\(")
_VAR = re.compile(r"^(?:(@\w+(?:\([^)]*\))?\s+)*)(?:static\s+)?var\s+(\w+)\s*(:=|:|=)?")
_SIGNAL = re.compile(r"^signal\s+(\w+)")
_ENUM = re.compile(r"^enum\b")
_EXPORT_ONLY = re.compile(r"^@export\w*(?:\([^)]*\))?\s*$")


@dataclass
class Stats:
    """What one script measures."""

    name: str
    lines: int = 0
    longest_function: int = 0
    longest_function_name: str = ""
    undocumented: list[str] = field(default_factory=list)
    untyped: list[str] = field(default_factory=list)
    allocations: list[str] = field(default_factory=list)


def _code_lines(text: str) -> list[str]:
    return text.replace("\r\n", "\n").split("\n")


def _split_params(params: str) -> list[str]:
    """The parameters of a signature, split at the commas that are not inside brackets."""
    parts, depth, current = [], 0, ""
    for char in params:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current.strip())
            current = ""
        else:
            current += char
    if current.strip():
        parts.append(current.strip())
    return parts


def _documented(lines: list[str], index: int) -> bool:
    """A `##` comment on the line above (annotations and blank lines between are skipped) or after the code."""
    if "##" in lines[index]:
        return True
    above = index - 1
    while above >= 0 and (_EXPORT_ONLY.match(lines[above].strip()) or lines[above].strip().startswith("@export_")):
        above -= 1
    return above >= 0 and lines[above].strip().startswith("##")


def _header_documented(lines: list[str]) -> bool:
    """The script says what it is: a `##` comment in the lines of `class_name` and `extends`, before or after them."""
    for line in lines[:12]:
        if line.startswith("##"):
            return True
        if line and not line.startswith(("class_name", "extends", "@tool", "@icon", "#")):
            break
    return False


def analyse(name: str, text: str) -> Stats:
    """The quality numbers of one script."""
    lines = _code_lines(text)
    stats = Stats(name=name, lines=len([ln for ln in lines if ln.strip()]))
    if not _header_documented(lines):
        stats.undocumented.append(f"{name}: the script has no `##` description at its top")
    current: str | None = None
    start = 0
    ended = len(lines)

    def close(end: int) -> None:
        nonlocal current
        if current is None:
            return
        body = [ln for ln in lines[start:end] if ln.strip() and not ln.strip().startswith("#")]
        if len(body) > stats.longest_function:
            stats.longest_function, stats.longest_function_name = len(body), current
        current = None

    for index, line in enumerate(lines):
        if line and not line[0].isspace() and not line.startswith("#"):
            close(index)
        if current is not None:
            if current in HOT_FUNCTIONS and ALLOCATIONS.search(line.split("#")[0]):
                stats.allocations.append(f"{name}:{index + 1} in {current}: {line.strip()}")
            continue
        stripped = line.rstrip()
        if _FUNC_OPEN.match(stripped):
            joined = stripped
            look = index
            while not re.search(r":\s*(#.*)?$", joined) and look + 1 < len(lines) and look < index + 12:
                look += 1
                joined += " " + lines[look].strip()
            match = _FUNC.match(joined.split("#")[0].rstrip())
            func = _FUNC_OPEN.match(stripped).group(1)
            current, start = func, index + 1
            if match is None:
                continue
            params = [p for p in _split_params(match.group(2)) if p]
            for param in params:
                if ":" not in param:
                    stats.untyped.append(f"{name}:{index + 1} {func}: parameter `{param}` has no type")
            if match.group(3) is None:
                stats.untyped.append(f"{name}:{index + 1} {func}: no return type")
            if not func.startswith("_") and not _documented(lines, index):
                stats.undocumented.append(f"{name}:{index + 1} func {func}")
            continue
        var = _VAR.match(stripped)
        if var and not line.startswith((" ", "\t")):
            member = var.group(2)
            if var.group(3) in (None, "="):
                stats.untyped.append(f"{name}:{index + 1} var {member} has no type")
            exported = stripped.startswith("@export") or (index > 0 and _EXPORT_ONLY.match(lines[index - 1].strip()))
            if (exported or not member.startswith("_")) and not _documented(lines, index):
                stats.undocumented.append(f"{name}:{index + 1} var {member}")
            continue
        sig = _SIGNAL.match(stripped)
        if sig and not _documented(lines, index):
            stats.undocumented.append(f"{name}:{index + 1} signal {sig.group(1)}")
        elif _ENUM.match(stripped) and not _documented(lines, index):
            stats.undocumented.append(f"{name}:{index + 1} enum")
    close(ended)
    return stats


def rows(scripts: dict[str, str], limits: dict) -> list[dict]:
    """The scored rows for the scripts a delivery added: `{name: source}` and the task's limits."""
    stats = [analyse(name, text) for name, text in sorted(scripts.items())]
    longest = max(stats, key=lambda s: s.lines, default=None)
    func = max(stats, key=lambda s: s.longest_function, default=None)
    undocumented = [item for s in stats for item in s.undocumented]
    untyped = [item for s in stats for item in s.untyped]
    hot = [item for s in stats for item in s.allocations]
    made = [
        ("new scripts", len(stats), ">=", limits.get("min_scripts", 2)),
        ("longest new script (code lines)", longest.lines if longest else 0, "<=", limits.get("max_script_lines", 150)),
        (
            "longest function (code lines)",
            func.longest_function if func else 0,
            "<=",
            limits.get("max_function_lines", 30),
        ),
        ("public members without a `##` doc comment", len(undocumented), "<=", limits.get("max_undocumented", 0)),
        ("declarations without a type", len(untyped), "<=", limits.get("max_untyped", 0)),
        ("allocations in a per-frame function", len(hot), "<=", limits.get("max_hot_allocations", 0)),
    ]
    out = []
    for name, value, op, limit in made:
        ok = value >= limit if op == ">=" else value <= limit
        out.append({"name": name, "value": value, "op": op, "limit": limit, "unit": "", "pass": bool(ok)})
    return out


def findings(scripts: dict[str, str]) -> list[str]:
    """Where each miss is, so the table can say what to fix."""
    found = []
    for name, text in sorted(scripts.items()):
        stats = analyse(name, text)
        found += stats.undocumented[:4] + stats.untyped[:4] + stats.allocations[:4]
    return found[:12]
