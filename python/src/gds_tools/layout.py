"""`gds check layout`: the folder, naming and dependency rules of a game's Godot project.

The rules are the kit's `docs/engines/godot/project-conventions.md`; this module is the part of them a program can
judge, so a
game's CI fails on a hand-made exception instead of a review noticing it. It reads files only (no Godot, no git
beyond one `ls-files`), so it runs in a second on any machine.

What it cannot see is named on that page: a dependency through a `class_name` (only `res://` paths are read), a
feature folder that grew too big, a name that is snake_case but means nothing.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

#: The folders of a project root. A new top-level folder is a change to the conventions, not to a game.
TOP_FOLDERS = frozenset({"addons", "assets", "core", "gameplay", "net", "tests", "tools", "ui", "world"})

#: Which folder may use which: a file refers only to folders of its own rank or below. `addons` and `assets` are
#: leaves, `core` is the foundation, the game itself (`gameplay`, `world`, `net`) sits on it and `ui` on top.
#: Files at the project root (the composition root: `main.tscn`) and in `tests/` and `tools/` may use anything.
ORDER = "addons, assets < core < gameplay, world, net < ui"
RANKS: dict[str, int] = {"addons": 0, "assets": 0, "core": 1, "gameplay": 2, "world": 2, "net": 2, "ui": 3}

#: Folder names that say nothing about what is inside.
VAGUE_FOLDERS = frozenset({"common", "misc", "vendor", "utils", "util", "helpers", "stuff", "temp", "tmp"})

#: Upper-case names that stay as they are: a licence beside third-party files, a note beside a folder.
KEPT_NAMES = frozenset({"README.md", "LICENSE", "LICENSE.md", "CREDITS.md", "NOTICE.md"})

#: Generated or local folders the rules do not enter (`reports/` is the editor's GdUnit output, ignored by git).
SKIPPED = frozenset({".godot", ".git", "reports"})

#: Folders a export must leave out, as the export preset writes them.
EXPORT_EXCLUDES = ("tests/*", "tools/*")

TEXT_SUFFIXES = frozenset({".gd", ".tscn", ".tres", ".gdshader", ".cfg", ".godot"})

_FOLDER = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
_STEM = re.compile(r"^[a-z0-9]+(_[a-z0-9]+)*$")
_CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.MULTILINE)
_RES_PATH = re.compile(r"res://([A-Za-z0-9_.\-]+)/")
_EXT_RESOURCE = re.compile(r'^\[ext_resource\b[^\]]*?\bpath="([^"]+)"[^\]]*?\bid="([^"]+)"', re.MULTILINE)
_EXCLUDE_FILTER = re.compile(r'^exclude_filter="([^"]*)"', re.MULTILINE)


@dataclass(frozen=True)
class Problem:
    """One broken rule: the file or folder (relative to the project), the rule's name and what is wrong."""

    path: str
    rule: str
    message: str

    def __str__(self) -> str:
        return f"{self.path}: [{self.rule}] {self.message}"


def _entries(project: Path) -> list[Path]:
    """Every file and folder of the project except the skipped folders (and, below `addons/`, nothing: an addon
    is somebody else's naming, so it is judged only as a source of references, which it never is)."""
    found = []
    for path in sorted(project.rglob("*")):
        parts = path.relative_to(project).parts
        if any(part in SKIPPED for part in parts) or parts[0] == "addons":
            continue
        found.append(path)
    return found


def _rel(project: Path, path: Path) -> str:
    return path.relative_to(project).as_posix()


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def _top_level(project: Path) -> list[Problem]:
    return [
        Problem(
            folder.name,
            "top-level",
            f"`{folder.name}/` is not one of {', '.join(sorted(TOP_FOLDERS))}: put it in the folder it belongs to",
        )
        for folder in sorted(project.iterdir())
        if folder.is_dir() and not folder.name.startswith(".") and folder.name not in SKIPPED | TOP_FOLDERS
    ]


def _names(project: Path, entries: list[Path]) -> list[Problem]:
    problems = []
    for path in entries:
        name = path.name
        if name.startswith(".") or name in KEPT_NAMES:
            continue
        if path.is_dir():
            if not _FOLDER.match(name):
                problems.append(Problem(_rel(project, path), "snake-case", "a folder is named in snake_case"))
            if name in VAGUE_FOLDERS:
                problems.append(
                    Problem(
                        _rel(project, path), "vague-folder", f"`{name}` says nothing: name the folder for its contents"
                    )
                )
        elif not _STEM.match(name.split(".")[0]):
            problems.append(Problem(_rel(project, path), "snake-case", "a file is named in snake_case"))
    return problems


def _pascal(stem: str) -> str:
    return stem.replace("_", "").lower()


