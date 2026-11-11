"""`gds template bench-web <template> <bench>`: a template's bench scene as a web build, in a throwaway game
(docs/engines/godot/web-probes.md#bench-web).

A bench (`tools/bench/<name>.tscn`) measures a cost; its numbers that count are the browser's. The web build of a game
starts `run/main_scene` and leaves `tools/*` out of the pack, so each bench author made a game, swapped the main scene,
opened the Web preset's exclude filter and exported by hand. This does it in one step on a game made from the working
tree's template (`template_test.make_game`, a throwaway workspace of its own): the template's files never change.
The build's folder is printed and the game kept, or with `run` the bench's own probe (`<name>.py` beside the scene)
reads the build under `gds quiet` and the game is removed.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

from gds_tools import template_test, workspace

#: The Playwright the bench probes run with (as every browser probe: docs/engines/godot/web-probes.md).
PLAYWRIGHT = "1.64.1"
#: Where a template keeps its benches, and the preset and filter the web build uses.
BENCH_FOLDER = "tools/bench"
PRESET = "Web"
OPENED = "tools/*"
#: Seconds; a web export of 3D Third Person takes about a minute on a workstation.
EXPORT_TIMEOUT = 1800
ERROR = re.compile(r"ERROR")
#: The intermittent at-exit leak CI exports once more on (docs/engines/godot/test-exit-leaks.md).
LEAK = re.compile(r"still in use at exit|leaked at exit")

#: Runs a probe command with its output on the console -> its exit code.
ProbeRunner = Callable[[Sequence[str]], int]


class BenchWebError(Exception):
    """The bench, the project files or the export are not what the command needs; the message says what."""


@dataclass
class Result:
    """The exit code, and the build and game when they are kept."""

    code: int
    build: Path | None = None
    game: Path | None = None


def scene_path(project: Path, scene: str) -> str:
    """The bench's `res://` path from its name (`nav_cost_bench`), a project path or a `res://` path; it must exist."""
    name = scene.replace("\\", "/").removeprefix("res://").removeprefix("./")
    if not name.endswith(".tscn"):
        name += ".tscn"
    if "/" not in name:
        name = f"{BENCH_FOLDER}/{name}"
    if not (project / name).is_file():
        known = sorted(p.stem for p in (project / BENCH_FOLDER).glob("*.tscn"))
        raise BenchWebError(f"no scene res://{name} in the game; the benches are: {', '.join(known) or 'none'}")
    return f"res://{name}"


def set_main_scene(text: str, scene: str) -> str:
    """`project.godot` with `run/main_scene` set to `scene` in `[application]`; every other line as it was."""
    lines = text.replace("\r\n", "\n").split("\n")
    if "[application]" not in lines:
        raise BenchWebError("project.godot has no [application] section")
    entry = f'run/main_scene="{scene}"'
    start = lines.index("[application]")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
    for i in range(start + 1, end):
        if lines[i].startswith("run/main_scene="):
            lines[i] = entry
            return "\n".join(lines)
    last = max((i for i in range(start + 1, end) if lines[i].strip()), default=start)
    lines.insert(last + 1, entry)
    return "\n".join(lines)


def open_tools(text: str, preset: str = PRESET) -> str:
    """`export_presets.cfg` with `tools/*` out of the `preset` preset's exclude filter; the others as they were."""
    lines = text.replace("\r\n", "\n").split("\n")
    section, names, found = "", {}, False
    for line in lines:
        if line.startswith("["):
            section = line
        elif line.startswith("name="):
            names[section] = line.split("=", 1)[1].strip('"')
    for i, line in enumerate(lines):
        if line.startswith("["):
            section = line
        elif names.get(section) == preset and line.startswith("exclude_filter="):
            found = True
            kept = [p.strip() for p in line.split("=", 1)[1].strip('"').split(",") if p.strip() not in ("", OPENED)]
            lines[i] = f'exclude_filter="{", ".join(kept)}"'
    if not found:
        raise BenchWebError(f"export_presets.cfg has no {preset} preset with an exclude_filter")
    return "\n".join(lines)


