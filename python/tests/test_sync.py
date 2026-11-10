"""`gds sync`: writing the kit's files into a game, the lock, and catching drift."""

import json
from pathlib import Path

import pytest

from gds_tools import sync


def make_kit(tmp_path):
    kit = tmp_path / "kit"
    (kit / ".claude" / "agents").mkdir(parents=True)
    (kit / ".claude" / "agents" / "engineer.md").write_text("engineer v1\n")
    (kit / "templates" / "game" / ".claude" / "hooks").mkdir(parents=True)
    (kit / "templates" / "game" / ".claude" / "hooks" / "launch.py").write_text("print('launch')\n")
    return kit


def test_sync_writes_files_and_lock_then_is_clean(tmp_path):
    kit, game = make_kit(tmp_path), tmp_path / "game"
    game.mkdir()
    assert sync.drift(kit, game)  # nothing there yet
    assert sync.sync(kit, game, lambda _: None) == 2
    assert (game / ".claude" / "agents" / "engineer.md").read_text() == "engineer v1\n"
    assert (game / ".claude" / "hooks" / "launch.py").exists()
    assert set(json.loads((game / sync.LOCK).read_text())["files"]) == {
        ".claude/agents/engineer.md",
        ".claude/hooks/launch.py",
    }
    assert sync.drift(kit, game) == []
    assert sync.sync(kit, game, lambda _: None) == 0


def test_hand_edit_in_game_is_drift(tmp_path):
    kit, game = make_kit(tmp_path), tmp_path / "game"
    game.mkdir()
    sync.sync(kit, game, lambda _: None)
    (game / ".claude" / "agents" / "engineer.md").write_text("edited in the game\n")
    assert any("differs from the kit" in p for p in sync.drift(kit, game))


def test_crlf_checkout_is_not_drift(tmp_path):
    kit, game = make_kit(tmp_path), tmp_path / "game"
    game.mkdir()
    sync.sync(kit, game, lambda _: None)
    path = game / ".claude" / "agents" / "engineer.md"
    path.write_bytes(path.read_bytes().replace(b"\n", b"\r\n"))
    assert sync.drift(kit, game) == []


def test_file_dropped_by_kit_is_reported(tmp_path):
    kit, game = make_kit(tmp_path), tmp_path / "game"
    game.mkdir()
    sync.sync(kit, game, lambda _: None)
    (kit / ".claude" / "agents" / "engineer.md").unlink()
    assert any("no longer owned" in p for p in sync.drift(kit, game))


# --- the checker and the message-check hooks of .pre-commit-config.yaml (kit #151) ---

KIT_CONFIG = """\
default_language_version:
  node: 24.22.2
# gds-sync:begin install-hooks (kit-owned)
default_install_hook_types: [pre-commit, commit-msg, pre-push]
# gds-sync:end install-hooks
repos:
  - repo: local
    hooks:
      # gds-sync:begin message-checks (kit-owned)
      - id: commit-trailers
        entry: python .github/scripts/groundwork.py check-message
        stages: [commit-msg]
      - id: push-messages
        entry: python .github/scripts/groundwork.py check-push
        stages: [pre-push]
      # gds-sync:end message-checks
"""

GAME_CONFIG = """\
default_language_version:
  node: 24.22.2
# gds-sync:begin install-hooks (kit-owned)
default_install_hook_types: [pre-commit, commit-msg]
# gds-sync:end install-hooks
repos:
  - repo: https://github.com/Scony/godot-gdscript-toolkit
    rev: 4.5.0
    hooks:
      - id: gdformat
  - repo: local
    hooks:
      # gds-sync:begin message-checks (kit-owned)
      - id: commit-trailers
        entry: python .github/scripts/groundwork.py check-message
        stages: [commit-msg]
      # gds-sync:end message-checks
      - id: gd-uids
        entry: python tools/check_gd_uids.py
"""


def kit_with_checks(tmp_path):
    kit = make_kit(tmp_path)
    (kit / ".github" / "scripts").mkdir(parents=True)
    (kit / ".github" / "scripts" / "groundwork.py").write_text("print('check v2')\n")
    (kit / ".pre-commit-config.yaml").write_text(KIT_CONFIG)
    return kit


