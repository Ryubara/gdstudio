"""`gds check layout`: each rule fails on a small project that breaks it, and the 3D Blank template passes them all."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from gds_tools import layout

KIT = Path(__file__).resolve().parents[2]
TEMPLATE_GAME = KIT / "templates" / "3d-blank" / "game"


def make(root: Path, files: dict[str, str]) -> Path:
    """A project with a `project.godot` and `files` (path -> text); every script gets its uid."""
    project = root / "game"
    project.mkdir()
    (project / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    for rel, text in files.items():
        path = project / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        if path.suffix in {".gd", ".gdshader"}:
            path.with_name(path.name + ".uid").write_text("uid://abc\n", encoding="utf-8")
    return project


def rules(project: Path) -> set[str]:
    return {problem.rule for problem in layout.check(project)}


def test_the_template_follows_every_rule():
    assert layout.check(TEMPLATE_GAME) == []


def test_the_third_person_template_on_top_of_its_base_follows_every_rule(tmp_path):
    """3D Third Person extends 3D Blank: the base's files first, its own on top (kit #821)."""
    game = tmp_path / "game"
    shutil.copytree(TEMPLATE_GAME, game)
    shutil.copytree(KIT / "templates" / "3d-third-person" / "game", game, dirs_exist_ok=True)
    assert layout.check(game) == []


def test_a_folder_that_is_not_a_project_is_refused(tmp_path):
    with pytest.raises(FileNotFoundError):
        layout.check(tmp_path)


def test_an_unknown_top_level_folder_is_refused(tmp_path):
    project = make(tmp_path, {"scripts/a.gd": "extends Node\n"})
    assert rules(project) == {"top-level"}


def test_local_and_generated_folders_are_not_judged(tmp_path):
    project = make(tmp_path, {".godot/Bad Name.txt": "", "reports/Report 1/index.html": ""})
    assert layout.check(project) == []


def test_names_are_snake_case_for_files_and_folders(tmp_path):
    project = make(tmp_path, {"gameplay/PlayerStuff/player.gd": "", "gameplay/ok/Bad-Name.tscn": ""})
    found = {(p.path, p.rule) for p in layout.check(project)}
    assert ("gameplay/PlayerStuff", "snake-case") in found
    assert ("gameplay/ok/Bad-Name.tscn", "snake-case") in found


def test_dot_files_and_licence_names_keep_their_case(tmp_path):
    project = make(
        tmp_path, {"assets/models/crate/LICENSE.md": "", "assets/models/crate/.gdignore": "", "core/README.md": ""}
    )
    assert layout.check(project) == []


def test_a_folder_named_for_nothing_is_refused(tmp_path):
    project = make(tmp_path, {"gameplay/common/health.gd": "extends Node\n"})
    assert rules(project) == {"vague-folder"}


def test_a_class_name_is_its_file_in_pascal_case(tmp_path):
    project = make(
        tmp_path,
        {
            "core/ui_router.gd": "class_name UIRouter\n",
            "core/settings.gd": "class_name Settings\n",
            "core/audio_service.gd": "class_name Sounds\n",
        },
    )
    assert [p.path for p in layout.check(project)] == ["core/audio_service.gd"]


def test_a_class_of_the_kits_synced_addon_is_declared_nowhere_else(tmp_path):
    """A template or game copy of a part that moved into `gds_game` never gets the kit's fixes (kit #923)."""
    project = make(
        tmp_path,
        {
            "addons/gds_game/trigger_zone/trigger_zone.gd": "class_name TriggerZone\nextends Area3D\n",
            "gameplay/trigger_zone/trigger_zone.gd": "class_name TriggerZone\nextends Area3D\n",
            "gameplay/door/door.gd": "class_name Door\nextends Node3D\n",
        },
    )
    found = [p for p in layout.check(project) if p.rule == "addon-class"]
    assert [p.path for p in found] == ["gameplay/trigger_zone/trigger_zone.gd"]
    assert "addons/gds_game/trigger_zone/trigger_zone.gd" in found[0].message


def test_a_scene_and_the_script_on_its_root_share_a_folder_and_a_name(tmp_path):
    scene = (
        '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="{path}" id="1_s"]\n\n'
        '[node name="Player" type="Node3D"]\nscript = ExtResource("1_s")\n'
    )
    project = make(
        tmp_path,
        {
            "gameplay/player/player.gd": "extends Node3D\n",
            "gameplay/player/player.tscn": scene.format(path="res://gameplay/player/player.gd"),
            "gameplay/crate/crate.gd": "extends Node3D\n",
            "gameplay/crate/crate.tscn": scene.format(path="res://gameplay/player/player.gd"),
        },
    )
    assert [(p.path, p.rule) for p in layout.check(project)] == [("gameplay/crate/crate.tscn", "scene-script")]


