"""`gds check scripts`: the report is read from what the check script prints, with Godot replaced by a fake."""

from __future__ import annotations

from pathlib import Path

import pytest

from gds_tools import scripts

FAILED = """\
SCRIPT ERROR: Parse Error: Identifier "UIRouter" not declared in the current scope.
   at: GDScript::reload (res://addons/gds_ui/demo/demo.gd:9)
SCRIPT ERROR: Parse Error: Identifier "UIRouter" not declared in the current scope.
   at: GDScript::reload (res://addons/gds_ui/demo/demo.gd:12)
ERROR: Failed to load script "res://addons/gds_ui/demo/demo.gd" with error "Parse error".
   at: load (modules/gdscript/gdscript_resource_format.cpp:46)
PARSE FAIL: res://addons/gds_ui/demo/demo.gd
PARSED: 12 script(s), 1 failed
"""


class FakeGodot:
    def __init__(self, output: str) -> None:
        self.output, self.calls = output, []

    def __call__(self, cmd, cwd, timeout):
        self.calls.append(list(cmd))
        return (1, self.output) if "-s" in cmd else (0, "")


@pytest.fixture
def kit(tmp_path: Path) -> Path:
    folder = tmp_path / "kit"
    (folder / scripts.SCRIPT).parent.mkdir(parents=True)
    (folder / scripts.SCRIPT).write_text("extends SceneTree\n", encoding="utf-8")
    return folder


@pytest.fixture
def project(tmp_path: Path) -> Path:
    folder = tmp_path / "game"
    folder.mkdir()
    (folder / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    return folder


def test_a_script_that_does_not_load_is_reported_once_with_godots_reason(kit, project):
    report = scripts.check(Path("godot"), project, kit, FakeGodot(FAILED))
    assert not report.ok
    assert (report.parsed, report.failed) == (12, ["res://addons/gds_ui/demo/demo.gd"])
    assert [d.split(":")[0] for d in report.details] == ["SCRIPT ERROR", "ERROR"]


def test_every_script_loading_is_ok(kit, project):
    report = scripts.check(Path("godot"), project, kit, FakeGodot("PARSED: 12 script(s), 0 failed\n"))
    assert report.ok
    assert report.parsed == 12


def test_the_project_is_imported_before_the_scripts_are_loaded(kit, project):
    fake = FakeGodot("PARSED: 1 script(s), 0 failed\n")
    scripts.check(Path("godot"), project, kit, fake)
    assert "--import" in fake.calls[0]
    assert "-s" in fake.calls[1]
    assert fake.calls[1][-1] == str((kit / scripts.SCRIPT).resolve())


def test_a_run_that_never_printed_its_total_is_an_error_not_a_pass(kit, project):
    with pytest.raises(scripts.ScriptCheckError, match="did not finish"):
        scripts.check(Path("godot"), project, kit, FakeGodot("ERROR: Cannot open file\n"))


def test_a_folder_without_a_project_is_refused(kit, tmp_path):
    with pytest.raises(FileNotFoundError):
        scripts.check(Path("godot"), tmp_path, kit, FakeGodot(""))


def test_the_real_check_script_is_in_the_kit():
    assert (Path(__file__).resolve().parents[2] / scripts.SCRIPT).is_file()