def game_with_old_checks(tmp_path):
    game = tmp_path / "game"
    (game / ".github" / "scripts").mkdir(parents=True)
    (game / ".github" / "scripts" / "groundwork.py").write_text("print('check v1')\n")
    (game / ".pre-commit-config.yaml").write_text(GAME_CONFIG)
    return game


def test_old_checker_and_hooks_in_a_game_are_drift(tmp_path):
    kit, game = kit_with_checks(tmp_path), game_with_old_checks(tmp_path)
    problems = sync.drift(kit, game)
    assert any(".github/scripts/groundwork.py: differs" in p for p in problems)
    assert any("block install-hooks differs" in p for p in problems)
    assert any("block message-checks differs" in p for p in problems)


def test_sync_writes_the_checker_and_only_the_kit_blocks(tmp_path):
    kit, game = kit_with_checks(tmp_path), game_with_old_checks(tmp_path)
    sync.sync(kit, game, lambda _: None)
    assert (game / ".github" / "scripts" / "groundwork.py").read_text() == "print('check v2')\n"
    config = (game / ".pre-commit-config.yaml").read_text()
    assert "default_install_hook_types: [pre-commit, commit-msg, pre-push]" in config
    assert "id: push-messages" in config and "stages: [pre-push]" in config
    assert "gdformat" in config and "id: gd-uids" in config  # the game's own hooks are untouched
    assert sync.drift(kit, game) == []
    lock = json.loads((game / sync.LOCK).read_text())
    assert set(lock["blocks"]) == {".pre-commit-config.yaml#install-hooks", ".pre-commit-config.yaml#message-checks"}
    assert sync.sync(kit, game, lambda _: None) == 0


def test_hand_edit_inside_a_block_is_drift(tmp_path):
    kit, game = kit_with_checks(tmp_path), game_with_old_checks(tmp_path)
    sync.sync(kit, game, lambda _: None)
    config = game / ".pre-commit-config.yaml"
    config.write_text(config.read_text().replace("check-push", "check-pushes"))
    assert any("block message-checks differs" in p for p in sync.drift(kit, game))


def test_game_without_the_markers_is_told_what_to_add(tmp_path):
    kit, game = kit_with_checks(tmp_path), game_with_old_checks(tmp_path)
    (game / ".pre-commit-config.yaml").write_text("repos: []\n")
    assert any("no `# gds-sync:begin message-checks` block" in p for p in sync.drift(kit, game))
    with pytest.raises(sync.SyncError, match="gds-sync:begin"):
        sync.sync(kit, game, lambda _: None)
    assert not (game / ".claude" / "agents" / "engineer.md").exists()  # nothing was written


def test_old_hook_left_outside_the_block_is_drift(tmp_path):
    kit, game = kit_with_checks(tmp_path), game_with_old_checks(tmp_path)
    config = game / ".pre-commit-config.yaml"
    config.write_text(config.read_text() + "      - id: push-messages\n        entry: old\n")
    assert any("push-messages is also defined outside" in p for p in sync.drift(kit, game))
    with pytest.raises(sync.SyncError, match="push-messages"):
        sync.sync(kit, game, lambda _: None)


def test_the_kits_own_config_defines_the_blocks_games_get():
    kit = Path(__file__).resolve().parents[2]
    found = sync.block_entries(kit)
    assert set(found) == {"install-hooks", "message-checks"}
    assert "pre-push" in found["install-hooks"]
    assert "check-push" in found["message-checks"] and "stages: [pre-push]" in found["message-checks"]
    assert (kit / ".github" / "scripts" / "groundwork.py").is_file()
    assert any(e.target == ".github/scripts/groundwork.py" for e in sync.entries(kit))


# --- the Godot addons the kit owns (kit #772) ---


def add_addon(kit):
    root = kit / "godot" / "addons" / "gds_ui"
    (root / "components").mkdir(parents=True)
    (root / "plugin.cfg").write_text('[plugin]\nname="gds_ui"\n')
    (root / "components" / "ui_button.gd").write_text("class_name UIButton\n")
    # Installed untracked beside it by `gds workspace init`; never the kit's to give away.
    (kit / "godot" / "addons" / "gdUnit4").mkdir()
    (kit / "godot" / "addons" / "gdUnit4" / "plugin.cfg").write_text("[plugin]\n")