def test_a_script_on_a_child_node_is_not_the_scenes_script(tmp_path):
    scene = (
        '[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://gameplay/a/other.gd" id="1_s"]\n\n'
        '[node name="Root" type="Node3D"]\n\n[node name="Child" type="Node" parent="."]\nscript = ExtResource("1_s")\n'
    )
    project = make(tmp_path, {"gameplay/a/other.gd": "extends Node\n", "gameplay/a/root.tscn": scene})
    assert layout.check(project) == []


def test_every_script_and_shader_has_its_uid(tmp_path):
    project = make(tmp_path, {"core/a.gd": "extends Node\n", "assets/shaders/s.gdshader": "shader_type spatial;\n"})
    (project / "core" / "a.gd.uid").unlink()
    (project / "assets" / "shaders" / "s.gdshader.uid").unlink()
    assert {(p.path, p.rule) for p in layout.check(project)} == {
        ("core/a.gd", "uid"),
        ("assets/shaders/s.gdshader", "uid"),
    }


@pytest.mark.parametrize(
    ("folder", "target", "broken"),
    [
        ("core", "gameplay", True),
        ("core", "ui", True),
        ("gameplay", "ui", True),
        ("world", "ui", True),
        ("assets", "core", True),
        ("gameplay", "core", False),
        ("gameplay", "world", False),
        ("ui", "gameplay", False),
        ("ui", "assets", False),
        ("core", "addons", False),
        ("tests", "ui", False),
        ("tools", "gameplay", False),
    ],
)
def test_a_reference_points_only_down_the_order(tmp_path, folder, target, broken):
    project = make(tmp_path, {f"{folder}/a.gd": f'extends Node\nconst X := preload("res://{target}/b.gd")\n'})
    assert (rules(project) == {"dependency"}) is broken


def test_the_root_scene_may_use_everything(tmp_path):
    project = make(tmp_path, {"main.tscn": '[ext_resource type="PackedScene" path="res://ui/hud.tscn" id="1_a"]\n'})
    assert layout.check(project) == []


def test_shipped_code_never_names_tools_or_tests(tmp_path):
    project = make(
        tmp_path,
        {
            "gameplay/a.gd": 'extends Node\nconst T := preload("res://tools/capture/x.gd")\n',
            "tools/capture/x.gd": "extends Node\n",
            "tests/t.gd": 'extends Node\nconst T := preload("res://tools/capture/x.gd")\n',
        },
    )
    assert [(p.path, p.rule) for p in layout.check(project)] == [("gameplay/a.gd", "ships-tools")]


def test_every_export_preset_leaves_tests_and_tools_out(tmp_path):
    project = make(tmp_path, {"export_presets.cfg": '[preset.0]\nexclude_filter="tests/*, reports/*"\n'})
    problems = layout.check(project)
    assert [(p.rule, "tools/*" in p.message, "tests/*" in p.message) for p in problems] == [("export", True, False)]
    (project / "export_presets.cfg").write_text('[preset.0]\nexclude_filter="tools/*,tests/*"\n', encoding="utf-8")
    assert layout.check(project) == []


def test_a_problem_prints_where_what_and_why(tmp_path):
    project = make(tmp_path, {"scripts/a.gd": ""})
    assert str(layout.check(project)[0]).startswith("scripts: [top-level] `scripts/` is not one of addons")


def test_the_cli_exits_one_for_a_broken_project_and_zero_for_a_good_one(tmp_path, capsys):
    from gds_tools import cli

    (tmp_path / "a").mkdir()
    (tmp_path / "b").mkdir()
    good = make(tmp_path / "a", {"core/a.gd": "extends Node\n"})
    bad = make(tmp_path / "b", {"scripts/a.gd": "extends Node\n"})
    assert cli.main(["check", "layout", str(good)]) == 0
    assert cli.main(["check", "layout", str(bad)]) == 1
    assert "[top-level]" in capsys.readouterr().err


GDS_UI_PROJECT = (
    'config_version=5\n\n[autoload]\n\nUIRouter="*res://addons/gds_ui/router/ui_router.gd"\n\n'
    '[editor_plugins]\n\nenabled=PackedStringArray("res://addons/gds_ui/plugin.cfg")\n'
)


def with_synced_addon(root: Path, project_godot: str) -> Path:
    """A project holding the kit's `gds_ui` plugin file and the given `project.godot`."""
    project = make(root, {"addons/gds_ui/plugin.cfg": "[plugin]\n"})
    (project / "project.godot").write_text(project_godot, encoding="utf-8")
    return project


