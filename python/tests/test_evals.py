"""The measured agent tasks (docs/studio/agent-evals.md): their files, prompts and logs."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

from gds_tools import eval_quality, eval_review, eval_service, evals, lessons, workspace
from gds_tools.manifest import load_tools

KIT = Path(__file__).resolve().parents[2]


def test_every_task_loads_with_the_files_its_kind_needs():
    found = evals.tasks(KIT)
    assert {
        "model-crate",
        "uv-palette",
        "rig-humanoid",
        "clip-walk",
        "decimate-boulder",
        "pickup-feature",
        "moving-platform",
        "arena-layout",
        "lobby-service",
        "planted-faults",
    } <= set(found)
    agents = {
        "blender": {"blender-artist"},
        "godot": {"godot-engineer", "level-designer"},
        "service": {"backend-engineer"},
        "review": {"reviewer"},
    }
    for task in found.values():
        assert task.title and task.deliver and task.read, task.name
        assert task.kind in agents and task.agent in agents[task.kind], task.name
        assert (KIT / ".claude" / "agents" / f"{task.agent}.md").is_file(), task.name
        if task.kind == "blender":
            assert (task.folder / "check.py").is_file(), task.name
        elif task.kind == "godot":
            has_suite = list((task.folder / "acceptance").glob("test_*.gd"))
            assert has_suite or (task.folder / "probe" / "probe.gd").is_file(), task.name
            assert (KIT / "templates" / task.template / "game" / "project.godot").is_file(), task.name
        elif task.kind == "service":
            assert (task.folder / "acceptance" / "test_acceptance.py").is_file(), task.name
        else:
            assert (task.folder / "faults.toml").is_file() and (task.folder / "inputs" / "pr.diff").is_file()


def test_the_read_lines_of_every_task_name_sections_that_exist():
    for task in evals.tasks(KIT).values():
        for ref in task.read:
            page, anchor = lessons.parse_ref(ref)
            assert anchor in lessons.anchors(KIT / "docs" / page), f"{task.name}: {ref}"


def test_a_brief_without_front_matter_is_refused():
    with pytest.raises(evals.EvalError):
        evals.split_front("# A task\n")


def test_the_prompt_carries_the_issue_the_read_lines_and_the_brief():
    task = evals.get(KIT, "model-crate")
    text = evals.prompt(task, Path("C:/scratch/model-crate"), "Ryubara/gdstudio#774")
    lines = text.splitlines()
    assert lines[0] == "Issue: Ryubara/gdstudio#774"
    assert [line for line in lines if line.startswith("Read: ")] == [f"Read: {r}" for r in task.read]
    assert "C:/scratch/model-crate/TASK.md" in text
    assert "gds eval check model-crate C:/scratch/model-crate" in text
    assert text == evals.prompt(task, Path("C:/scratch/model-crate"), "Ryubara/gdstudio#774")


def test_an_unknown_task_is_refused():
    with pytest.raises(evals.EvalError, match="gds eval list"):
        evals.get(KIT, "no-such-task")


def test_prepare_refuses_a_folder_that_is_not_empty(tmp_path):
    (tmp_path / "left.txt").write_text("x", encoding="utf-8")
    with pytest.raises(evals.EvalError, match="not empty"):
        evals.prepare(evals.get(KIT, "model-crate"), tmp_path, KIT, tmp_path, lambda _n: Path("none"), print)


def test_junit_counts_split_the_acceptance_suite_from_the_games_own(tmp_path):
    report = tmp_path / "report_1"
    report.mkdir()
    (report / "results.xml").write_text(
        """<testsuites>
  <testsuite name="test_eval_acceptance">
    <testcase classname="tests.eval_acceptance.test_eval_acceptance" name="a"/>
    <testcase classname="tests.eval_acceptance.test_eval_acceptance" name="b"><failure message="no"/></testcase>
  </testsuite>
  <testsuite name="test_pickup">
    <testcase classname="tests.pickup.test_pickup" name="c"/>
  </testsuite>
