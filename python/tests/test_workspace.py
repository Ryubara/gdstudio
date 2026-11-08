"""Workspace init end to end with downloads stubbed out, and workspace discovery."""

import subprocess
from pathlib import Path

from gds_tools import fetch, workspace


def test_init_creates_layout_marker_and_config_and_is_idempotent(tmp_path, monkeypatch):
    installed = []
    monkeypatch.setattr(fetch, "is_installed", lambda *a: False)
    monkeypatch.setattr(fetch, "download", lambda item, cache, log: Path("archive"))
    monkeypatch.setattr(fetch, "install", lambda tool, *a: installed.append(tool.name))
    logs: list[str] = []

    code = workspace.init(tmp_path, ["godot"], clone=False, dry_run=False, log=logs.append)

    assert code in (0, 1)  # 1 only when a prerequisite is missing on this machine
    for folder in ("repos", "worktrees", "scratch", "cache", "tools", "refs", "vault"):
        assert (tmp_path / folder).is_dir()
    assert (tmp_path / workspace.MARKER).exists()
    assert (tmp_path / workspace.LOCAL_FILE).exists()
    assert installed == ["godot"]

    logs.clear()
    workspace.init(tmp_path, ["none"], clone=False, dry_run=False, log=logs.append)
    assert not any(line.startswith("create") for line in logs)


def _fake_tools(monkeypatch, found: dict[str, str | None], codes: dict[str, int]):
    """`shutil.which` finds the programs of `found`; each program's commands return its code from `codes`."""
    monkeypatch.setattr(workspace.shutil, "which", lambda name: found.get(name))
    monkeypatch.setattr(
        workspace,
        "run",
        lambda cmd, cwd=None: subprocess.CompletedProcess(cmd, codes.get(cmd[0], 0), "", ""),
    )


def _game(root: Path, name: str, *, deploys: bool = False, exports: bool = False) -> None:
    game = root / "repos" / name / "game"
    game.mkdir(parents=True)
    (game / "project.godot").write_text("", encoding="utf-8")
    if deploys:
        (root / "repos" / name / "deploy").mkdir()
    if exports:
        (game / "export_presets.cfg").write_text("", encoding="utf-8")


def test_services_warn_when_gh_is_signed_out_and_never_require(tmp_path, monkeypatch):
    _fake_tools(monkeypatch, {"gh": "gh"}, {"gh": 1})

    checks = workspace.check_services(tmp_path)

    assert [(c.name, c.ok, c.required) for c in checks] == [("gh", False, False)]
    assert "gh auth login" in checks[0].detail


def test_services_check_railway_and_templates_only_for_games_that_need_them(tmp_path, monkeypatch):
    _game(tmp_path, "quiet")
    _fake_tools(monkeypatch, {"gh": "gh", "railway": "railway"}, {})
    assert [c.name for c in workspace.check_services(tmp_path)] == ["gh"]

    _game(tmp_path, "loud", deploys=True, exports=True)
    godot = tmp_path / "tools" / "godot" / "godot.exe"
    godot.parent.mkdir(parents=True)
    monkeypatch.setattr(workspace, "tool_path", lambda name, root=None: godot)
    checks = {c.name: c for c in workspace.check_services(tmp_path)}
    assert checks["railway"].ok
    assert not checks["godot export templates"].ok
    assert "loud" in checks["godot export templates"].detail

    (godot.parent / "editor_data" / "export_templates" / "4.7.2.stable").mkdir(parents=True)
    assert {c.name: c for c in workspace.check_services(tmp_path)}["godot export templates"].ok


def test_services_name_the_game_when_railway_is_missing(tmp_path, monkeypatch):
    _game(tmp_path, "online", deploys=True)
    _fake_tools(monkeypatch, {"gh": "gh"}, {})

    railway = {c.name: c for c in workspace.check_services(tmp_path)}["railway"]

    assert not railway.ok and "online" in railway.detail


def test_dry_run_changes_nothing(tmp_path):
    workspace.init(tmp_path, None, clone=True, dry_run=True, log=lambda _: None)
    assert list(tmp_path.iterdir()) == []


def test_find_workspace_from_nested_folder(tmp_path):
    (tmp_path / workspace.MARKER).write_text("")
    nested = tmp_path / "worktrees" / "game" / "branch"
    nested.mkdir(parents=True)
    assert workspace.find_workspace(nested) == tmp_path.resolve()
    assert workspace.find_workspace(tmp_path.parent) is None
