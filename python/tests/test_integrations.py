"""The integrations init sets up: the untracked Godot MCP addon in each game, MCP registration, Blender extensions,
and the new tools.toml entries."""

import subprocess
from pathlib import Path

from gds_tools import fetch, integrations
from gds_tools.manifest import load_mcp, load_tools

KIT = Path(__file__).resolve().parents[2]


def make_game(tmp_path: Path) -> Path:
    project = tmp_path / "repos" / "game" / "game"
    project.mkdir(parents=True)
    (project / "project.godot").write_text("")
    (tmp_path / "repos" / "game" / ".git" / "info").mkdir(parents=True)
    return project


def make_addon(tmp_path: Path) -> Path:
    tool = tmp_path / "tools" / "godot-mcp-addon-1"
    (tool / "addons" / "godot_mcp").mkdir(parents=True)
    (tool / "addons" / "godot_mcp" / "plugin.cfg").write_text("[plugin]")
    (tool / ".gds-installed").write_text("sha256:abc\n")
    return tool


def test_addon_installed_enabled_and_excluded_once(tmp_path):
    project, tool = make_game(tmp_path), make_addon(tmp_path)
    assert integrations.game_projects(tmp_path / "repos") == [project]
    assert integrations.install_godot_addon(tool, "godot_mcp", "addons/godot_mcp", project, lambda _: None)
    assert (project / "addons" / "godot_mcp" / "plugin.cfg").exists()
    assert '"res://addons/godot_mcp/plugin.cfg"' in (project / "override.cfg").read_text()
    exclude = (project.parent / ".git" / "info" / "exclude").read_text()
    assert "/game/addons/godot_mcp/" in exclude and "/game/override.cfg" in exclude
    assert not integrations.install_godot_addon(
        tool, "godot_mcp", "addons/godot_mcp", project, lambda _: None
    )  # second run: nothing to do


def test_register_mcp_skips_registered_and_adds_missing(tmp_path, monkeypatch):
    monkeypatch.setattr(integrations.shutil, "which", lambda name: "claude")
    calls = []

    def runner(cmd, cwd):
        calls.append(cmd)
        registered = cmd[:3] == ["claude", "mcp", "get"] and cmd[3] == "godot"
        return subprocess.CompletedProcess(cmd, 0 if registered or cmd[2] == "add" else 1, "", "")

    added = integrations.register_mcp(
        [tmp_path], {"godot": ["uvx", "g"], "blender": ["uv", "run"]}, lambda _: None, runner
    )
    assert added == 1
    assert ["claude", "mcp", "add", "-s", "local", "blender", "--", "uv", "run"] in calls


def test_resolve_command_names_tool_folders(tmp_path):
    words = integrations.resolve_command(["uv", "--directory", "{tool:srv}"], tmp_path, {"srv": "srv-1"})
    assert words[-1] == (tmp_path / "srv-1").as_posix()


def test_kit_lists_the_new_tools_and_servers():
    tools = load_tools(KIT / "tools.toml")
    assert {"ffmpeg", "godot-mcp-addon", "gdunit4", "blender-mcp-addon", "blender-mcp-server"} <= set(tools)
    assert tools["gdunit4"].extra == {"addon": "gdUnit4", "source": "gdUnit4-6.2.2/addons/gdUnit4"}
    assert tools["blender-mcp-addon"].requires == "blender"
    assert set(load_mcp(KIT / "tools.toml")) == {"godot", "blender"}


def test_blender_install_makes_it_portable(tmp_path):
    import zipfile

    archive = tmp_path / "b.zip"
    with zipfile.ZipFile(archive, "w") as zf:
        zf.writestr("b/blender.exe", "bin")
    import hashlib

    item = fetch.Download(
        "https://e/b.zip", "sha256", hashlib.sha256(archive.read_bytes()).hexdigest(), exe="b/blender.exe"
    )
    tool = fetch.Tool("blender", "9", "blender", True, None, {"any": item})
    target = fetch.install(tool, item, archive, tmp_path / "tools", {"blender": tool})
    assert (target / "b" / "portable").is_dir()


def test_two_plugins_share_one_override(tmp_path):
    override = tmp_path / "override.cfg"
    assert integrations.enable_plugin(override, "res://addons/a/plugin.cfg")
    assert integrations.enable_plugin(override, "res://addons/b/plugin.cfg")
    assert not integrations.enable_plugin(override, "res://addons/a/plugin.cfg")
    text = override.read_text()
    assert text.count("[editor_plugins]") == 1
    assert '"res://addons/a/plugin.cfg", "res://addons/b/plugin.cfg"' in text
