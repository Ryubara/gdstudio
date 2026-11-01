"""`gds sync`: writing the kit's files into a game, the lock, and catching drift."""

import json

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
