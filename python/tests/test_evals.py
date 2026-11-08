"""The measured agent tasks (docs/studio/agent-evals.md): their files, prompts and logs."""

from __future__ import annotations

from pathlib import Path

import pytest

from gds_tools import evals, lessons

KIT = Path(__file__).resolve().parents[2]


def test_every_task_loads_with_the_files_its_kind_needs():
    found = evals.tasks(KIT)
    assert {"model-crate", "uv-palette", "rig-humanoid", "clip-walk", "decimate-boulder", "pickup-feature"} <= set(
        found
    )
    for task in found.values():
        assert task.title and task.deliver and task.read, task.name
        assert task.agent in {"blender-artist", "godot-engineer"}, task.name
        if task.kind == "blender":
            assert (task.folder / "check.py").is_file(), task.name
        else:
            assert task.kind == "godot"
            assert list((task.folder / "acceptance").glob("test_*.gd")), task.name
            assert (KIT / "templates" / task.template / "game" / "project.godot").is_file(), task.name


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
