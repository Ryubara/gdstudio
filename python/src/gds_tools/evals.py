"""Measured agent tasks: small fixed tasks with numbers to meet, so a change to an agent's page can be measured
(docs/studio/agent-evals.md).

A task is a folder `evals/<kind>/<name>/` of the kit with a `TASK.md` (TOML front matter between `+++` lines, then the
brief the agent gets) and, for a Blender task, `prepare.py` (writes the inputs) and `check.py` (measures the delivery);
both run in the pinned Blender, headless. A Godot task starts from a template and is judged by its own tests, the
task's acceptance suite and `gds check layout`.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import time
import tomllib
import xml.etree.ElementTree as ET
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from gds_tools import integrations, layout
from gds_tools.manifest import load_tools

Log = Callable[[str], None]
EVALS = "evals"
RESULT = "result.json"
RUNS = "checks.jsonl"  # one line per check run: how many runs a delivery took, and what the first one met
ACCEPTANCE_DIR = "tests/eval_acceptance"
GDTOOLKIT = "gdtoolkit==4.5.0"
PLACEHOLDERS = {"{GAME_TITLE}": "Eval", "{GAME_DESCRIPTION}": "An agent eval built from a template."}


class EvalError(Exception):
    """A task that does not exist, or a folder it cannot use."""


@dataclass(frozen=True)
class Task:
    name: str
    folder: Path
    title: str
    agent: str
    kind: str
    deliver: list[str] = field(default_factory=list)
    read: list[str] = field(default_factory=list)
    template: str = ""

    @property
    def brief(self) -> str:
        """TASK.md without its front matter."""
        return split_front(self.folder.joinpath("TASK.md").read_text(encoding="utf-8"))[1]


def split_front(text: str) -> tuple[dict, str]:
    """The TOML front matter of a TASK.md and the text after it."""
    match = re.match(r"\+\+\+\n(.*?)\n\+\+\+\n", text.replace("\r\n", "\n"), re.S)
    if not match:
        raise EvalError("TASK.md has no +++ front matter")
    return tomllib.loads(match.group(1)), text.replace("\r\n", "\n")[match.end() :].lstrip("\n")


def tasks(kit: Path) -> dict[str, Task]:
    """Every task of the kit, by name."""
    found = {}
    for path in sorted((kit / EVALS).glob("*/*/TASK.md")):
        front, body = split_front(path.read_text(encoding="utf-8"))
        heading = next((line[2:].strip() for line in body.splitlines() if line.startswith("# ")), path.parent.name)
        found[path.parent.name] = Task(
            name=path.parent.name,
            folder=path.parent,
            title=heading,
            agent=front["agent"],
            kind=front["kind"],
            deliver=list(front.get("deliver", [])),
            read=list(front.get("read", [])),
            template=front.get("template", ""),
        )
    return found


def get(kit: Path, name: str) -> Task:
    found = tasks(kit)
    if name not in found:
        raise EvalError(f"no eval named {name!r}; `gds eval list` prints them")
    return found[name]


GDS_PROJECT = "<workspace>/repos/gdstudio/python"


def prompt(task: Task, target: Path, issue: str, gds_project: str = GDS_PROJECT) -> str:
    """The fixed prompt of a run: the same words every time, so two runs differ only by the agent's page and docs."""
    lines = [f"Issue: {issue}"]
    lines += [f"Read: {ref}" for ref in task.read]
    lines += [
        "",
        f"This is a measured eval run (`{task.name}`, kit docs/studio/agent-evals.md), not issue work: open no branch,",
        "pull request or issue, and edit neither the kit nor a game. "
        "Work only in the eval folder below. The issue line",
        "above is the issue the run is made under; it is already started.",
        "",
        f"Eval folder: {target.as_posix()}",
        "",
        f"The brief is `{(target / 'TASK.md').as_posix()}` ({task.title}): read it first, it holds the task and the",
        "numbers the check measures.",
        "",
        f"When you are done, run `uv run --project {gds_project} gds eval check {task.name} {target.as_posix()}`,",
        "fix what you can, and end with your report: the check's last table as it printed, how long the work took,",
        "what you would do differently, a `Read:` line, "
        "a `Docs gaps:` line naming each section that was missing, wrong",
        "or out of date for this task (what the docs should have told you), "
        "and a `Mistakes:` line. An eval run edits no",
        "docs: put each mistake's learning in `Docs gaps:` "
        "and write `Mistakes: none (eval run, learnings in Docs gaps)`.",
    ]
    return "\n".join(lines)