def test_the_addon_goes_to_the_same_res_path_and_nothing_else_from_the_folder(tmp_path):
    kit, game = make_kit(tmp_path), tmp_path / "game"
    add_addon(kit)
    game.mkdir()
    sync.sync(kit, game, lambda _: None)
    assert (game / "game" / "addons" / "gds_ui" / "components" / "ui_button.gd").read_text() == "class_name UIButton\n"
    assert not (game / "game" / "addons" / "gdUnit4").exists()
    assert "game/addons/gds_ui/plugin.cfg" in json.loads((game / sync.LOCK).read_text())["files"]
    assert sync.drift(kit, game) == []


def test_a_hand_edit_in_the_addon_copy_is_drift(tmp_path):
    kit, game = make_kit(tmp_path), tmp_path / "game"
    add_addon(kit)
    game.mkdir()
    sync.sync(kit, game, lambda _: None)
    (game / "game" / "addons" / "gds_ui" / "components" / "ui_button.gd").write_text("class_name UIButton\nvar x\n")
    assert any("ui_button.gd: differs from the kit" in p for p in sync.drift(kit, game))


def test_a_file_the_kit_dropped_or_a_game_added_to_the_addon_is_drift_and_sync_removes_it(tmp_path):
    kit, game = make_kit(tmp_path), tmp_path / "game"
    add_addon(kit)
    game.mkdir()
    sync.sync(kit, game, lambda _: None)
    extra = game / "game" / "addons" / "gds_ui" / "components" / "ui_extra.gd"
    extra.write_text("extends Node\n")
    assert any("ui_extra.gd: not in the kit's addon" in p for p in sync.drift(kit, game))
    (kit / "godot" / "addons" / "gds_ui" / "components" / "ui_button.gd").unlink()
    assert sync.sync(kit, game, lambda _: None) == 2  # both removed
    assert not extra.exists()
    assert sync.drift(kit, game) == []


def test_the_real_kit_owns_the_addon_with_its_uids_and_none_of_the_third_party_ones():
    targets = {e.target for e in sync.entries(Path(__file__).resolve().parents[2])}
    assert "game/addons/gds_ui/plugin.cfg" in targets
    assert "game/addons/gds_ui/router/ui_router.gd.uid" in targets
    assert "game/addons/gds_game/trigger_zone/trigger_zone.gd.uid" in targets
    assert not [t for t in targets if t.startswith("game/addons/") and t.split("/")[2] not in sync.KIT_ADDONS]


def test_sync_warns_about_a_synced_addon_the_games_project_does_not_register(tmp_path, monkeypatch, capsys):
    from gds_tools import cli, workspace

    kit, game = make_kit(tmp_path), tmp_path / "game"
    add_addon(kit)
    (kit / "godot" / "addons" / "gds_ui" / "plugin.cfg").write_text("[plugin]\n")
    (game / "game").mkdir(parents=True)
    (game / "game" / "project.godot").write_text("config_version=5\n")
    monkeypatch.setattr(workspace, "kit_checkout", lambda: kit)
    assert cli.main(["sync", str(game)]) == 0
    warned = capsys.readouterr().err
    assert "warning: project.godot: [addon-autoload]" in warned
    assert "UIRouter" in warned
    assert "[addon-plugin]" in warned


# --- files that moved from a template into a kit addon (kit #923) ---

KIT = Path(__file__).resolve().parents[2]


def test_every_moved_file_is_in_the_kits_addon_with_its_uid():
    for old, new in sync.MOVED.items():
        target = KIT / sync.KIT_PROJECT / new.removeprefix("res://")
        assert target.is_file(), new
        assert target.with_name(target.name + ".uid").is_file(), new
        assert new.split("/")[3] in sync.KIT_ADDONS
        assert not old.startswith("res://addons/")