</testsuites>""",
        encoding="utf-8",
    )
    assert evals.junit_counts(tmp_path, "eval_acceptance") == (2, 1, 1, 0)


def test_each_check_is_logged_and_the_table_scores_the_rows(tmp_path, monkeypatch):
    (tmp_path / "TASK.md").write_text("+++\n+++\n", encoding="utf-8")
    rows = [
        {"name": "a", "value": 1, "op": "==", "limit": 1, "unit": "", "pass": True},
        {"name": "b", "value": 2, "op": "<=", "limit": 1, "unit": "m", "pass": False},
        {"name": "c", "value": 9, "op": "info", "limit": "", "unit": "", "pass": True},
    ]
    data = {"task": "pickup-feature", "passed": 2, "total": 3, "rows": rows, "errors": ["layout: x"]}
    monkeypatch.setattr(evals, "check_godot", lambda *_a: data)
    task = evals.get(KIT, "pickup-feature")
    evals.check(task, tmp_path, lambda _n: Path("none"), print)
    evals.check(task, tmp_path, lambda _n: Path("none"), print)
    runs = evals.runs(tmp_path)
    assert [(r["met"], r["of"]) for r in runs] == [(1, 2), (1, 2)]
    text = evals.table(data)
    assert "FAIL b: 2 m (<= 1)" in text
    assert "  ! layout: x" in text
    assert text.endswith("pickup-feature: 1/2 met")


# --- Godot tasks against the bare template --------------------------------------------------------------------------


def _real_tools():
    """(tools folder, tool lookup) of this checkout's workspace; a skip when Godot or GdUnit4 is not installed."""
    try:
        root = workspace.require_workspace(KIT)
        godot = workspace.tool_path("godot", root)
    except workspace.WorkspaceError:
        pytest.skip("the pinned Godot is not installed")
    gdunit = load_tools(KIT / "tools.toml")["gdunit4"]
    if not (root / "tools" / gdunit.folder / gdunit.extra["source"]).exists():
        pytest.skip("GdUnit4 is not installed")
    return root / "tools", lambda _name: godot


@pytest.fixture(scope="module")
def bare_game(tmp_path_factory):
    """A game made from the 3D Blank template the way `gds eval prepare` makes it (GdUnit4 and the kit's addons in)."""
    tools_dir, tool = _real_tools()
    folder = tmp_path_factory.mktemp("bare") / "eval"
    evals.prepare(evals.get(KIT, "pickup-feature"), folder, KIT, tools_dir, tool, lambda _line: None)
    return folder / "game", tool


def test_a_prepared_game_has_the_kit_addons_the_template_registers(bare_game):
    game, _ = bare_game
    assert (game / "addons" / "gds_ui" / "plugin.cfg").is_file()
    assert "addons/gds_ui/router/ui_router.gd" in (game / "project.godot").read_text(encoding="utf-8")


# `moving-platform` waits 17 s of game time: at 60 fixed frames a second the engine never waits for the clock
# (engines/godot/test-speed.md#what-makes-a-suite-run-at-the-clocks-speed), so the test takes seconds, not 20 s.
FIXED_FPS = ("--fixed-fps", "60")


@pytest.mark.parametrize("name", ["pickup-feature", "moving-platform"])
def test_an_acceptance_suite_parses_and_runs_every_case_against_the_bare_template(bare_game, name):
    """The eval that ran 0 acceptance cases (kit #898): the suite no longer parsed against the template it was written
    for. Every case must be discovered and run; the bare template fails them, as it holds no delivery."""
    game, tool = bare_game
    task = evals.get(KIT, name)
    suites = list((task.folder / "acceptance").glob("test_*.gd"))
    declared = sum(path.read_text(encoding="utf-8").count("\nfunc test_") for path in suites)
    assert len(suites) == 1 and declared >= 5
    cases, failed, _own, own_failed = evals.run_acceptance(task, game, tool, lambda _l: None, godot_args=FIXED_FPS)
    assert (cases, own_failed) == (declared, 0)
    assert failed >= 1
    assert not (game / evals.ACCEPTANCE_DIR).exists()


