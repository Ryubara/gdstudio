"""`gds template uids`: the `.uid` files of a template's scripts and shaders, written as Godot writes them.

A template's folder is not a project anyone opens in Godot, so its uid files were made by hand, and some held letters
Godot never writes (kit #1129). The text form is Godot's `ResourceUID.id_to_text` (base 34, `a`-`y` then `0`-`8`);
the pairs below were printed by the pinned Godot 4.7.2.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from gds_tools import cli, layout, uids, workspace

KIT = Path(__file__).resolve().parents[2]

#: (id, text) as the pinned Godot's `ResourceUID.id_to_text` prints them.
GODOT_PAIRS = [
    (0, "uid://a"),
    (1, "uid://b"),
    (24, "uid://y"),
    (25, "uid://0"),
    (33, "uid://8"),
    (34, "uid://ba"),
    (35, "uid://bb"),
    (2**63 - 1, "uid://d4n4ub6itg400"),
]


def project(root: Path, files: list[str]) -> Path:
    folder = root / "game"
    folder.mkdir()
    (folder / "project.godot").write_text("config_version=5\n", encoding="utf-8")
    for rel in files:
        path = folder / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        text = "shader_type spatial;\n" if path.suffix == ".gdshader" else "extends Node\n"
        path.write_text(text, encoding="utf-8")
    return folder


@pytest.mark.parametrize(("number", "text"), GODOT_PAIRS)
def test_the_text_form_is_godots(number, text):
    assert uids.id_to_text(number) == text
    assert uids.text_to_id(text) == number


@pytest.mark.parametrize(
    "text",
    [
        "uid://mxs9xj2t11c5n",  # a 9: Godot never writes one
        "uid://z99aef05w4va",  # a z
        "uid://cpartsbudget926",  # a word, too long for 63 bits
        "uid://d4n4ub6itg401",  # one past the largest id
        "uid://",
        "abc",
        "uid://ABC",
    ],
)
def test_a_text_godot_would_not_write_is_not_valid(text):
    assert not uids.is_valid(text)


def test_a_new_uid_is_valid_and_new_each_time():
    made = {uids.new_uid() for _ in range(200)}
    assert len(made) == 200
    assert all(uids.is_valid(text) for text in made)


def test_the_missing_files_are_written_and_an_existing_one_is_never_touched(tmp_path):
    game = project(tmp_path, ["core/a.gd", "ui/b.gd", "assets/shaders/s.gdshader", "addons/x/plugin.gd"])
    kept = game / "core" / "a.gd.uid"
    kept.write_bytes(b"uid://c7g41in1osxi6\n")
    result = uids.write_missing(game)
    assert sorted(p.relative_to(game).as_posix() for p in result.written) == [
        "assets/shaders/s.gdshader.uid",
        "ui/b.gd.uid",
    ]
    assert kept.read_bytes() == b"uid://c7g41in1osxi6\n"
    for path in result.written:
        raw = path.read_bytes()
        assert raw.endswith(b"\n") and b"\r" not in raw and not raw.startswith(b"\xef\xbb\xbf")
        assert uids.is_valid(raw.decode().strip())
    assert not (game / "addons" / "x" / "plugin.gd.uid").exists()  # an addon's files are its own
    assert uids.write_missing(game).written == []  # a second run writes nothing


def test_an_invalid_file_is_reported_and_replaced_only_when_asked(tmp_path):
    game = project(tmp_path, ["tests/test_a.gd"])
    bad = game / "tests" / "test_a.gd.uid"
    bad.write_text("uid://z99aef05w4va\n", encoding="utf-8")
    result = uids.write_missing(game)
    assert result.written == [] and result.invalid == [bad]
    assert bad.read_text(encoding="utf-8") == "uid://z99aef05w4va\n"
    result = uids.write_missing(game, replace_invalid=True)
    assert result.written == [bad] and result.invalid == []
    assert uids.is_valid(bad.read_text(encoding="utf-8").strip())


def test_the_layout_check_passes_after_the_command_and_names_it_before(tmp_path):
    game = project(tmp_path, ["core/a.gd", "assets/shaders/s.gdshader"])
    problems = layout.check(game)
    assert {(p.path, p.rule) for p in problems} == {("core/a.gd", "uid"), ("assets/shaders/s.gdshader", "uid")}
    assert all("gds template uids" in p.message for p in problems)
    uids.write_missing(game)
    assert layout.check(game) == []


def test_the_layout_check_refuses_a_uid_godot_would_not_write(tmp_path):
    game = project(tmp_path, ["core/a.gd"])
    (game / "core" / "a.gd.uid").write_text("uid://cpartsbudget926\n", encoding="utf-8")
    problems = layout.check(game)
    assert [(p.path, p.rule) for p in problems] == [("core/a.gd.uid", "uid")]
    assert "--replace-invalid" in problems[0].message


def tiny_template(kit: Path) -> Path:
    folder = kit / "templates" / "tiny"
    folder.mkdir(parents=True)
    (folder / "template.toml").write_text(
        'title = "Tiny"\ndescription = "d"\ndefault_description = "d"\n', encoding="utf-8"
    )
    return project(folder, ["core/a.gd"])


def test_the_command_takes_a_template_name_or_a_project_folder(tmp_path, monkeypatch, capsys):
    kit = tmp_path / "kit"
    game = tiny_template(kit)
    monkeypatch.setattr(cli, "_template_context", lambda: (kit, tmp_path))
    assert cli.main(["template", "uids", "tiny"]) == 0
    assert (game / "core" / "a.gd.uid").is_file()
    assert "core/a.gd.uid" in capsys.readouterr().out
    (tmp_path / "elsewhere").mkdir()
    other = project(tmp_path / "elsewhere", ["ui/b.gd"])
    assert cli.main(["template", "uids", str(other)]) == 0
    assert (other / "ui" / "b.gd.uid").is_file()


def test_the_command_exits_1_while_an_invalid_file_is_left(tmp_path, monkeypatch):
    kit = tmp_path / "kit"
    game = tiny_template(kit)
    (game / "core" / "a.gd.uid").write_text("uid://z\n", encoding="utf-8")
    monkeypatch.setattr(cli, "_template_context", lambda: (kit, tmp_path))
    assert cli.main(["template", "uids", "tiny"]) == 1
    assert cli.main(["template", "uids", "tiny", "--replace-invalid"]) == 0


def test_every_committed_template_uid_is_one_godot_writes():
    bad = [
        path.relative_to(KIT).as_posix()
        for path in sorted((KIT / "templates").rglob("*.uid"))
        if "addons" not in path.parts and not uids.is_valid(uids.read(path))
    ]
    assert bad == []


# --- the real thing -------------------------------------------------------------------------------------------------


def pinned_godot() -> Path:
    try:
        return workspace.tool_path("godot")
    except workspace.WorkspaceError:
        pytest.skip("the pinned Godot is not installed")


def test_godot_imports_the_written_files_without_rewriting_them(tmp_path):
    """The pinned Godot opens a project whose uid files the command wrote: it keeps every one byte for byte and
    writes no other."""
    godot = pinned_godot()
    game = project(tmp_path, ["core/a.gd", "gameplay/b.gd", "assets/shaders/s.gdshader", "tests/test_c.gd"])
    written = uids.write_missing(game).written
    before = {path: path.read_bytes() for path in written}
    run = subprocess.run(
        [str(godot), "--headless", "--path", str(game), "--import"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
        check=False,
    )
    assert "ERROR" not in run.stdout + run.stderr, run.stdout + run.stderr
    after = {path: path.read_bytes() for path in game.rglob("*.uid") if ".godot" not in path.parts}
    assert after == before
    shutil.rmtree(game / ".godot", ignore_errors=True)