def _run(cmd: list[str], log: Log, timeout: int = 900, cwd: Path | None = None) -> subprocess.CompletedProcess:
    log("run     " + " ".join(str(c) for c in cmd[:6]) + (" ..." if len(cmd) > 6 else ""))
    return subprocess.run(
        [str(c) for c in cmd],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
        cwd=cwd,
    )


def blender_cmd(blender: Path, script: Path, *args: str) -> list[str]:
    return [str(blender), "-b", "--factory-startup", "--python-exit-code", "1", "-P", str(script), "--", *args]


def prepare(task: Task, target: Path, kit: Path, tools_dir: Path, tool: Callable[[str], Path], log: Log) -> None:
    """Make the eval folder: the brief and the inputs (Blender), or the template's game with GdUnit4 (Godot)."""
    if target.exists() and any(target.iterdir()):
        raise EvalError(f"{target} is not empty: an eval starts in a fresh folder")
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(task.folder / "TASK.md", target / "TASK.md")
    if task.kind == "blender":
        script = task.folder / "prepare.py"
        if script.exists():
            run = _run(blender_cmd(tool("blender"), script, "--dir", str(target)), log)
            if run.returncode != 0:
                raise EvalError(f"prepare.py failed: {run.stderr[-800:]}")
        for extra in task.folder.glob("*.json"):
            shutil.copy2(extra, target / extra.name)
        return
    if task.kind != "godot":
        raise EvalError(f"unknown eval kind {task.kind!r}")
    game = target / "game"
    shutil.copytree(kit / "templates" / task.template / "game", game)
    for path in game.rglob("*"):
        if path.is_file() and path.suffix in {".godot", ".md", ".tscn", ".gd", ".tres", ".cfg"}:
            text = path.read_text(encoding="utf-8")
            for key, value in PLACEHOLDERS.items():
                text = text.replace(key, value)
            path.write_text(text, encoding="utf-8")
    gdunit = load_tools(kit / "tools.toml")["gdunit4"]
    if not integrations.install_godot_addon(
        tools_dir / gdunit.folder, gdunit.extra["addon"], gdunit.extra["source"], game, log
    ):
        raise EvalError(f"GdUnit4 is not installed under {tools_dir / gdunit.folder}; run `gds workspace init`")
    run = _run([tool("godot"), "--headless", "--path", game, "--import"], log)
    log(f"import  exit {run.returncode}")


class Rows:
    """The rows of a Godot check, in the shape the Blender checks write."""

    def __init__(self, task: str) -> None:
        self.task, self.rows, self.errors = task, [], []

    def row(self, name: str, value, op: str, limit) -> None:
        ok = {"==": lambda: value == limit, "<=": lambda: value <= limit, ">=": lambda: value >= limit}[op]()
        self.rows.append({"name": name, "value": value, "op": op, "limit": limit, "unit": "", "pass": bool(ok)})

    def data(self) -> dict:
        passed = sum(1 for r in self.rows if r["pass"])
        return {"task": self.task, "passed": passed, "total": len(self.rows), "rows": self.rows, "errors": self.errors}


def junit_counts(report: Path, marker: str) -> tuple[int, int, int, int]:
    """(cases, failed) for the suites whose name or path holds `marker`, and the same for every other suite."""
    mine = mine_failed = rest = rest_failed = 0
    for xml in report.rglob("results.xml"):
        for case in ET.parse(xml).getroot().iter("testcase"):
            where = (case.get("classname", "") + " " + case.get("name", "")).lower()
            failed = case.find("failure") is not None or case.find("error") is not None
            if marker in where:
                mine, mine_failed = mine + 1, mine_failed + failed
            else:
                rest, rest_failed = rest + 1, rest_failed + failed
    return mine, mine_failed, rest, rest_failed