def test_the_arena_probe_runs_on_the_bare_template_and_reports_a_missing_arena(bare_game):
    game, tool = bare_game
    rows, tail = evals.run_probe(evals.get(KIT, "arena-layout"), game, tool, lambda _l: None)
    assert [r["name"] for r in rows] == ["the arena scene loads"], tail
    assert rows[0]["pass"] is False
    assert not (game / evals.PROBE_DIR).exists()


def test_no_acceptance_suite_names_a_local_that_shadows_a_gdunit_function():
    """GdUnit4 loads a suite with warnings as errors: a local called `before` or `after` shadows its hooks."""
    for path in (KIT / "evals" / "godot").rglob("acceptance/*.gd"):
        text = path.read_text(encoding="utf-8")
        for hook in ("before", "after", "before_test", "after_test"):
            assert f"var {hook}:" not in text and f"var {hook} " not in text, f"{path.name}: {hook}"


# --- code quality ---------------------------------------------------------------------------------------------------

GOOD = """class_name Spinner
extends Node3D
## Spins about the vertical axis.

## Emitted once a turn.
signal turned
## Degrees a second.
@export var speed_deg: float = 90.0

var _angle: float = 0.0


func _physics_process(delta: float) -> void:
	_angle += speed_deg * delta
	rotation_degrees.y = _angle


## Turn at once.
func snap(angle: float) -> void:
	_angle = angle
"""

SLOPPY = """class_name Sloppy
extends Node3D

signal turned
@export var speed = 90.0
var _scratch = []


func _process(delta):
	var points = [position, position + Vector3.UP]
	var text := "turn %d" % speed
	for body in get_tree().get_nodes_in_group("things"):
		body.name = text
	var thing = Node3D.new()
	add_child(thing)


func snap(angle):
	_angle = angle
"""


def _rows(scripts, **limits):
    return {r["name"]: r for r in eval_quality.rows(scripts, limits)}


def test_a_small_typed_documented_script_meets_every_quality_row():
    rows = _rows({"spinner.gd": GOOD}, min_scripts=1)
    assert all(r["pass"] for r in rows.values()), rows


def test_a_sloppy_script_misses_the_documentation_type_and_hot_path_rows():
    rows = _rows({"sloppy.gd": SLOPPY}, min_scripts=1, max_script_lines=10, max_function_lines=3)
    for name in (
        "longest new script (code lines)",
        "longest function (code lines)",
        "public members without a `##` doc comment",
        "declarations without a type",
        "allocations in a per-frame function",
    ):
        assert not rows[name]["pass"], name
    stats = eval_quality.analyse("sloppy.gd", SLOPPY)
    assert len(stats.allocations) == 4  # the array literal, the string built, the node list, the new node
    assert any("parameter `delta`" in item for item in stats.untyped)
    assert any("no return type" in item for item in stats.untyped)
    assert any("var _scratch has no type" in item for item in stats.untyped)
    assert any("no `##` description" in item for item in stats.undocumented)


def test_an_allocation_outside_a_per_frame_function_is_fine():
    text = GOOD + "\n\nfunc make() -> Node3D:\n\treturn Node3D.new()\n"
    assert eval_quality.analyse("spinner.gd", text).allocations == []
    hot = GOOD.replace("\t_angle += speed_deg * delta", "\tvar copy := [speed_deg]\n\t_angle += copy[0] * delta")
    assert len(eval_quality.analyse("spinner.gd", hot).allocations) == 1


def test_added_scripts_are_the_ones_the_template_does_not_have(tmp_path):
    template, game = tmp_path / "template", tmp_path / "game"
    for root in (template, game):
        (root / "core").mkdir(parents=True)
        (root / "core" / "kept.gd").write_text("extends Node\n", encoding="utf-8")
    (game / "core" / "edited.gd").write_text("extends Node\n", encoding="utf-8")
    (game / "tests").mkdir()
    (game / "tests" / "test_x.gd").write_text("extends Node\n", encoding="utf-8")
    (game / "addons" / "a").mkdir(parents=True)
    (game / "addons" / "a" / "a.gd").write_text("extends Node\n", encoding="utf-8")
    assert list(evals.added_scripts(game, template)) == ["core/edited.gd"]