def prepare(project: Path, scene: str) -> str:
    """Make the bench the game's main scene and let `tools/*` into the web pack; return the bench's `res://` path."""
    bench = scene_path(project, scene)
    godot_file, presets = project / "project.godot", project / "export_presets.cfg"
    # Bytes, not text mode: on Windows text mode writes every line ending as CRLF (studio/shell.md#line-endings).
    godot_file.write_bytes(set_main_scene(godot_file.read_text(encoding="utf-8"), bench).encode("utf-8"))
    presets.write_bytes(open_tools(presets.read_text(encoding="utf-8")).encode("utf-8"))
    return bench


def probe_of(project: Path, bench: str) -> Path | None:
    """The bench's browser probe: the `.py` of the same name beside the scene, or None."""
    probe = (project / bench.removeprefix("res://")).with_suffix(".py")
    return probe if probe.is_file() else None


def probe_command(kit: Path, probe: Path, build: Path, args: Sequence[str]) -> list[str]:
    """The probe under `gds quiet` (it can take the mouse: docs/engines/godot/no-focus.md), given the build first."""
    return [
        "uv", "run", "--project", str(kit / "python"), "gds", "quiet", "--",
        "uv", "run", "--with", f"playwright=={PLAYWRIGHT}", "python", str(probe), str(build), *args,
    ]  # fmt: skip


def export(godot: Path, project: Path, runner: template_test.Runner = template_test.run_program) -> Path:
    """Export the Web preset into the game's `build/web` with the pinned Godot; return the folder. An export whose
    only error is the at-exit leak is run once more, as CI does; any other error fails with its lines."""
    build = project.parent / "build" / "web"
    cmd = [str(godot), "--headless", "--path", str(project), "--export-release", PRESET, str(build / "index.html")]
    for attempt in range(2):
        shutil.rmtree(build, ignore_errors=True)
        build.mkdir(parents=True)
        code, output = runner(cmd, project, EXPORT_TIMEOUT)
        errors = [line for line in output.splitlines() if ERROR.search(line)]
        if errors and attempt == 0 and all(LEAK.search(line) for line in errors):
            continue
        if errors or code != 0:
            shown = "\n".join(errors[:20]) or output.strip()[-2000:]
            raise BenchWebError(f"the web export failed (exit {code}):\n{shown}")
        break
    for name in ("index.pck", "index.wasm"):
        if not (build / name).is_file():
            raise BenchWebError(f"the export wrote no {name} in {build}")
    return build


def run_probe(cmd: Sequence[str]) -> int:
    """Run the probe with its lines on the console (the bench's numbers are its output)."""
    return subprocess.run(list(cmd), check=False).returncode


def run_bench_web(
    kit: Path,
    real: Path,
    template: str,
    scene: str,
    *,
    run: bool = False,
    probe_args: Sequence[str] = (),
    keep: bool = False,
    runner: template_test.Runner = template_test.run_program,
    maker: template_test.Maker | None = None,
    probe_runner: ProbeRunner = run_probe,
    base: Path | None = None,
    log: template_test.Log = template_test.say,
) -> Result:
    """Make the game, swap in the bench, export it; keep it and say where, or with `run` read it with the probe and
    remove the game (unless `keep`). The throwaway workspace is removed on any failure."""
    godot = workspace.tool_path("godot", real)
    game = template_test.make_game(kit, real, template, runner=runner, maker=maker, base=base, log=log)
    folder = template_test.throwaway_of(game)
    project = game / "game"
    kept = False
    try:
        bench = prepare(project, scene)
        probe = probe_of(project, bench)
        if run and probe is None:
            raise BenchWebError(f"{bench} has no probe beside it ({Path(bench).stem}.py); export without --run")
        log(f"bench     {bench} is the main scene; {OPENED} is in the {PRESET} pack")
        build = export(godot, project, runner)
        log(f"build     {build}")
        if not run:
            kept = True
            log(f"game      {game} (remove it with `gds template clean {game}`)")
            if probe is not None:
                log("probe     " + " ".join(probe_command(kit, probe, build, probe_args)))
            return Result(code=0, build=build, game=game)
        assert probe is not None
        code = probe_runner(probe_command(kit, probe, build, probe_args))
        log(f"probe     {probe.name} exit {code}")
        kept = keep
        if keep:
            log(f"game      {game} (remove it with `gds template clean {game}`)")
            return Result(code=code, build=build, game=game)
        return Result(code=code)
    except BenchWebError as error:
        log(f"gds: {error}")
        return Result(code=1)
    finally:
        if not kept and not template_test.remove_throwaway(folder):
            log(f"warning   could not remove {folder}; delete it by hand")