def check_godot(task: Task, target: Path, tool: Callable[[str], Path], log: Log) -> dict:
    rows = Rows(task.name)
    game = target / "game"
    if not (game / "project.godot").is_file():
        rows.errors.append("no game/project.godot in the eval folder")
        rows.row("game project present", False, "==", True)
        return rows.data()
    problems = layout.check(game)
    for problem in problems:
        rows.errors.append(f"layout: {problem}")
    rows.row("gds check layout problems", len(problems), "==", 0)
    scripts = [p for p in game.rglob("*.gd") if "addons" not in p.relative_to(game).parts]
    lint = _run(["uvx", "--from", GDTOOLKIT, "gdlint", *scripts], log) if scripts else None
    rows.row("gdlint clean", lint is not None and lint.returncode == 0, "==", True)
    fmt = _run(["uvx", "--from", GDTOOLKIT, "gdformat", "--check", *scripts], log) if scripts else None
    rows.row("gdformat clean", fmt is not None and fmt.returncode == 0, "==", True)
    for name, run in (("gdlint", lint), ("gdformat", fmt)):
        if run is not None and run.returncode != 0:
            rows.errors.append(f"{name}: {(run.stdout + run.stderr)[-600:]}")
    imported = _run([tool("godot"), "--headless", "--path", game, "--import"], log)
    errors = [line for line in (imported.stdout + imported.stderr).splitlines() if "ERROR" in line]
    rows.errors += errors[:10]
    rows.row("ERROR lines on a headless import", len(errors), "==", 0)
    own = [p for p in (game / "tests").rglob("test_*.gd") if "fixtures" not in p.parts]
    template_suites = {"test_main_scene.gd", "test_project_settings.gd", "test_prototype_level.gd"}
    rows.row("new test suites written", len([p for p in own if p.name not in template_suites]), ">=", 1)
    acceptance = task.folder / "acceptance"
    dest = game / ACCEPTANCE_DIR
    reports = target / "reports"
    shutil.rmtree(dest, ignore_errors=True)
    shutil.rmtree(reports, ignore_errors=True)
    shutil.copytree(acceptance, dest)
    try:
        _run([tool("godot"), "--headless", "--path", game, "--import"], log)
        cmd = [tool("godot"), "--headless", "--path", game, "-s", "res://addons/gdUnit4/bin/GdUnitCmdTool.gd"]
        _run([*cmd, "-a", "res://tests", "-rd", "../reports", "-c", "--ignoreHeadlessMode"], log, timeout=1200)
    finally:
        shutil.rmtree(dest, ignore_errors=True)
    cases, failed, own_cases, own_failed = junit_counts(reports, "eval_acceptance")
    rows.row("acceptance cases run", cases, ">=", 1)
    rows.row("acceptance cases failed", failed if cases else -1, "==", 0)
    rows.row("the game's own test cases failed", own_failed if own_cases else -1, "==", 0)
    rows.rows.append(
        {"name": "the game's own test cases", "value": own_cases, "op": "info", "limit": "", "unit": "", "pass": True}
    )
    return rows.data()


def check(task: Task, target: Path, tool: Callable[[str], Path], log: Log) -> dict:
    """Measure the delivery in `target`; the rows are also written to `target/result.json`."""
    if not (target / "TASK.md").is_file():
        raise EvalError(f"{target} is not an eval folder (no TASK.md); start one with `gds eval prepare`")
    out = target / RESULT
    if task.kind == "blender":
        out.unlink(missing_ok=True)
        run = _run(
            blender_cmd(tool("blender"), task.folder / "check.py", "--dir", str(target), "--json", str(out)), log
        )
        if not out.is_file():
            raise EvalError(f"check.py wrote no result (exit {run.returncode}): {run.stderr[-800:]}")
        data = json.loads(out.read_text(encoding="utf-8"))
    else:
        data = check_godot(task, target, tool, log)
        out.write_text(json.dumps(data, indent=2), encoding="utf-8")
    scored = [r for r in data["rows"] if r["op"] != "info"]
    line = {"time": time.strftime("%Y-%m-%dT%H:%M:%S"), "met": sum(r["pass"] for r in scored), "of": len(scored)}
    with (target / RUNS).open("a", encoding="utf-8") as runs:
        runs.write(json.dumps(line) + "\n")
    return data


def runs(target: Path) -> list[dict]:
    """The check runs logged in an eval folder, oldest first."""
    path = target / RUNS
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def table(data: dict) -> str:
    """The rows as text, one a line, and the score."""
    lines = []
    for r in data["rows"]:
        mark = "ok  " if r["pass"] else "FAIL"
        if r["op"] == "info":
            mark = "    "
        lines.append(f"{mark} {r['name']}: {r['value']} {r['unit']} ({r['op']} {r['limit']})".replace("  (", " ("))
    lines += [f"  ! {e}" for e in data.get("errors", [])]
    scored = [r for r in data["rows"] if r["op"] != "info"]
    lines.append(f"{data['task']}: {sum(r['pass'] for r in scored)}/{len(scored)} met")
    return "\n".join(lines)