# --- the service and review kinds -----------------------------------------------------------------------------------


def test_unittest_output_is_read_for_the_cases_run_and_the_ones_that_failed():
    out = """test_a (m.C.test_a) ... ok
test_b (m.C.test_b) ... FAIL
test_c (m.C.test_c) ... ERROR
test_d (m.C.test_d) ... skipped 'no'
test_e (m.C.test_e) ... ok
"""
    assert eval_service.parse_unittest(out) == (4, ["test_b", "test_c"])


def test_log_lines_are_counted_by_their_fields_and_for_the_token():
    text = "\n".join(
        [
            json.dumps({"method": "GET", "path": "/x", "status": 200}),
            json.dumps({"method": "GET", "path": "/x"}),
            "plain text SECRET",
            json.dumps({"method": "GET", "path": "/y", "status": 401, "auth": "Bearer SECRET"}),
        ]
    )
    assert eval_service.log_numbers(text, "SECRET") == (2, 2)


def test_the_lobby_acceptance_suite_runs_all_its_cases_and_fails_each_against_a_dead_url():
    task = evals.get(KIT, "lobby-service")
    env = {"LOBBY_URL": "http://127.0.0.1:9", "LOBBY_TOKEN": "t", "LOBBY_HOST": "h", "LOBBY_PORT_BASE": "7000"}
    run = subprocess.run(
        [sys.executable, "-W", "ignore", "-m", "unittest", "-v", "test_acceptance"],
        cwd=task.folder / "acceptance",
        capture_output=True,
        text=True,
        env=env,
        timeout=120,
    )
    ran, failed = eval_service.parse_unittest(run.stderr + run.stdout)
    assert ran >= task.limits["min_acceptance"]
    assert len(failed) == ran


def test_a_service_folder_without_a_project_fails_the_first_row_and_stops(tmp_path):
    task = evals.get(KIT, "lobby-service")
    (tmp_path / "service").mkdir()
    data = eval_service.check_service(task.name, task.folder, tmp_path, task.limits, print)
    assert [(r["name"], r["pass"]) for r in data["rows"]] == [("service/pyproject.toml present", False)]


def test_prepare_gives_a_review_its_inputs_and_never_the_answer_key(tmp_path):
    task = evals.get(KIT, "planted-faults")
    target = tmp_path / "run"
    evals.prepare(task, target, KIT, tmp_path, lambda _n: Path("none"), print)
    files = {p.relative_to(target).as_posix() for p in target.rglob("*") if p.is_file()}
    assert {"pr.md", "pr.diff", "rules.md", "repo/game/gameplay/weapon/weapon.gd"} <= files
    assert not any("faults" in f or "answer" in f for f in files)


def test_prepare_gives_a_service_an_empty_folder_for_the_delivery(tmp_path):
    target = tmp_path / "run"
    evals.prepare(evals.get(KIT, "lobby-service"), target, KIT, tmp_path, lambda _n: Path("none"), print)
    assert sorted(p.name for p in target.iterdir()) == ["TASK.md", "service"]
    assert list((target / "service").iterdir()) == []


def test_every_anchor_of_the_answer_key_is_found_exactly_once_and_faults_do_not_overlap():
    folder = evals.get(KIT, "planted-faults").folder
    faults, traps = eval_review.load_key(folder)
    assert len(faults) == 13 and len(traps) == 4
    for first in faults:
        for second in faults:
            if first.id < second.id:
                for a in first.places:
                    for b in second.places:
                        assert a.file != b.file or abs(a.line - b.line) > a.tol + b.tol, (first.id, second.id)


def _finding(folder, fault_id, delta=0):
    faults, _ = eval_review.load_key(folder)
    place = next(f for f in faults if f.id == fault_id).places[0]
    return {"file": place.file, "line": place.line + delta, "summary": "x" * 20}


