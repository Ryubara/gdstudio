"""The workspace and the kit: the tool groups the guards judge, globs, git, the workspace by its marker file, the
kit checkout and the kit modules loaded by file, and the `gds` commands started in the background."""

from __future__ import annotations

import importlib.util
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

SHELL_TOOLS = ("Bash", "PowerShell")
EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
AGENT_TOOLS = ("Agent", "Task")
MARKER = ".gdstudio-workspace"
WARNINGS: list[str] = []  # what a guard could not check in this hook run; the dispatcher says them (take_warnings)


def take_warnings() -> list[str]:
    """The warnings the guards gave since the last call, once: a guard that fails open says so here."""
    taken, WARNINGS[:] = list(WARNINGS), []
    return taken


def glob_regex(pattern: str) -> re.Pattern[str]:
    """A glob as a regex over forward-slash paths: `**` any folders, `*` within a folder; a leading `**/` matches at
    any depth, otherwise the pattern is anchored at the start."""
    out, i = "", 0
    lead = pattern.startswith("**/")
    body = pattern[3:] if lead else pattern
    while i < len(body):
        if body.startswith("**", i):
            out, i = out + ".*", i + 2
        elif body[i] == "*":
            out, i = out + "[^/]*", i + 1
        elif body[i] == "?":
            out, i = out + "[^/]", i + 1
        else:
            out, i = out + re.escape(body[i]), i + 1
    return re.compile(("(?:^|.*/)" if lead else "^") + out + "$")


def matches(path: str, patterns: list[str]) -> bool:
    """True when `path` (any slashes) matches one of the globs."""
    norm = path.replace("\\", "/")
    return any(glob_regex(p).match(norm) for p in patterns)


def git(cwd: Path, *args: str) -> str:
    """A git command's output, '' when it fails (not a repository, git missing)."""
    try:
        result = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def workspace_of(path: Path) -> Path | None:
    """The GDStudio workspace holding `path`, by its marker file."""
    for folder in (path, *path.parents):
        if (folder / MARKER).exists():
            return folder
    return None


KIT = Path(__file__).resolve().parents[3]  # .claude/hooks/guards/workspace.py: the kit checkout


def kit_root(workspace: Path | None) -> Path:
    """The kit checkout of the workspace (its docs are the ones agents read), else the kit this file belongs to."""
    if workspace and (workspace / "repos" / "gdstudio").is_dir():
        return workspace / "repos" / "gdstudio"
    return KIT


def load_kit_module(name: str, kit: Path = KIT, cached: bool = False) -> Any:
    """`python/src/gds_tools/<name>.py` of a kit checkout, loaded by file (the hooks run without the `gds` package, so
    the modules they load use the standard library only); with `cached`, a module loaded before is kept. None when it
    cannot be loaded: a hook never locks a session out, and no check beats a crash."""
    key = f"_gds_{name}_for_hooks"
    if cached and key in sys.modules:
        return sys.modules[key]
    try:
        spec = importlib.util.spec_from_file_location(key, kit / "python" / "src" / "gds_tools" / f"{name}.py")
        module = importlib.util.module_from_spec(spec)
        sys.modules[key] = module  # a dataclass looks its module up here
        spec.loader.exec_module(module)
        return module
    except Exception:
        sys.modules.pop(key, None)
        return None


def load_pr_module() -> Any:
    """`gds_tools/pr.py` of the kit this file belongs to (the pull request rules); None when it cannot be loaded."""
    return load_kit_module("pr")


def lessons_module(kit: Path) -> Any:
    """`gds_tools/lessons.py` of a kit checkout (the docs' sections); None when it cannot be loaded."""
    return load_kit_module("lessons", kit)


def issues_module(kit: Path) -> Any:
    """`gds_tools/issues.py` of the kit, loaded once, so the hook computes the window with the code `gds issue start`
    uses. None when it cannot be loaded."""
    return load_kit_module("issues", kit, cached=True)


def start_background(
    workspace: Path,
    rules: dict[str, Any],
    gds_args: list[str],
    default_stamp: str,
    default_log: str,
    default_every: float,
    force: bool,
) -> bool:
    """Start `gds <gds_args>` in the background, at most once every `rules["every_seconds"]` (a stamp file's age)
    unless `force`, its output appended to `rules["log"]`. Returns whether it was started."""
    stamp = workspace / rules.get("stamp", default_stamp)
    try:
        recent = time.time() - stamp.stat().st_mtime < float(rules.get("every_seconds", default_every))
    except OSError:
        recent = False
    if recent and not force:
        return False
    uv, kit = shutil.which("uv"), kit_root(workspace)
    if not uv or not (kit / "python").is_dir():
        return False
    log = workspace / rules.get("log", default_log)
    command = [uv, "run", "--project", str(kit / "python"), "gds", *gds_args]
    try:
        stamp.parent.mkdir(parents=True, exist_ok=True)
        stamp.touch()
        log.parent.mkdir(parents=True, exist_ok=True)
        if log.exists() and log.stat().st_size > int(rules.get("max_log_bytes", 1_000_000)):
            os.replace(log, log.with_suffix(".old.log"))
        with log.open("ab") as out:
            # Windows: no console window for it or its git children; a job object of the hook runner may forbid
            # breaking away from it, so that flag is tried first and dropped when refused.
            flags = [0x08000000 | 0x00000200 | 0x01000000, 0x08000000 | 0x00000200] if os.name == "nt" else [0]
            for creation in flags:
                try:
                    subprocess.Popen(
                        command,
                        cwd=str(workspace),
                        stdin=subprocess.DEVNULL,
                        stdout=out,
                        stderr=subprocess.STDOUT,
                        creationflags=creation,
                        start_new_session=os.name != "nt",
                    )
                    return True
                except PermissionError:
                    continue
    except OSError:
        pass
    return False
