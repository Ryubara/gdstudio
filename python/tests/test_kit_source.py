"""The template source is the kit checkout whose `gds` runs, never the folder you stand in or another worktree
(new-game.md#proof, kit #1048).

Two worktrees of one kit repository, each with its own copy of `gds_tools`: the code of one, run from inside the other,
names its own checkout and its own branch, both ways round."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from gds_tools import template_test, workspace

KIT = Path(__file__).resolve().parents[2]
SOURCE = KIT / "python" / "src" / "gds_tools"


def git(*args: str, cwd: Path) -> str:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True).stdout


@pytest.fixture
def two_worktrees(tmp_path: Path, monkeypatch) -> tuple[Path, Path, Path]:
    """A workspace with a kit repository and two worktrees of it, `worktrees/gdstudio/one` on branch `one` and
    `.../two` on branch `two`, each with the kit's files `kit_checkout` looks for and its own `gds_tools`."""
    for key, value in {
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.invalid",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.invalid",
        "GIT_CONFIG_GLOBAL": str(tmp_path / "gitconfig"),
        "GIT_CONFIG_SYSTEM": str(tmp_path / "gitconfig"),
    }.items():
        monkeypatch.setenv(key, value)
    root = tmp_path / "ws"
    kit = root / "repos" / "gdstudio"
    kit.mkdir(parents=True)
    (root / workspace.MARKER).write_text("marker\n", encoding="utf-8")
    shutil.copyfile(KIT / "tools.toml", kit / "tools.toml")
    shutil.copyfile(KIT / "workspace.toml", kit / "workspace.toml")
    (kit / ".gitignore").write_text("__pycache__/\n", encoding="utf-8")  # as the kit's own: running it writes them
    shutil.copytree(SOURCE, kit / "python" / "src" / "gds_tools", ignore=shutil.ignore_patterns("__pycache__"))
    git("init", "-q", "-b", "main", cwd=kit)
    git("add", "-A", cwd=kit)
    git("commit", "-q", "-m", "kit", cwd=kit)
    one, two = root / "worktrees" / "gdstudio" / "one", root / "worktrees" / "gdstudio" / "two"
    git("worktree", "add", "-q", "-b", "one", str(one), cwd=kit)
    git("worktree", "add", "-q", "-b", "two", str(two), cwd=kit)
    (two / "changed.txt").write_text("not committed\n", encoding="utf-8")
    return root, one, two


def source_seen(code_from: Path, stand_in: Path) -> dict[str, str]:
    """Run `gds_tools` from `code_from`'s checkout with `stand_in` as the current folder, as `uv run --project
    <code_from>/python gds ...` from `stand_in` does, and return the kit the template commands would read."""
    probe = (
        "import json, sys\n"
        f"sys.path.insert(0, {str(code_from / 'python' / 'src')!r})\n"
        "from gds_tools import cli, workspace\n"
        "kit, root = cli._template_context()\n"
        "print(json.dumps({'module': workspace.__file__, 'kit': str(kit), 'root': str(root),"
        " 'described': workspace.describe_kit(kit)}))\n"
    )
    env = {k: v for k, v in os.environ.items() if k not in ("PYTHONPATH", "VIRTUAL_ENV")}
    done = subprocess.run(
        [sys.executable, "-c", probe], cwd=stand_in, capture_output=True, text=True, check=True, env=env
    )
    return json.loads(done.stdout)


@pytest.mark.parametrize("runs, stands", [("one", "two"), ("two", "one")])
def test_the_source_is_the_checkout_that_runs_gds_not_the_one_you_stand_in(two_worktrees, runs, stands):
    root, one, two = two_worktrees
    checkouts = {"one": one, "two": two}
    seen = source_seen(checkouts[runs], checkouts[stands])
    assert Path(seen["module"]).resolve().is_relative_to(checkouts[runs].resolve())
    assert Path(seen["kit"]).resolve() == checkouts[runs].resolve()
    assert Path(seen["root"]).resolve() == root.resolve()
    assert seen["described"].startswith(f"{runs} at ")
    assert seen["described"].endswith("1 changed file(s)" if runs == "two" else "0 changed file(s)")


def test_the_source_is_the_checkout_that_runs_gds_from_the_main_checkout_too(two_worktrees):
    """The kit's main checkout is the usual folder an agent stands in; `--project <worktree>/python` still wins."""
    root, one, _ = two_worktrees
    seen = source_seen(one, root / "repos" / "gdstudio")
    assert Path(seen["kit"]).resolve() == one.resolve()


def test_a_folder_that_is_not_a_checkout_is_described_as_such(tmp_path):
    assert workspace.describe_kit(tmp_path) == "not a git checkout"


def test_the_template_test_log_starts_with_the_source_and_its_branch(two_worktrees, tmp_path, monkeypatch):
    """The first line names the kit and its branch, so a log that holds another run's lines shows it at once."""
    _, one, _ = two_worktrees
    lines: list[str] = []
    monkeypatch.setattr(template_test.new_game, "load_template", lambda kit, name: None)
    monkeypatch.setattr(template_test.workspace, "tool_path", lambda name, root: tmp_path / "godot")

    def stop(*_):
        raise RuntimeError("stop after the first lines")

    folder = tmp_path / f"{template_test.PREFIX}x"
    folder.mkdir()
    monkeypatch.setattr(template_test, "make_throwaway", lambda real, kit, base: folder)
    with pytest.raises(RuntimeError):
        template_test.run_template_test(one, tmp_path, "tiny", maker=stop, log=lines.append)
    commit = git("rev-parse", "--short", "HEAD", cwd=one).strip()
    assert lines[0] == f"kit       {one} (one at {commit}, 0 changed file(s))"
    assert lines[1].startswith("workspace ")


def test_template_game_keeps_stdout_to_the_games_path(monkeypatch, tmp_path, capsys):
    """`game=$(gds template game <t>)` reads the path alone; the source line goes to stderr with the hints."""
    from gds_tools import cli

    game = tmp_path / "game"

    def make_game(kit, root, name, *, log):
        log(f"kit       {kit} (one at abc1234, 0 changed file(s))")
        return game

    monkeypatch.setattr(cli, "_template_context", lambda: (tmp_path / "kit", tmp_path))
    monkeypatch.setattr(template_test, "make_game", make_game)
    assert cli.main(["template", "game", "tiny"]) == 0
    out, err = capsys.readouterr()
    assert out.strip() == str(game)
    assert err.startswith("kit       ")
