"""`gds template test <name>` and `gds template game <name>`: run a template's suites where it can run
(docs/engines/godot/new-game.md#proof).

A template's tests cannot run in `templates/<t>/game`: GdUnit4 is installed into a made game, and `gds_ui` comes from
`gds sync`. So the command does what an agent did by hand before: it builds a throwaway workspace of its own (a new
folder under the system temp folder, with the marker, the local file and the GdUnit4 folder, so `gds new game` never
finds the real workspace), makes the game from the working tree's template (uncommitted changes included), imports
it, parses every script, runs the suites with the command CI uses, and removes the folder it made, and only that one.

The folder name comes from `tempfile.mkdtemp`, never a fixed name: two agents once shared a fixed folder in the
session's scratchpad, and one's clean-up deleted the other's game.
"""

from __future__ import annotations

import os
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from pathlib import Path

from gds_tools import layout, new_game, scripts, workspace
from gds_tools.manifest import load_tools

#: Every throwaway workspace starts with this, and nothing else is ever removed.
PREFIX = "gds-tt-"
#: The game's name inside the throwaway workspace (a unique workspace makes a fixed game name safe).
GAME_NAME = "template-check"
#: The pinned tools a throwaway workspace needs besides the local file: what CI fetches for a template (`ci.yml`).
ADDONS = ("gdunit4",)
GDUNIT_SCRIPT = "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"
DEFAULT_SUITES = ("res://tests",)
#: Seconds. A suite that never ends is a stuck debugger or a wait on a clock that does not tick, not a slow run.
IMPORT_TIMEOUT = 600
GDUNIT_TIMEOUT = 3000
#: The clock the template job of `ci.yml` runs the suites at (`--fixed-fps 60`); the command defaults to it so a green
#: local run is a green CI run. A test pins that `ci.yml` passes the same number.
CI_FIXED_FPS = 60
#: What CI refuses in the test log (`ci.yml`, step "Run the tests (GdUnit4)").
LEAKS = re.compile(r"leaked at exit|still in use")

#: A started program: its command, folder and timeout in seconds -> (exit code, output).
Runner = Callable[[Sequence[str], Path, float], tuple[int, str]]
#: Make the game: (kit, workspace, name, template) -> the game's repository.
Maker = Callable[[Path, Path, str, str], Path]
Log = Callable[[str], None]


def say(line: str) -> None:
    """A line of progress, flushed: a run takes minutes and a pipe would hold the lines back until it ended."""
    print(line, flush=True)


class TemplateTestError(Exception):
    """The throwaway workspace or the game cannot be made; the message says what to change."""


@dataclass(frozen=True)
class Suite:
    """One test suite of a GdUnit4 run: its file, the cases it ran, how many failed and how long it took, and the
    first line of each failed case's message."""

    path: str
    cases: int
    failures: int
    errors: int
    seconds: float
    failed: tuple[str, ...] = ()

    @property
    def ok(self) -> bool:
        return self.failures == 0 and self.errors == 0


@dataclass
class Result:
    """What a run left: the exit code, the suites it ran and where the game and the log are."""

    code: int
    suites: list[Suite] = field(default_factory=list)
    game: Path | None = None
    workspace: Path | None = None
    log: Path | None = None
    kept: bool = False


def run_program(cmd: Sequence[str], cwd: Path, timeout: float) -> tuple[int, str]:
    """Run `cmd` and return its exit code and its output (both streams, text); a timeout ends it and reports 124."""
    try:
        done = subprocess.run(
            list(cmd), cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=timeout, check=False,
        )  # fmt: skip
    except subprocess.TimeoutExpired as error:
        partial = error.stdout or b""
        text = partial.decode("utf-8", "replace") if isinstance(partial, bytes) else partial
        return 124, f"{text}\n{Path(cmd[0]).name} did not finish within {timeout:g} s\n"
    return done.returncode, (done.stdout or "") + (done.stderr or "")


def make_throwaway(real: Path, kit: Path, base: Path | None = None) -> Path:
    """A new workspace of its own: a unique folder under the system temp folder (`base`, for a test), with the marker,
    a copy of the local file (the tool paths) and a copy of each addon folder the game needs under `tools/`.

    It is never inside the real workspace: a folder there would find the real marker, and the game would land in the
    real `repos/` (new-game.md#proof); one of its own makes `gds new game --workspace` use it."""
    folder = Path(tempfile.mkdtemp(prefix=PREFIX, dir=base)).resolve()
    real = real.resolve()
    if folder == real or real in folder.parents:
        shutil.rmtree(folder, ignore_errors=True)
        raise TemplateTestError(
            f"the temporary folder {folder.parent} is inside the workspace {real}; point TMP or TEMP (TMPDIR) elsewhere"
        )
    try:
        shutil.copyfile(real / workspace.MARKER, folder / workspace.MARKER)
        local = real / workspace.LOCAL_FILE
        if not local.is_file():
            raise TemplateTestError(f"{local} is missing; run `gds workspace init`")
        shutil.copyfile(local, folder / workspace.LOCAL_FILE)
        (folder / "repos").mkdir()
        for tool in load_tools(kit / "tools.toml").values():
            if tool.name not in ADDONS:
                continue
            source = real / "tools" / tool.folder
            if not source.is_dir():
                raise TemplateTestError(f"{tool.name} is not installed; run `gds workspace init --fetch {tool.name}`")
            shutil.copytree(source, folder / "tools" / tool.folder)
    except BaseException:
        remove_throwaway(folder)
        raise
    return folder


