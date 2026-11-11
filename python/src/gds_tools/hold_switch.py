"""The maintainer's hold switch (docs/studio/hooks.md#hold): whether the coordinator may take `S-hold` off a pull
request. It lives in the workspace's untracked `gdstudio.local.toml`, under `[hold]`, and only the maintainer turns it
on or off, by hand in an editor: the hooks refuse an agent that writes that file or that key.

Standard library only: the hooks load this file by its path (`load_kit_module`), without the `gds` package.
"""

from __future__ import annotations

import tomllib
from dataclasses import dataclass
from pathlib import Path

FILE = "gdstudio.local.toml"  # workspace.LOCAL_FILE; a test keeps them equal
SECTION = "hold"
KEY = "coordinator_may_lift"
SINCE = "since"  # optional: the date the maintainer turned it on
BY = "by"  # optional: who turned it on
LOG = "scratch/hold-lifts.log"  # every lift the guard lets through, relative to the workspace


@dataclass(frozen=True)
class Switch:
    """The switch as the file has it: on only when the key is the TOML boolean `true`."""

    on: bool
    since: str = ""
    by: str = ""

    def describe(self) -> str:
        """One line for `gds doctor` and the guard's answers."""
        if not self.on:
            return "off: only the maintainer takes S-hold off"
        parts = [f"since {self.since}" if self.since else "", f"by {self.by}" if self.by else ""]
        who = " ".join(part for part in parts if part)
        return f"on{f' ({who})' if who else ''}: the coordinator may take S-hold off; task agents still may not"


def read(workspace: Path | None) -> Switch:
    """The switch of a workspace. Off when the file, the section or the key is missing, when the key is anything but
    the boolean `true` (a string "true" is off), and when the file cannot be read: the refusal is the default."""
    if workspace is None:
        return Switch(False)
    try:
        data = tomllib.loads((workspace / FILE).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return Switch(False)
    section = data.get(SECTION)
    if not isinstance(section, dict) or section.get(KEY) is not True:
        return Switch(False)
    return Switch(True, str(section.get(SINCE, "")), str(section.get(BY, "")))


def section_text(text: str) -> str:
    """The `[hold]` table of a gdstudio.local.toml as written, header included, '' when it has none: what `gds
    workspace init` carries over when it writes the file again, so a refresh never turns the switch off or on."""
    lines, kept, inside = text.splitlines(), [], False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            inside = stripped == f"[{SECTION}]"
        if inside:
            kept.append(line)
    while kept and not kept[-1].strip():
        kept.pop()
    return "\n".join(kept)
