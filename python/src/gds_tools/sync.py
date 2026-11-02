"""`gds sync`: keep the game-side copies of kit-owned files identical to the kit (docs/sync.md).

The kit is the one source of the files every game carries: the agent definitions (`.claude/agents/*.md`), the
commit and pull request checker (`.github/scripts/groundwork.py`), the hook launcher with its settings
(`templates/game/`) and the message-check hooks of `.pre-commit-config.yaml`. The last is a file a game also writes
into (its own formatters), so only the blocks between `# gds-sync:begin <name>` and `# gds-sync:end <name>` lines are
the kit's; the kit's own config is their source. `gds sync <game>` writes all of it into the game and records the
hashes in `.claude/gds-sync.json`; `gds sync <game> --check` fails when a copy differs from the kit, so a hand edit in
a game (or a kit change not yet synced) is caught. Change these files in the kit, then sync each game in a pull
request of its own.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

LOCK = Path(".claude") / "gds-sync.json"

#: The kit files that are copied whole, besides the agent definitions and `templates/game/`.
SCRIPTS = (".github/scripts/groundwork.py",)

#: The one game file the kit owns only parts of: the hooks that judge commit messages and pushes.
BLOCK_FILE = ".pre-commit-config.yaml"
_BEGIN = re.compile(r"^[ \t]*# gds-sync:begin (\S+)")
_HOOK_ID = re.compile(r"^\s*- id: (\S+)", re.MULTILINE)


class SyncError(Exception):
    """A game cannot be synced as it is (its config lacks the kit's blocks); the message says what to add."""


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
    found += [Entry(kit / script, script) for script in SCRIPTS if (kit / script).is_file()]
    return found


def blocks(text: str) -> dict[str, str]:
    """The kit-owned blocks of a config file: name -> the lines from `# gds-sync:begin` to `# gds-sync:end`, both
    included, with a final newline. A begin without its end is a mistake in the file, so it raises."""
    found: dict[str, str] = {}
    lines = text.replace("\r\n", "\n").split("\n")
    i = 0
    while i < len(lines):
        match = _BEGIN.match(lines[i])
        if match:
            end = re.compile(rf"^[ \t]*# gds-sync:end {re.escape(match.group(1))}\s*$")
            j = next((k for k in range(i + 1, len(lines)) if end.match(lines[k])), None)
            if j is None:
                raise SyncError(f"{BLOCK_FILE}: `# gds-sync:begin {match.group(1)}` has no `# gds-sync:end` line")
            found[match.group(1)] = "\n".join(lines[i : j + 1]) + "\n"
            i = j
        i += 1
    return found


def block_entries(kit: Path) -> dict[str, str]:
    """The blocks the kit's own `.pre-commit-config.yaml` defines (none when it has no such file)."""
    source = kit / BLOCK_FILE
    return blocks(source.read_text(encoding="utf-8")) if source.is_file() else {}


def _hook_ids(text: str) -> list[str]:
    return _HOOK_ID.findall(text)


def digest(data: bytes) -> str:
    """The sha256 of file contents, with line endings normalised (Windows checkouts write CRLF)."""
    return hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest()


def block_drift(kit: Path, game: Path) -> list[str]:
    """What differs in the kit-owned blocks of the game's `.pre-commit-config.yaml`: a missing or changed block, or a
    kit hook defined a second time outside its block (an old copy from before the block existed)."""
    wanted = block_entries(kit)
    if not wanted:
        return []
    config = game / BLOCK_FILE
    if not config.exists():
        return [f"{BLOCK_FILE}: missing (the kit's hooks need a pre-commit config)"]
    text = config.read_text(encoding="utf-8").replace("\r\n", "\n")
    try:
        have = blocks(text)
    except SyncError as error:
        return [str(error)]
    problems = []
    for name, block in wanted.items():
        if name not in have:
            problems.append(f"{BLOCK_FILE}: no `# gds-sync:begin {name}` block (add the markers, then run `gds sync`)")
        elif have[name] != block:
            problems.append(f"{BLOCK_FILE}: block {name} differs from the kit (edit the kit, then run `gds sync`)")
    outside = text
    for block in have.values():
        outside = outside.replace(block, "")
    outside_ids = _hook_ids(outside)
    for name, block in wanted.items():
        for hook in _hook_ids(block):
            if hook in outside_ids:
                problems.append(f"{BLOCK_FILE}: hook {hook} is also defined outside the kit's block {name} (delete it)")
    return problems


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
    problems += block_drift(kit, game)
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
    block_hashes = {}
    wanted = block_entries(kit)
    config_text = None
    if wanted:
        if not (game / BLOCK_FILE).exists():
            raise SyncError(f"{game / BLOCK_FILE} does not exist; the kit's hooks need a pre-commit config")
        config_text = (game / BLOCK_FILE).read_text(encoding="utf-8").replace("\r\n", "\n")
        have = blocks(config_text)
        missing = [name for name in wanted if name not in have]
        if missing:
            raise SyncError(
                f"{BLOCK_FILE} of {game.name} has no block {', '.join(missing)}: once, wrap the game's own copy of "
                f"those hooks in `# gds-sync:begin <name>` / `# gds-sync:end <name>` lines (docs/sync.md), then run "
                f"`gds sync` again"
            )
        duplicated = [p for p in block_drift(kit, game) if "outside the kit's block" in p]
        if duplicated:
            raise SyncError("; ".join(duplicated))
    for entry in entries(kit):
        data = entry.source.read_bytes().replace(b"\r\n", b"\n")
        path = game / entry.target
        if not path.exists() or path.read_bytes().replace(b"\r\n", b"\n") != data:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            log(f"wrote   {entry.target}")
            changed += 1
        files[entry.target] = digest(data)
    if config_text is not None:
        have = blocks(config_text)
        new_text = config_text
        for name, block in wanted.items():
            new_text = new_text.replace(have[name], block)
            block_hashes[f"{BLOCK_FILE}#{name}"] = digest(block.encode())
        if new_text != config_text:
            (game / BLOCK_FILE).write_bytes(new_text.encode("utf-8"))
            log(f"wrote   {BLOCK_FILE} ({', '.join(n for n in wanted if have[n] != wanted[n])})")
            changed += 1
    lock = {"note": "Written by `gds sync` from the GDStudio kit; edit the kit, not these files.", "files": files}
    if block_hashes:
        lock["blocks"] = block_hashes
    (game / LOCK).parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(lock, indent=2) + "\n"
    if not (game / LOCK).exists() or (game / LOCK).read_text(encoding="utf-8") != text:
        (game / LOCK).write_text(text, encoding="utf-8", newline="\n")
    return changed