def test_no_template_keeps_a_moved_file_or_its_old_path():
    for template in (KIT / "templates").glob("*/game"):
        for old in sync.MOVED:
            assert not (template / old.removeprefix("res://")).exists(), f"{template.parent.name}: {old}"
        for path in template.rglob("*"):
            if path.suffix in sync.REFERENCE_SUFFIXES and path.is_file():
                text = path.read_text(encoding="utf-8", errors="replace")
                assert not [old for old in sync.MOVED if f'"{old}"' in text], path


def made_before_the_move(tmp_path):
    """A game as a template made it before #923: its own copies of the moved scripts and scenes naming them."""
    game = tmp_path / "old-game"
    project = game / "game"
    for old in sync.MOVED:
        path = project / old.removeprefix("res://")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"class_name {path.stem.title().replace('_', '')}\n")
        path.with_name(path.name + ".uid").write_text("uid://b0ld\n")
    zone = project / "gameplay" / "trigger_zone" / "trigger_zone.tscn"
    zone.write_text(
        '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://gameplay/trigger_zone/trigger_zone.gd" '
        'id="1_zone"]\n'
    )
    flash = project / "gameplay" / "weapon" / "muzzle_flash.tres"
    flash.parent.mkdir(parents=True)
    flash.write_text('[ext_resource type="Script" path="res://gameplay/effects/effect_def.gd" id="1_def"]\n')
    (project / "tests" / "fixtures" / "README.md").write_text("fixtures\n")
    (project / "tests" / "test_zone.gd").write_text("extends GdUnitTestSuite\nvar pins := ExportPins\n")
    # Kit #952: the presets stay the game's own beside the shake script that moved; the host scene names its script.
    preset = project / "core" / "camera_shake" / "presets" / "impact.tres"
    preset.parent.mkdir(parents=True)
    preset.write_text('[ext_resource type="Script" path="res://core/camera_shake/shake_preset.gd" id="1_preset"]\n')
    host = project / "ui" / "menus" / "screen_host.tscn"
    host.write_text('[ext_resource type="Script" path="res://ui/menus/screen_host.gd" id="1_host"]\n')
    return game


def test_a_game_made_before_the_move_is_drift_until_synced(tmp_path):
    game = made_before_the_move(tmp_path)
    problems = sync.drift(KIT, game)
    assert any("gameplay/trigger_zone/trigger_zone.gd: moved to res://addons/gds_game/" in p for p in problems)
    assert any("muzzle_flash.tres: names res://gameplay/effects/effect_def.gd" in p for p in problems)


def test_sync_moves_a_game_made_before_the_move_onto_the_addon(tmp_path):
    game = made_before_the_move(tmp_path)
    (game / ".pre-commit-config.yaml").write_text((KIT / ".pre-commit-config.yaml").read_text(encoding="utf-8"))
    lines = []
    sync.sync(KIT, game, lines.append)
    project = game / "game"
    for old, new in sync.MOVED.items():
        assert not (project / old.removeprefix("res://")).exists()
        assert (project / new.removeprefix("res://")).is_file()
    zone = (project / "gameplay" / "trigger_zone" / "trigger_zone.tscn").read_text()
    assert 'path="res://addons/gds_game/trigger_zone/trigger_zone.gd"' in zone
    assert "res://addons/gds_game/effects/effect_def.gd" in (project / "gameplay/weapon/muzzle_flash.tres").read_text()
    assert (project / "tests" / "test_zone.gd").read_text().endswith("ExportPins\n")  # a class name needs no change
    assert (project / "tests" / "fixtures" / "README.md").exists()
    preset = (project / "core" / "camera_shake" / "presets" / "impact.tres").read_text()
    assert 'path="res://addons/gds_game/camera_shake/shake_preset.gd"' in preset
    host = (project / "ui" / "menus" / "screen_host.tscn").read_text()
    assert 'path="res://addons/gds_game/screen_host/screen_host.gd"' in host
    assert any("removed game/tests/fixtures/input_sim.gd (moved to" in line for line in lines)
    assert sync.drift(KIT, game) == []
    # A second sync finds nothing left to move.
    assert sync.move_into_addons(game, lambda _: None) == 0