def _classes(project: Path, entries: list[Path]) -> list[Problem]:
    """A script's `class_name` is its file name in PascalCase (`ui_router.gd` holds `UIRouter` or `UiRouter`)."""
    problems = []
    for path in entries:
        if path.suffix != ".gd":
            continue
        found = _CLASS_NAME.search(_text(path))
        if found and found.group(1).lower() != _pascal(path.stem):
            problems.append(
                Problem(
                    _rel(project, path),
                    "class-name",
                    f"class_name {found.group(1)} does not match the file: rename one to the other",
                )
            )
    return problems


def _scene_scripts(project: Path, entries: list[Path]) -> list[Problem]:
    """The script on a scene's root node sits beside the scene and has its name (`player.tscn`, `player.gd`)."""
    problems = []
    for path in entries:
        if path.suffix != ".tscn":
            continue
        text = _text(path)
        scripts = {ident: res for res, ident in _EXT_RESOURCE.findall(text) if res.endswith(".gd")}
        nodes = [block for block in re.split(r"^(?=\[node )", text, flags=re.MULTILINE) if block.startswith("[node ")]
        if not nodes:
            continue
        attached = re.search(r'^script = ExtResource\("([^"]+)"\)', nodes[0], re.MULTILINE)
        script = scripts.get(attached.group(1)) if attached else None
        if script is None or script.startswith("res://addons/"):
            continue
        expected = "res://" + path.relative_to(project).with_suffix(".gd").as_posix()
        if script != expected:
            problems.append(
                Problem(
                    _rel(project, path),
                    "scene-script",
                    f"its root script is {script}: a scene's script is {expected} (same folder, same name)",
                )
            )
    return problems


def _uids(project: Path, entries: list[Path]) -> list[Problem]:
    """Godot writes `<script>.uid` beside every script and shader; one that is not committed shows up untracked in
    every checkout."""
    return [
        Problem(_rel(project, path), "uid", f"{path.name}.uid is missing: open the project once and commit it")
        for path in entries
        if path.suffix in {".gd", ".gdshader"} and not path.with_name(path.name + ".uid").exists()
    ]


def _rank_of(project: Path, path: Path) -> int | None:
    """The rank of the folder a file is in; None for the files that may use anything (the root, tests, tools)."""
    parts = path.relative_to(project).parts
    return RANKS.get(parts[0]) if len(parts) > 1 else None


def _dependencies(project: Path, entries: list[Path]) -> list[Problem]:
    """Paths only point down: `core` never names `gameplay`, `gameplay` never names `ui`; shipped code never names
    `tools/` or `tests/`."""
    problems = []
    for path in entries:
        if path.suffix not in TEXT_SUFFIXES or not path.is_file():
            continue
        top = path.relative_to(project).parts[0]
        own = _rank_of(project, path)
        seen: set[str] = set()
        for target in _RES_PATH.findall(_text(path)):
            if target in seen:
                continue
            seen.add(target)
            if (
                target in {"tools", "tests"}
                and top not in {"tools", "tests"}
                and len(path.relative_to(project).parts) > 1
            ):
                problems.append(
                    Problem(
                        _rel(project, path),
                        "ships-tools",
                        f"shipped code refers to res://{target}/, which the export leaves out",
                    )
                )
            elif own is not None and target in RANKS and RANKS[target] > own:
                problems.append(
                    Problem(
                        _rel(project, path),
                        "dependency",
                        f"{top}/ refers to res://{target}/, which sits above it (the order is {ORDER})",
                    )
                )
    return problems


def _export(project: Path) -> list[Problem]:
    presets = project / "export_presets.cfg"
    if not presets.is_file():
        return []
    problems = []
    for number, filt in enumerate(_EXCLUDE_FILTER.findall(_text(presets))):
        left_in = [pattern for pattern in EXPORT_EXCLUDES if pattern not in {p.strip() for p in filt.split(",")}]
        if left_in:
            problems.append(
                Problem(
                    "export_presets.cfg",
                    "export",
                    f"preset {number} exports {', '.join(left_in)}: add it to exclude_filter",
                )
            )
    return problems


def _reports(project: Path) -> list[Problem]:
    """Test reports are generated files: written outside the project (`-rd`), never committed under it."""
    run = subprocess.run(
        ["git", "-C", str(project), "ls-files", "--", "reports"], capture_output=True, text=True, check=False
    )
    if run.returncode != 0 or not run.stdout.strip():
        return []
    return [Problem("reports", "generated", "generated test reports are committed: write them outside res:// with -rd")]


def check(project: Path) -> list[Problem]:
    """Every broken rule of the Godot project at `project` (the folder holding `project.godot`)."""
    project = project.resolve()
    if not (project / "project.godot").is_file():
        raise FileNotFoundError(f"{project} holds no project.godot")
    entries = _entries(project)
    return [
        *_top_level(project),
        *_names(project, entries),
        *_classes(project, entries),
        *_scene_scripts(project, entries),
        *_uids(project, entries),
        *_dependencies(project, entries),
        *_export(project),
        *_reports(project),
    ]
