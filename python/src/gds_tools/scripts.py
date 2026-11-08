"""`gds check scripts`: every GDScript of a Godot project parses (docs/engines/godot/new-game.md#proof).

An import and a short run of the main scene load only the scripts the scene reaches. A script that names an autoload
the project does not register (the `gds_ui` demo without `UIRouter`) is first loaded by the editor or an export, so it
passed a game's whole CI and opened with errors (kit #814). This runs the pinned Godot headless with the kit's
`godot/tools/check_scripts.gd`, which loads each `.gd` fresh as the editor does, and reports every script that does
not load. The project is imported first, so the global class cache exists.
"""

from __future__ import annotations

import re
import subprocess
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

SCRIPT = Path("godot") / "tools" / "check_scripts.gd"
IMPORT_TIMEOUT = 600  # seconds
CHECK_TIMEOUT = 600

_FAILED = re.compile(r"^PARSE FAIL: (.+)$", re.MULTILINE)
_PARSED = re.compile(r"^PARSED: (\d+) script\(s\), (\d+) failed$", re.MULTILINE)
_DETAIL = re.compile(r"^(SCRIPT ERROR: .*|ERROR: Failed to load script .*)$", re.MULTILINE)

#: A started program: its command, folder and timeout in seconds -> (exit code, output).
Runner = Callable[[Sequence[str], Path, float], tuple[int, str]]


class ScriptCheckError(Exception):
    """The check could not run (no Godot output at all, a timeout), as opposed to a script failing."""


@dataclass(frozen=True)
class Report:
    """How many scripts were loaded, the ones that did not load and Godot's own lines about why."""

    parsed: int
    failed: list[str]
    details: list[str]

    @property
    def ok(self) -> bool:
        return not self.failed


def run_program(cmd: Sequence[str], cwd: Path, timeout: float) -> tuple[int, str]:
    """Run `cmd` and return its exit code and its output (both streams, text)."""
    try:
        done = subprocess.run(
            list(cmd), cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=timeout, check=False,
        )  # fmt: skip
    except subprocess.TimeoutExpired as error:
        raise ScriptCheckError(f"{Path(cmd[0]).name} did not finish within {timeout:g} s") from error
    return done.returncode, (done.stdout or "") + (done.stderr or "")


def parse_output(output: str) -> Report:
    """The report in what the check script printed; ScriptCheckError when it never reached its last line."""
    total = _PARSED.search(output)
    if total is None:
        tail = "\n".join(output.strip().splitlines()[-8:])
        raise ScriptCheckError(f"the check script did not finish; Godot printed:\n{tail}")
    details = list(dict.fromkeys(_DETAIL.findall(output)))  # a script that names UIRouter five times prints five lines
    return Report(int(total.group(1)), _FAILED.findall(output), details)


def check(godot: Path, project: Path, kit: Path, run: Runner = run_program) -> Report:
    """Import `project`, then load every script of it with `godot`; `kit` holds the check script."""
    project = project.resolve()
    if not (project / "project.godot").is_file():
        raise FileNotFoundError(f"{project} holds no project.godot")
    script = (kit / SCRIPT).resolve()
    if not script.is_file():
        raise FileNotFoundError(f"{script} is missing: the kit checkout is incomplete")
    run([str(godot), "--headless", "--path", str(project), "--import"], project, IMPORT_TIMEOUT)
    _, output = run([str(godot), "--headless", "--path", str(project), "-s", str(script)], project, CHECK_TIMEOUT)
    return parse_output(output)