def test_a_review_that_cites_every_fault_finds_all_thirteen_with_no_false_finding():
    folder = evals.get(KIT, "planted-faults").folder
    faults, _ = eval_review.load_key(folder)
    result = eval_review.score(folder, [_finding(folder, f.id) for f in faults])
    assert (result["found"], result["false"], result["duplicates"]) == (13, 0, 0)


def test_a_citation_of_the_diff_line_counts_and_a_repeat_is_a_duplicate_not_a_false_finding():
    folder = evals.get(KIT, "planted-faults").folder
    faults, _ = eval_review.load_key(folder)
    f1 = next(f for f in faults if f.id == "F1")
    in_diff = next(p for p in f1.places if p.file == "pr.diff")
    findings = [{"file": "pr.diff", "line": in_diff.line, "summary": "x"}, _finding(folder, "F1", 1)]
    result = eval_review.score(folder, findings)
    assert (result["found"], result["false"], result["duplicates"]) == (1, 0, 1)


def test_findings_on_correct_code_and_far_from_any_fault_are_false_and_traps_are_told_apart():
    folder = evals.get(KIT, "planted-faults").folder
    _, traps = eval_review.load_key(folder)
    trap = traps[0].places[0]
    findings = [
        {"file": trap.file, "line": trap.line, "summary": "x"},
        {"file": "weapon.gd", "line": 1, "summary": "x"},
        {"file": "nowhere.gd", "line": 5, "summary": "x"},
    ]
    result = eval_review.score(folder, findings)
    assert (result["found"], result["false"], result["traps"]) == (0, 3, 1)


def test_file_names_are_read_by_their_last_part_and_lines_from_numbers_ranges_and_text():
    findings, problems = eval_review.parse_findings(
        json.dumps(
            [
                {"file": "repo/game/gameplay/weapon/weapon.gd", "line": 5, "summary": "a"},
                {"file": "C:\\x\\Pr.MD", "line": "12-14", "summary": "b"},
                {"file": "description", "line": [3, 4], "summary": "c"},
                {"file": "weapon.gd", "summary": "no line"},
                {"file": "weapon.gd", "line": True, "summary": "bool"},
            ]
        )
    )
    assert [(f["file"], f["line"]) for f in findings] == [("weapon.gd", 5), ("pr.md", 12), ("pr.md", 3)]
    assert len(problems) == 2
    assert eval_review.parse_findings("not json")[1]
    assert eval_review.parse_findings("{}")[0] == []


def test_the_review_check_scores_the_verdict_the_findings_and_the_false_ones(tmp_path):
    task = evals.get(KIT, "planted-faults")
    faults, _ = eval_review.load_key(task.folder)
    good = [_finding(task.folder, f.id) for f in faults[:10]]
    (tmp_path / "REVIEW.md").write_text("# Review\n\n**Verdict: changes needed**\n", encoding="utf-8")
    (tmp_path / "findings.json").write_text(json.dumps(good), encoding="utf-8")
    data = eval_review.check_review(task.name, task.folder, tmp_path, task.limits)
    rows = {r["name"]: r for r in data["rows"]}
    assert all(r["pass"] for r in data["rows"]), rows
    assert rows["planted faults found"]["value"] == 10
    noisy = good + [{"file": "weapon.gd", "line": 1, "summary": "x"}] * 3
    (tmp_path / "findings.json").write_text(json.dumps(noisy), encoding="utf-8")
    rows = {r["name"]: r for r in eval_review.check_review(task.name, task.folder, tmp_path, task.limits)["rows"]}
    assert not rows["findings that match no planted fault"]["pass"]
    (tmp_path / "REVIEW.md").write_text("Verdict: approve", encoding="utf-8")
    (tmp_path / "findings.json").write_text("[]", encoding="utf-8")
    rows = {r["name"]: r for r in eval_review.check_review(task.name, task.folder, tmp_path, task.limits)["rows"]}
    assert [n for n, r in rows.items() if not r["pass"]] == [
        "REVIEW.md gives the verdict `changes needed`",
        "findings.json lists findings with a file, a line and a summary",
        "planted faults found",
    ]
