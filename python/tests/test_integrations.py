"""The integrations init sets up: the untracked Godot MCP addon in each game, MCP registration, Blender extensions,
and the new tools.toml entries."""

import subprocess
from pathlib import Path

from gds_tools import fetch, integrations
from gds_tools.manifest import load_mcp, load_tools

KIT = Path(__file__).resolve().parents[2]


PROJECT = """config_version=5

[application]

config/name="Game"

[editor_plugins]

enabled=PackedStringArray("res://addons/gds_ui/plugin.cfg")

[input]
"""


def make_game(tmp_path: Path) -> Path:
    project = tmp_path / "repos" / "game" / "game"
    project.mkdir(parents=True)
    (project / "project.godot").write_text(PROJECT, newline="\n")
    (tmp_path / "repos" / "game" / ".git" / "info").mkdir(parents=True)
    return project


def git(repo: Path, *args: str) -> str:
    done = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True, check=True)
    return done.stdout


def make_git_game(tmp_path: Path) -> Path:
    """A real git repository with a committed game/project.godot (the Godot 4.7 editor reads plugins only there)."""
    repo = tmp_path / "repos" / "game"
    project = repo / "game"
    project.mkdir(parents=True)
    (project / "project.godot").write_text(PROJECT, newline="\n")
    git(repo, "init", "-q", "-b", "main")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "add", "-A")
    git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "start")
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
    assert '"res://addons/godot_mcp/plugin.cfg"' in (project / "project.godot").read_text()
    assert not (project / "override.cfg").exists()  # the 4.7 editor never reads it (#1005)
    exclude = (project.parent / ".git" / "info" / "exclude").read_text()
    assert "/game/addons/godot_mcp/" in exclude
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


def test_two_plugins_join_the_committed_list(tmp_path):
    project_file = tmp_path / "project.godot"
    project_file.write_text(PROJECT, newline="\n")
    assert integrations.enable_plugin(project_file, "res://addons/a/plugin.cfg")
    assert integrations.enable_plugin(project_file, "res://addons/b/plugin.cfg")
    assert not integrations.enable_plugin(project_file, "res://addons/a/plugin.cfg")
    text = project_file.read_text()
    assert text.count("[editor_plugins]") == 1
    assert '"res://addons/gds_ui/plugin.cfg", "res://addons/a/plugin.cfg", "res://addons/b/plugin.cfg")' in text


def test_a_project_without_a_plugin_list_is_left_alone(tmp_path):
    project_file = tmp_path / "project.godot"
    project_file.write_text("config_version=5\n", newline="\n")
    assert not integrations.enable_plugin(project_file, "res://addons/a/plugin.cfg")
    assert project_file.read_text() == "config_version=5\n"


def test_the_old_override_loses_the_plugins_it_listed(tmp_path):
    project, tool = make_game(tmp_path), make_addon(tmp_path)
    (project / "override.cfg").write_text(
        '[editor_plugins]\n\nenabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")\n'
    )
    integrations.install_godot_addon(tool, "godot_mcp", "addons/godot_mcp", project, lambda _: None)
    assert not (project / "override.cfg").exists()


def test_enabled_plugins_stay_out_of_commits(tmp_path):
    """#1005: the plugins are listed in the real project.godot (the 4.7 editor ignores override.cfg), and a local clean
    filter keeps them out of every commit, diff and status, in the checkout and in its worktrees."""
    project, tool = make_git_game(tmp_path), make_addon(tmp_path)
    repo = project.parent
    gdunit = tmp_path / "tools" / "gdunit4-1"
    (gdunit / "addons" / "gdUnit4").mkdir(parents=True)
    (gdunit / "addons" / "gdUnit4" / "plugin.cfg").write_text("[plugin]")
    assert integrations.install_godot_addon(tool, "godot_mcp", "addons/godot_mcp", project, lambda _: None)
    assert integrations.install_godot_addon(gdunit, "gdUnit4", "addons/gdUnit4", project, lambda _: None)
    text = (project / "project.godot").read_text()
    mcp, gdunit_entry = '"res://addons/godot_mcp/plugin.cfg"', '"res://addons/gdUnit4/plugin.cfg"'
    assert f'"res://addons/gds_ui/plugin.cfg", {mcp}, {gdunit_entry})' in text
    assert git(repo, "status", "--porcelain") == ""
    assert git(repo, "diff") == ""
    # a real change beside them is committed without them
    (project / "project.godot").write_text(text.replace('config/name="Game"', 'config/name="Renamed"'), newline="\n")
    git(repo, "add", "game/project.godot")
    staged = git(repo, "show", ":game/project.godot")
    assert 'config/name="Renamed"' in staged and "godot_mcp" not in staged and "gdUnit4" not in staged
    assert '"res://addons/gds_ui/plugin.cfg")' in staged
    git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "rename")
    # a checkout writes them back where the addon is installed
    (project / "project.godot").unlink()
    git(repo, "checkout", "--", "game/project.godot")
    assert f"{mcp}, {gdunit_entry})" in (project / "project.godot").read_text()
    assert git(repo, "status", "--porcelain") == ""
    # a fresh worktree has no addons yet, so it names none (Godot would report a missing plugin)
    worktree = tmp_path / "worktrees" / "game" / "branch"
    git(repo, "worktree", "add", "-q", "-b", "branch", str(worktree))
    assert "godot_mcp" not in (worktree / "game" / "project.godot").read_text()
    assert git(worktree, "status", "--porcelain") == ""


def test_the_kits_own_godot_project_gets_the_addons_too(tmp_path):
    project = tmp_path / "repos" / "gdstudio" / "godot"
    project.mkdir(parents=True)
    (project / "project.godot").write_text("")
    (tmp_path / "repos" / "gdstudio" / ".git" / "info").mkdir(parents=True)
    tool = make_addon(tmp_path)
    assert integrations.game_projects(tmp_path / "repos") == [project]
    assert integrations.install_godot_addon(tool, "godot_mcp", "addons/godot_mcp", project, lambda _: None)
    assert (project / "addons" / "godot_mcp" / "plugin.cfg").exists()
    exclude = (project.parent / ".git" / "info" / "exclude").read_text()
    assert "/godot/addons/godot_mcp/" in exclude
