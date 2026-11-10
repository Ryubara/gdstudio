"""`gds new game`: a game made from the 3D Blank template is complete, in sync with the kit and follows its rules."""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from gds_tools import cli, layout, new_game, sync

KIT = Path(__file__).resolve().parents[2]


@pytest.fixture(autouse=True)
def git_identity(monkeypatch, tmp_path):
    """Commits need a name; a test never reads or writes the person's own git configuration."""
    for key, value in {
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.invalid",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.invalid",
        "GIT_CONFIG_GLOBAL": str(tmp_path / "gitconfig"),
        "GIT_CONFIG_SYSTEM": str(tmp_path / "gitconfig"),
    }.items():
        monkeypatch.setenv(key, value)


@pytest.fixture
def kit(tmp_path) -> Path:
    """A copy of the parts of the kit the command reads, so a test that records a remote writes to the copy."""
    copy = tmp_path / "kit"
    for rel in ("templates", "godot/addons", ".claude/agents", ".github/scripts", ".github/workflows"):
        shutil.copytree(KIT / rel, copy / rel, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    for rel in ("workspace.toml", "tools.toml", ".pre-commit-config.yaml"):
        shutil.copyfile(KIT / rel, copy / rel)
    return copy


@pytest.fixture
def root(tmp_path) -> Path:
    workspace = tmp_path / "workspace"
    (workspace / "repos").mkdir(parents=True)
    return workspace


def quiet_run(argv, *args, **kwargs):
    """Real git, a fake `uvx` (the hooks come from the network) and no output."""
    if argv[0] == "uvx":
        return subprocess.CompletedProcess(argv, 0, "", "")
    return subprocess.run(argv, *args, **kwargs)


def make(kit, root, name="my-game", **options):
    return new_game.new_game(kit, root, name, "3d-blank", log=lambda _: None, run=quiet_run, **options)


def text_files(repo: Path):
    for path in sorted(repo.rglob("*")):
        if (
            path.is_file()
            and ".git" not in path.relative_to(repo).parts
            and path.suffix not in {".png", ".svg", ".exr", ".lmbake", ".ttf", ".glb", ".ogg"}
        ):
            yield path


def test_the_game_has_what_a_game_repository_has(kit, root):
    repo = make(kit, root, title="My Game", description="A test game.").repo
    for rel in (
        "game/project.godot",
        "game/main.tscn",
        "game/export_presets.cfg",
        "game/world/prototype/prototype_level.tscn",
        "game/tests/test_main_scene.gd",
        ".github/conventions.yml",
        ".github/workflows/ci.yml",
        ".github/workflows/pr.yml",
        ".github/workflows/hold.yml",
        ".github/scripts/groundwork.py",
        ".github/scripts/pr_status.py",
        ".claude/hooks/launch.py",
        ".claude/agents/godot-engineer.md",
        ".claude/gds-sync.json",
        "game/addons/gds_ui/plugin.cfg",
        ".pre-commit-config.yaml",
        "AGENTS.md",
        "README.md",
        "mkdocs.yml",
        "docs/index.md",
        "docs/design/prototype-level.md",
    ):
        assert (repo / rel).is_file(), rel
    assert (repo / ".git").is_dir()


def test_no_placeholder_is_left_and_the_names_are_filled_in(kit, root):
    repo = make(kit, root, title="My Game", description="A test game.").repo
    for path in text_files(repo):
        assert not new_game.PLACEHOLDER.search(path.read_text(encoding="utf-8")), path
    assert 'config/name="My Game"' in (repo / "game" / "project.godot").read_text(encoding="utf-8")
    assert "repos/my-game" in (repo / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    assert "# My Game" in (repo / "README.md").read_text(encoding="utf-8")
    assert 'site_name: "My Game"' in (repo / "mkdocs.yml").read_text(encoding="utf-8")


def test_the_default_title_is_the_name_capitalised(kit, root):
    repo = make(kit, root, name="my-cool-game").repo
    assert 'config/name="My Cool Game"' in (repo / "game" / "project.godot").read_text(encoding="utf-8")


def test_the_game_starts_in_sync_with_the_kit_and_follows_the_layout_rules(kit, root):
    repo = make(kit, root).repo
    assert sync.drift(kit, repo) == []
    assert layout.check(repo / "game") == []
    lock = json.loads((repo / sync.LOCK).read_text(encoding="utf-8"))
    assert ".claude/hooks/launch.py" in lock["files"]


@pytest.mark.parametrize("command", ["validate", "render --check", "check-files"])
def test_the_conventions_and_the_files_generated_from_them_agree(kit, root, command):
    repo = make(kit, root).repo
    done = subprocess.run(
        [sys.executable, ".github/scripts/groundwork.py", *command.split()],
        cwd=repo,
        capture_output=True,
        text=True,
        check=False,
    )
    assert done.returncode == 0, done.stdout + done.stderr


def test_the_first_commit_holds_everything_with_a_title_the_conventions_accept(kit, root):
    made = make(kit, root)
    assert made.committed
    log = subprocess.run(
        ["git", "-C", str(made.repo), "log", "--format=%s"], capture_output=True, text=True, check=True
    ).stdout.splitlines()
    assert log == ["build: Add the 3D Blank starter"]
    status = subprocess.run(
        ["git", "-C", str(made.repo), "status", "--porcelain"], capture_output=True, text=True, check=True
    ).stdout
    assert status == ""
    title = made.repo / "title.txt"
    title.write_text(log[0], encoding="utf-8")
    done = subprocess.run(
        [sys.executable, ".github/scripts/groundwork.py", "check-title", str(title)],
        cwd=made.repo,
        capture_output=True,
        text=True,
        check=False,
    )
    assert done.returncode == 0, done.stderr


def test_a_failed_commit_leaves_the_files_staged_and_says_so(kit, root):
    def no_commit(argv, *args, **kwargs):
        if "commit" in argv:
            return subprocess.CompletedProcess(argv, 1, "", "no identity")
        return quiet_run(argv, *args, **kwargs)

    made = new_game.new_game(kit, root, "my-game", "3d-blank", log=lambda _: None, run=no_commit)
    assert not made.committed
    assert any("commit the files" in step for step in made.todo)


def test_a_remote_is_recorded_as_origin_and_in_workspace_toml_and_nothing_is_pushed(kit, root):
    url = "https://github.com/Ryubara/my-game.git"
    made = make(kit, root, remote=url)
    origin = subprocess.run(
        ["git", "-C", str(made.repo), "remote", "get-url", "origin"], capture_output=True, text=True, check=True
    ).stdout.strip()
    assert origin == url
    registered = (kit / "workspace.toml").read_text(encoding="utf-8")
    assert f'[repos.my-game]\nurl = "{url}"\nrole = "game"' in registered
    assert any("workspace.toml entry" in step for step in made.todo)


def test_without_a_remote_the_workspace_file_is_left_alone(kit, root):
    before = (kit / "workspace.toml").read_text(encoding="utf-8")
    made = make(kit, root)
    assert (kit / "workspace.toml").read_text(encoding="utf-8") == before
    assert any("add [repos.my-game] to the kit's workspace.toml" in step for step in made.todo)


def test_local_lists_the_github_steps_it_left_out(kit, root):
    todo = make(kit, root).todo
    assert any("create the GitHub repository" in step for step in todo)
    assert not any("maintainer" in step for step in todo)


def test_pinned_addons_that_are_fetched_are_installed_untracked(kit, root):
    addon = root / "tools" / "gdunit4-6.2.2" / "gdUnit4-6.2.2" / "addons" / "gdUnit4"
    addon.mkdir(parents=True)
    (addon / "plugin.cfg").write_text("[plugin]\n", encoding="utf-8")
    repo = make(kit, root).repo
    assert (repo / "game" / "addons" / "gdUnit4" / "plugin.cfg").is_file()
    exclude = (repo / ".git" / "info" / "exclude").read_text(encoding="utf-8")
    assert "/game/addons/gdUnit4/" in exclude
    tracked = subprocess.run(
        ["git", "-C", str(repo), "ls-files", "game/addons"], capture_output=True, text=True, check=True
    ).stdout
    assert "gdUnit4" not in tracked


@pytest.mark.parametrize("name", ["My-Game", "my_game", "1game", "my game", "-game", "game-", "a" * 40, ""])
def test_a_name_that_is_not_a_repository_name_is_refused(kit, root, name):
    with pytest.raises(new_game.NewGameError, match="not a game name"):
        make(kit, root, name=name)


def test_an_existing_folder_is_never_overwritten(kit, root):
    (root / "repos" / "my-game").mkdir()
    with pytest.raises(new_game.NewGameError, match="exists already"):
        make(kit, root)


def test_a_name_the_workspace_already_lists_is_refused(kit, root):
    with pytest.raises(new_game.NewGameError, match="already has a repository"):
        make(kit, root, name="deadnight")


def test_an_unknown_template_names_the_ones_there_are(kit, root):
    for name in ("nope", "game", "repo"):
        with pytest.raises(new_game.NewGameError, match="3d-blank"):
            new_game.new_game(kit, root, "my-game", name, log=lambda _: None, run=quiet_run)
    assert not (root / "repos" / "my-game").exists()


@pytest.mark.parametrize("bad", ['say "hi"', "back\\slash", "two\nlines", "  ", "x" * 101])
def test_a_title_or_description_that_would_break_a_quoted_file_is_refused(kit, root, bad):
    with pytest.raises(new_game.NewGameError, match="one line of at most"):
        make(kit, root, title=bad)
    with pytest.raises(new_game.NewGameError, match="one line of at most"):
        make(kit, root, description=bad)


def test_render_fills_placeholders_makes_line_endings_lf_and_leaves_binary_alone():
    assert new_game.render(b"# {GAME_TITLE}\r\nline\r\n", {"{GAME_TITLE}": "A"}) == b"# A\nline\n"
    binary = b"\x89PNG\r\n\x1a\n\xff\xfe{GAME_TITLE}"
    assert new_game.render(binary, {"{GAME_TITLE}": "A"}) == binary


def test_a_placeholder_the_command_does_not_know_stops_the_copy(tmp_path):
    source, target = tmp_path / "source", tmp_path / "target"
    source.mkdir()
    (source / "a.md").write_text("{GAME_COLOUR}\n", encoding="utf-8")
    with pytest.raises(new_game.NewGameError, match=r"\{GAME_COLOUR\}"):
        new_game.copy_tree(source, target, {"{GAME_TITLE}": "A"})


def test_the_kit_repository_comes_from_its_workspace_entry(kit):
    assert new_game.kit_repo(kit) == "Ryubara/gdstudio"


def test_the_templates_the_kit_has_are_listed():
    assert new_game.available(KIT) == ["3d-blank", "3d-third-person"]


def test_the_command_prints_what_is_left(kit, root, monkeypatch, capsys):
    monkeypatch.setattr(cli.workspace, "kit_checkout", lambda: kit)
    monkeypatch.setattr(new_game, "new_game", lambda *a, **k: new_game.Made(root / "repos" / "x", True, ["do this"]))
    (root / ".gdstudio-workspace").write_text("marker\n", encoding="utf-8")
    code = cli.main(["new", "game", "x", "--template", "3d-blank", "--local", "--workspace", str(root)])
    out = capsys.readouterr().out
    assert code == 0
    assert "left to do:" in out and "- do this" in out


def test_the_command_reports_a_refusal_with_exit_code_two(kit, root, monkeypatch, capsys):
    monkeypatch.setattr(cli.workspace, "kit_checkout", lambda: kit)
    (root / ".gdstudio-workspace").write_text("marker\n", encoding="utf-8")
    code = cli.main(["new", "game", "Bad Name", "--template", "3d-blank", "--workspace", str(root)])
    assert code == 2
    assert "not a game name" in capsys.readouterr().err


def make_template(kit: Path, name: str, extends: str | None, files: dict[str, str]) -> None:
    folder = kit / "templates" / name
    folder.mkdir(parents=True)
    head = f'title = "{name}"\ndescription = "d"\ndefault_description = "A game from {name}."\n'
    (folder / "template.toml").write_text(head + (f'extends = "{extends}"\n' if extends else ""), encoding="utf-8")
    for rel, text in files.items():
        (folder / rel).parent.mkdir(parents=True, exist_ok=True)
        (folder / rel).write_text(text, encoding="utf-8")


def test_a_template_that_extends_another_adds_its_files_on_top_of_the_base(kit, root):
    make_template(
        kit,
        "third-demo",
        "3d-blank",
        {"game/gameplay/player/player.gd": "extends Node\n", "docs/design/index.md": "# Third person\n"},
    )
    repo = new_game.new_game(kit, root, "my-game", "third-demo", log=lambda _: None, run=quiet_run).repo
    assert (repo / "game" / "world" / "prototype" / "prototype_level.tscn").is_file()  # the base's level
    assert (repo / "game" / "gameplay" / "player" / "player.gd").is_file()  # the template's own file
    assert (repo / "docs" / "design" / "index.md").read_text(encoding="utf-8") == "# Third person\n"
    assert not (repo / "template.toml").exists()
    assert "A game from third-demo." in (repo / "README.md").read_text(encoding="utf-8")


def test_templates_that_extend_each_other_are_refused(kit, root):
    make_template(kit, "a", "b", {})
    make_template(kit, "b", "a", {})
    with pytest.raises(new_game.NewGameError, match="extend each other"):
        new_game.new_game(kit, root, "my-game", "a", log=lambda _: None, run=quiet_run)
    assert not (root / "repos" / "my-game").exists()


def test_a_template_that_extends_one_the_kit_lacks_names_what_there_is(kit, root):
    make_template(kit, "orphan", "missing", {})
    with pytest.raises(new_game.NewGameError, match="no template 'missing'"):
        new_game.new_game(kit, root, "my-game", "orphan", log=lambda _: None, run=quiet_run)


def test_every_pre_commit_run_in_the_game_workflows_names_one_hook():
    """`pre-commit run` takes one hook id: `run gdformat gdlint` failed every new game's first CI (kit #779). The
    kit's template job runs all hooks with --all-files, so only the game's own command line shows it."""
    import shlex

    for workflow in sorted((KIT / "templates" / "repo" / ".github" / "workflows").glob("*.yml")):
        for line in workflow.read_text(encoding="utf-8").splitlines():
            words = shlex.split(line.split("run:", 1)[-1]) if '"$PRE_COMMIT" run' in line else []
            if words:
                hooks = [w for w in words[words.index("run") + 1 :] if not w.startswith("-")]
                assert len(hooks) <= 1, f"{workflow.name}: {line.strip()}"


def test_the_third_person_project_file_is_the_blank_one_plus_its_input_orientation_and_jolt():
    """An extending template replaces a file whole, so 3D Third Person carries its own `project.godot`. It must not
    drift from 3D Blank's: the same text, but for the input map, the landscape setting (kit #821), Jolt
    Physics, which the ragdoll needs (kit #846), and the navigation map's 0.1 m cell height, which lets the map
    sections' baked meshes climb a stair the way the character does (kit #885)."""
    blank = (KIT / "templates" / "3d-blank" / "game" / "project.godot").read_text(encoding="utf-8")
    third = (KIT / "templates" / "3d-third-person" / "game" / "project.godot").read_text(encoding="utf-8")
    without_input = re.sub(r"\[input\]\n.*?(?=\n\[)", "", third, flags=re.DOTALL).replace("\n\n\n", "\n\n")
    without_input = without_input.replace("window/handheld/orientation=0\n", "")
    without_input = without_input.replace('3d/physics_engine="Jolt Physics"\n', "")
    without_input = without_input.replace("[navigation]\n\n3d/default_cell_height=0.1\n\n", "")
    assert without_input.strip() == blank.strip()
    assert "[input]" in third and "window/handheld/orientation=0" in third
    assert '3d/physics_engine="Jolt Physics"' in third
    assert "3d/default_cell_height=0.1" in third


def test_the_third_person_game_has_every_file_of_the_blank_one_and_its_own(kit, root):
    """The base's files go in first and the template's on top: the made game holds both."""
    made = new_game.new_game(kit, root, "my-game", "3d-third-person", log=lambda _: None, run=quiet_run)
    game = made.repo / "game"
    assert (game / "world" / "prototype" / "prototype_level.tscn").is_file()
    assert (game / "ui" / "touch" / "touch_controls.gd").is_file()  # the base's
    assert (game / "gameplay" / "player" / "player.gd").is_file()  # the template's
    assert (game / "assets" / "animation" / "universal" / "LICENSE.md").is_file()
    assert (game / "addons" / "phantom_camera" / "LICENSE.md").is_file()
    assert layout.check(game) == []