def remove_throwaway(folder: Path) -> bool:
    """Remove a folder this module made and nothing else (its name starts with `PREFIX`); False when something stays.

    Git writes read-only object files and Godot may still hold a file for a moment, so a failure is retried after the
    read-only bit is cleared."""
    if not folder.name.startswith(PREFIX):
        raise TemplateTestError(f"{folder} was not made by this command; it is not removed")

    def clear(function, path, _error):
        os.chmod(path, stat.S_IWRITE)
        function(path)

    for attempt in range(5):
        try:
            shutil.rmtree(folder, onexc=clear)
        except OSError:
            time.sleep(0.5 * (attempt + 1))
        if not folder.exists():
            return True
    return False


def throwaway_of(path: Path) -> Path:
    """The throwaway workspace that holds `path` (or is it); TemplateTestError for a path this command did not make."""
    for folder in (path.resolve(), *path.resolve().parents):
        if folder.name.startswith(PREFIX) and (folder / workspace.MARKER).is_file():
            return folder
    raise TemplateTestError(f"{path} is not in a workspace made by `gds template`; it is not removed")


def default_maker() -> Maker:
    """`gds new game --local` in the throwaway workspace, from the kit checkout `gds` runs from. The hooks are not
    installed (they come from the network and a throwaway game never commits); everything else is the real command."""

    def quiet_run(argv, *args, **kwargs):
        if argv and argv[0] == "uvx":
            return subprocess.CompletedProcess(argv, 0, "", "")
        return subprocess.run(argv, *args, **kwargs)

    def make(kit: Path, root: Path, name: str, template: str) -> Path:
        # The command's own lines (what it wrote, which addon it did not find) are not this command's output.
        return new_game.new_game(kit, root, name, template, log=lambda _: None, run=quiet_run).repo

    return make


def gdunit_command(
    godot: Path,
    project: Path,
    report_dir: Path,
    suites: Sequence[str],
    fixed_fps: int | None,
    godot_args: Sequence[str],
    gdunit_args: Sequence[str],
) -> list[str]:
    """The command of the template job in `ci.yml`: one `-a` per suite, `-c` to go on after a failure, the report
    folder outside the project, and `--ignoreHeadlessMode` because GdUnit4 refuses a headless run otherwise."""
    cmd = [str(godot), "--headless", "--path", str(project)]
    if fixed_fps:
        cmd += ["--fixed-fps", str(fixed_fps)]
    cmd += [*godot_args, "-s", GDUNIT_SCRIPT]
    for suite in suites:
        cmd += ["-a", suite]
    cmd += ["-rd", str(report_dir), "-c", "--ignoreHeadlessMode", "--verbose", *gdunit_args]
    return cmd


def parse_reports(report_dir: Path) -> list[Suite]:
    """The suites of the newest JUnit report GdUnit4 wrote in `report_dir`, in the order they ran."""
    reports = sorted(report_dir.rglob("results.xml"), key=lambda p: p.stat().st_mtime)
    if not reports:
        return []
    suites = []
    for node in ET.parse(reports[-1]).getroot().iter("testsuite"):
        failed = []
        for case in node.iter("testcase"):
            problem = case.find("failure") if case.find("failure") is not None else case.find("error")
            if problem is not None:
                message = (problem.get("message") or problem.text or "").strip().splitlines()
                failed.append(f"{case.get('name')}: {message[0] if message else ''}".rstrip(": "))
        package = node.get("package", "")
        suites.append(
            Suite(
                path=f"{package}/{node.get('name', '?')}.gd".removeprefix("/"),
                cases=int(node.get("tests", 0)),
                failures=int(node.get("failures", 0)),
                errors=int(node.get("errors", 0)),
                seconds=float(node.get("time", 0)),
                failed=tuple(failed),
            )
        )
    return suites


def normalise_suite(suite: str) -> str:
    """`tests/test_x.gd` or `test_x.gd` as GdUnit4 wants it: `res://tests/test_x.gd`."""
    if suite.startswith("res://"):
        return suite
    suite = suite.replace("\\", "/").removeprefix("./")
    return f"res://{suite}" if "/" in suite else f"res://tests/{suite}"


