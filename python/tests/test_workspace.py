"""Workspace init end to end with downloads stubbed out, and workspace discovery."""

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


def test_dry_run_changes_nothing(tmp_path):
    workspace.init(tmp_path, None, clone=True, dry_run=True, log=lambda _: None)
    assert list(tmp_path.iterdir()) == []


def test_find_workspace_from_nested_folder(tmp_path):
    (tmp_path / workspace.MARKER).write_text("")
    nested = tmp_path / "worktrees" / "game" / "branch"
    nested.mkdir(parents=True)
    assert workspace.find_workspace(nested) == tmp_path.resolve()
    assert workspace.find_workspace(tmp_path.parent) is None
