"""`gds sync`: keep the game-side copies of kit-owned files identical to the kit (docs/sync.md).

The kit is the one source of the files every game carries: the agent definitions (`.claude/agents/*.md`) and the
hook launcher with its settings (`templates/game/`). `gds sync <game>` writes them into the game and records their
hashes in `.claude/gds-sync.json`; `gds sync <game> --check` fails when a copy differs from the kit, so a hand edit in
a game (or a kit change not yet synced) is caught. Change these files in the kit, then sync each game in a pull
request of its own.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

LOCK = Path(".claude") / "gds-sync.json"


@dataclass(frozen=True)
class Entry:
    """One synced file: where it comes from in the kit and where it goes in a game."""

    source: Path
    target: str  # repository-relative, forward slashes


def entries(kit: Path) -> list[Entry]:
    """Every file the kit owns in a game."""
    found = [Entry(p, f".claude/agents/{p.name}") for p in sorted((kit / ".claude" / "agents").glob("*.md"))]
    templates = kit / "templates" / "game"
    found += [Entry(p, p.relative_to(templates).as_posix()) for p in sorted(templates.rglob("*")) if p.is_file()]
    return found


def digest(data: bytes) -> str:
    """The sha256 of file contents, with line endings normalised (Windows checkouts write CRLF)."""
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def drift(kit: Path, game: Path) -> list[str]:
    """What differs between the kit and a game: missing, changed or no-longer-owned files."""
    problems = []
    wanted = {e.target: digest(e.source.read_bytes()) for e in entries(kit)}
    for target, want in wanted.items():
        path = game / target
        if not path.exists():
            problems.append(f"{target}: missing (run `gds sync`)")
        elif digest(path.read_bytes()) != want:
            problems.append(f"{target}: differs from the kit (edit it in the kit, then run `gds sync`)")
    lock = game / LOCK
    if lock.exists():
        for target in json.loads(lock.read_text(encoding="utf-8")).get("files", {}):
            if target not in wanted and (game / target).exists():
                problems.append(f"{target}: no longer owned by the kit (delete it, then run `gds sync`)")
    return problems


def sync(kit: Path, game: Path, log=print) -> int:
    """Write the kit's files into a game and its lock; returns how many files changed."""
    changed = 0
    files = {}
    for entry in entries(kit):
        data = entry.source.read_bytes().replace(b"\r\n", b"\n")
        path = game / entry.target
        if not path.exists() or path.read_bytes().replace(b"\r\n", b"\n") != data:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            log(f"wrote   {entry.target}")
            changed += 1
        files[entry.target] = digest(data)
    lock = {"note": "Written by `gds sync` from the GDStudio kit; edit the kit, not these files.", "files": files}
    (game / LOCK).parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(lock, indent=2) + "\n"
    if not (game / LOCK).exists() or (game / LOCK).read_text(encoding="utf-8") != text:
        (game / LOCK).write_text(text, encoding="utf-8", newline="\n")
    return changed