def run_template_test(
    kit: Path,
    real: Path,
    template: str,
    *,
    suites: Sequence[str] = (),
    keep: bool = False,
    fixed_fps: int | None = CI_FIXED_FPS,
    godot_args: Sequence[str] = (),
    gdunit_args: Sequence[str] = (),
    timeout: float = GDUNIT_TIMEOUT,
    runner: Runner = run_program,
    maker: Maker | None = None,
    base: Path | None = None,
    log: Log = say,
) -> Result:
    """Make a throwaway workspace and a game from `template`, parse its scripts and run its suites; return the result.

    The throwaway workspace is removed on success, on failure and on an interrupt, unless `keep`."""
    new_game.load_template(kit, template)  # an unknown template fails before anything is made
    godot = workspace.tool_path("godot", real)
    asked = [normalise_suite(s) for s in suites] or list(DEFAULT_SUITES)
    folder = make_throwaway(real, kit, base)
    result = Result(code=1, workspace=folder, kept=keep)
    try:
        # The source first: the checkout whose `gds` runs (its module path), never the current folder (kit #1048).
        log(f"kit       {kit} ({workspace.describe_kit(kit)})")
        log(f"workspace {folder}")
        started = time.monotonic()
        game = (maker or default_maker())(kit, folder, GAME_NAME, template)
        project = game / "game"
        result.game = game
        log(f"game      {game} (from {kit}) in {time.monotonic() - started:.0f} s")

        problems = layout.check(project)
        for problem in problems:
            log(f"  {problem}")
        if problems:
            log(f"layout: {len(problems)} problem(s)")
            return result
        log("layout    ok")

        report = scripts.check(godot, project, kit, runner)
        for path in report.failed:
            log(f"  {path}: does not parse")
        for line in report.details:
            log(f"    {line}")
        if not report.ok:
            log(f"scripts   {len(report.failed)} of {report.parsed} do not parse")
            return result
        log(f"scripts   {report.parsed} parse")

        reports = folder / "reports"
        log(f"gdunit    running {', '.join(asked)}")
        started = time.monotonic()
        code, output = runner(
            gdunit_command(godot, project, reports, asked, fixed_fps, godot_args, gdunit_args), project, timeout
        )
        result.log = folder / "gdunit.log"
        result.log.write_text(output, encoding="utf-8")
        result.suites = parse_reports(reports)
        for suite in result.suites:
            mark = "ok  " if suite.ok else "FAIL"
            log(f"  {mark} {suite.path}  {suite.cases} cases, {suite.failures} failures, {suite.seconds:.1f} s")
            for line in suite.failed:
                log(f"         {line}")
        total = sum(s.cases for s in result.suites)
        bad = sum(s.failures + s.errors for s in result.suites)
        log(
            f"gdunit    exit {code}: {len(result.suites)} suites, {total} cases, {bad} failed, "
            f"{time.monotonic() - started:.0f} s"
        )
        if code == 0 and not result.suites:
            log("gdunit    no suite ran (a path that matches nothing exits 0); read the log")
            code = 1
        if code == 0 and LEAKS.search(output):
            log("gdunit    the log has 'leaked at exit' or 'still in use' lines, which CI refuses")
            code = 1
        if code != 0:
            if not any(suite.failed for suite in result.suites):
                tail = "\n".join(output.strip().splitlines()[-30:])
                log(f"--- end of the GdUnit4 output ---\n{tail}")
            keep_log = (base or Path(tempfile.gettempdir())) / f"{folder.name}.log"
            if not keep:
                shutil.copyfile(result.log, keep_log)
                result.log = keep_log
                log(f"log       {keep_log}")
        result.code = code
        return result
    finally:
        if keep:
            log(f"kept      {result.game or folder} (remove the folder {folder} when you are done)")
        elif not remove_throwaway(folder):
            log(f"warning   could not remove {folder}; delete it by hand")
        else:
            result.workspace = None
            result.game = None


def make_game(
    kit: Path,
    real: Path,
    template: str,
    *,
    runner: Runner = run_program,
    maker: Maker | None = None,
    base: Path | None = None,
    log: Log = say,
) -> Path:
    """A game made from the working tree's template in a throwaway workspace of its own, imported, and kept: for
    captures and probes. The caller removes the returned workspace folder (the game's grandparent) when it is done."""
    new_game.load_template(kit, template)
    godot = workspace.tool_path("godot", real)
    folder = make_throwaway(real, kit, base)
    log(f"kit       {kit} ({workspace.describe_kit(kit)})")
    try:
        game = (maker or default_maker())(kit, folder, GAME_NAME, template)
        code, output = runner(
            [str(godot), "--headless", "--path", str(game / "game"), "--import"], game, IMPORT_TIMEOUT
        )
        if code != 0:
            raise TemplateTestError(f"the import failed (exit {code}):\n{output.strip()[-2000:]}")
    except BaseException:
        remove_throwaway(folder)
        raise
    return game


def split_args(text: str | None) -> list[str]:
    """`"--a 1 --b"` -> `["--a", "1", "--b"]`: a pass-through given as one quoted argument."""
    return shlex.split(text) if text else []
