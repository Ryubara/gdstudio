"""3D Third Person's GdUnit4 suite is split over CI shards by measured seconds (kit #1492).

`.github/scripts/ci_test_shards.py` deals every test script of the made game to a shard of the `template-tests` job and
ends each job with a check that warns past 60 % and fails past 80 % of its limit
(docs/engines/godot/test-speed.md#split-the-suite-by-seconds-not-by-folder). These tests hold the dealing, the log
parsing and the check, and keep the script's shard count and limit equal to the workflow's.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github" / "scripts" / "ci_test_shards.py"
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
# A game made from 3d-third-person holds 3d-blank's tests with its own on top.
TEMPLATE_TESTS = [
    ROOT / "templates" / "3d-blank" / "game" / "tests",
    ROOT / "templates" / "3d-third-person" / "game" / "tests",
]

spec = importlib.util.spec_from_file_location("ci_test_shards", SCRIPT)
assert spec and spec.loader
shards = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shards)


def template_scripts() -> list[str]:
    found = {path.relative_to(tests).as_posix() for tests in TEMPLATE_TESTS for path in tests.rglob("test_*.gd")}
    return sorted(found)


def test_the_workflow_runs_the_shards_the_script_deals():
    shards.check_workflow(WORKFLOW.read_text(encoding="utf-8"))


def test_the_workflow_check_refuses_a_matrix_that_disagrees():
    text = WORKFLOW.read_text(encoding="utf-8")
    listed = ", ".join(str(n) for n in range(1, shards.SHARDS + 1))
    with pytest.raises(AssertionError, match="runs shards"):
        shards.check_workflow(text.replace(f"shard: [{listed}]", f"shard: [{listed}, {shards.SHARDS + 1}]"))
    with pytest.raises(AssertionError, match="timeout-minutes"):
        shards.check_workflow(
            text.replace(f"    timeout-minutes: {shards.JOB_LIMIT_MINUTES}\n", "    timeout-minutes: 99\n", 1)
        )


def test_every_template_script_runs_in_exactly_one_shard():
    names, times = template_scripts(), shards.load_times()
    assert len(names) > 100
    print(shards.self_test(names, times, WORKFLOW))
    print(shards.report(names, times))


def test_the_heaviest_go_first_to_the_lightest_shard_and_a_new_script_fills_a_gap():
    weight = {"a.gd": 90.0, "b.gd": 60.0, "c.gd": 50.0, "d.gd": 20.0, "new.gd": 10.0}
    shard_of, load = shards.deal(weight, shards=2)
    assert shard_of == {"a.gd": 1, "b.gd": 2, "c.gd": 2, "d.gd": 1, "new.gd": 1}
    assert load == [120.0, 110.0]
    times = {"default_seconds": 10, "seconds": {"a.gd": 90, "b.gd": 60, "c.gd": 50, "d.gd": 20}}
    assert shards.shard_paths(list(weight), times, 2, shards=2) == ["res://tests/b.gd", "res://tests/c.gd"]
    with pytest.raises(SystemExit):
        shards.shard_paths(list(weight), times, 3, shards=2)


JOB_LOG = (
    "2026-11-14T01:12:21.2958758Z \x1b[38;2;0;206;209mRun Test Suite: \x1b[0m\x1b[38;2;250;235;215m"
    "res://tests/test_input_map.gd\x1b[0m\n"
    "2026-11-14T01:12:21.3208603Z \x1b[38;2;30;144;255mStatistics:\x1b[0m\x1b[38;2;128;128;128m 4 test cases | 0 errors"
    " | 0 failures | 0 flaky | 0 skipped | 0 orphans |\x1b[0m\x1b[38;2;34;139;34m PASSED\x1b[0m\x1b[38;2;100;149;237m"
    " 34ms\x1b[0m\n"
    "Run Test Suite: res://tests/gameplay/test_ai_soak.gd\n"
    "  a test case line\n"
    "Statistics: 9 test cases | 0 errors | 1 failures | 0 flaky | 0 skipped | 0 orphans | FAILED 1min 13s 694ms\n"
)


def test_suite_seconds_reads_a_coloured_job_log_and_a_plain_one():
    assert shards.suite_seconds(JOB_LOG) == {"test_input_map.gd": 0.034, "gameplay/test_ai_soak.gd": 73.694}


@pytest.mark.parametrize(
    ("elapsed", "code", "kind"),
    [(14 * 60, 0, ""), (16 * 60, 0, "::warning::"), (21 * 60, 1, "::error::")],
)
def test_the_check_warns_past_60_and_fails_past_80_percent(elapsed: float, code: int, kind: str):
    got, commands, summary = shards.check(elapsed, 25, "template-tests 1/4", JOB_LOG)
    assert got == code
    assert commands[0].startswith(kind) if kind else not commands[0].startswith("::")
    assert "`gameplay/test_ai_soak.gd` | 73.7" in "\n".join(summary)


def test_the_check_runs_the_command_line_and_writes_the_summary(tmp_path: Path):
    log, summary = tmp_path / "tests.log", tmp_path / "summary.md"
    log.write_text(JOB_LOG, encoding="utf-8")
    assert (
        shards.main(
            ["check", "--elapsed", "1260", "--limit-minutes", "25", "--log", str(log), "--summary", str(summary)]
        )
        == 1
    )
    assert "21.0 of 25 minutes (84%)" in summary.read_text(encoding="utf-8")
    assert shards.main(["check", "--elapsed", "60", "--limit-minutes", "40", "--log", str(tmp_path / "none.log")]) == 0


def test_update_takes_the_median_and_keeps_scripts_no_log_ran(tmp_path: Path):
    logs = []
    for index, seconds in enumerate((10, 30, 20)):
        path = tmp_path / f"run{index}.log"
        path.write_text(
            f"Run Test Suite: res://tests/test_a.gd\nStatistics: 1 test cases | PASSED {seconds}s\n", encoding="utf-8"
        )
        logs.append(path)
    times = tmp_path / "times.json"
    times.write_text(json.dumps({"default_seconds": 10, "seconds": {"test_old.gd": 5.0}}), encoding="utf-8")
    assert shards.main(["update", *map(str, logs), "--times", str(times)]) == 0
    assert json.loads(times.read_text(encoding="utf-8"))["seconds"] == {"test_a.gd": 20.0, "test_old.gd": 5.0}