def test_a_synced_addon_that_is_registered_passes(tmp_path):
    assert layout.check(with_synced_addon(tmp_path, GDS_UI_PROJECT)) == []


def test_a_synced_addon_without_its_autoload_or_plugin_is_refused(tmp_path):
    project = with_synced_addon(tmp_path, "config_version=5\n")
    assert rules(project) == {"addon-plugin", "addon-autoload"}
    assert "UIRouter" in str(next(p for p in layout.check(project) if p.rule == "addon-autoload"))


def test_each_registration_is_judged_alone(tmp_path):
    no_autoload = GDS_UI_PROJECT.replace('UIRouter="*res://addons/gds_ui/router/ui_router.gd"\n', "")
    assert rules(with_synced_addon(tmp_path, no_autoload)) == {"addon-autoload"}
    other = tmp_path / "other"
    other.mkdir()
    no_plugin = GDS_UI_PROJECT.replace('"res://addons/gds_ui/plugin.cfg"', '"res://addons/other/plugin.cfg"')
    assert rules(with_synced_addon(other, no_plugin)) == {"addon-plugin"}


def test_a_committed_addon_without_its_registration_is_refused(tmp_path):
    project = make(tmp_path, {"addons/phantom_camera/plugin.cfg": "[plugin]\n"})
    (project / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    assert rules(project) == {"addon-plugin", "addon-autoload"}
    assert "PhantomCameraManager" in str(next(p for p in layout.check(project) if p.rule == "addon-autoload"))


def test_a_project_without_the_addon_needs_no_registration(tmp_path):
    assert layout.check(make(tmp_path, {"core/a.gd": "extends Node\n"})) == []


def test_the_registrations_are_what_the_kits_own_project_has():
    """The table is a copy of what enabling the plugin does; the kit's `godot/project.godot` is the original."""
    settings = layout._settings(KIT / "godot")
    for name, (plugin, autoloads) in layout.ADDON_REGISTRATIONS.items():
        if not (KIT / "godot" / "addons" / name).is_dir():
            continue
        assert f'"{plugin}"' in settings["editor_plugins"]["enabled"], name
        for autoload, path in autoloads.items():
            assert settings["autoload"][autoload].strip('"') == path


def test_the_templates_register_the_addons_they_commit():
    """Phantom Camera is committed in 3D Blank (kit #821): its plugin and its autoload are what the table says."""
    settings = layout._settings(TEMPLATE_GAME)
    plugin, autoloads = layout.ADDON_REGISTRATIONS["phantom_camera"]
    assert f'"{plugin}"' in settings["editor_plugins"]["enabled"]
    for autoload, path in autoloads.items():
        assert settings["autoload"][autoload].strip('"') == path


def test_the_template_with_the_synced_addon_passes_every_rule(tmp_path):
    """What `gds new game` makes: the template's project plus the addon `gds sync` copies into it."""
    game = tmp_path / "game"
    shutil.copytree(TEMPLATE_GAME, game)
    shutil.copytree(KIT / "godot" / "addons" / "gds_ui", game / "addons" / "gds_ui")
    assert layout.check(game) == []


def test_a_suite_that_reads_the_wall_clock_or_waits_on_a_timer_must_say_why(tmp_path):
    calls = {"msec": "Time.get_ticks_msec()", "usec": "Time.get_ticks_usec()", "timer": "get_tree().create_timer(1.0)"}
    for name, call in calls.items():
        (tmp_path / name).mkdir()
        project = make(tmp_path / name, {"tests/test_a.gd": f"extends GdUnitTestSuite\nvar t := {call}\n"})
        assert [(p.path, p.rule) for p in layout.check(project)] == [("tests/test_a.gd", "on-the-clock")], call


def test_a_first_line_comment_on_the_clock_is_the_reason(tmp_path):
    text = "# On the clock: the engine's own callback is the subject.\nextends GdUnitTestSuite\n"
    text += "var t := Time.get_ticks_msec()\n"
    assert layout.check(make(tmp_path, {"tests/test_a.gd": text})) == []


def test_a_clock_call_in_a_comment_or_outside_the_tests_is_not_judged(tmp_path):
    project = make(
        tmp_path,
        {
            "tests/test_a.gd": "extends GdUnitTestSuite\n# Never Time.get_ticks_msec() here.\n",
            "core/clock.gd": "extends Node\nvar t := Time.get_ticks_msec()\n",
        },
    )
    assert layout.check(project) == []
