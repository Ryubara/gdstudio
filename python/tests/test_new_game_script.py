"""templates/new-game.sh: the double-click that makes a game from a template (docs/engines/godot/new-game.md)."""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

KIT = Path(__file__).resolve().parents[2]
SCRIPT = KIT / "templates" / "new-game.sh"

FAKE_UV = """#!/usr/bin/env bash
# Stands in for `uv run ... gds ...`: records the gds arguments and answers --list.
args=("$@")
while [ "${#args[@]}" -gt 0 ] && [ "${args[0]}" != "gds" ]; do args=("${args[@]:1}"); done
printf '%s\\n' "${args[*]:1}" >> "$GDS_LOG"
if [ "${args[*]:1}" = "new game --list" ]; then
  echo "3d-blank             A floor and walls."
  echo "3d-third-person      A character on 3D Blank."
fi
exit 0
"""


def _bash() -> str:
    found = shutil.which("bash")
    assert found, "bash is needed to run templates/new-game.sh"
    return found


def _workspace(tmp_path: Path) -> tuple[Path, Path, Path]:
    workspace = tmp_path / "ws"
    kit = workspace / "repos" / "gdstudio"
    (kit / "templates").mkdir(parents=True)
    (kit / "python").mkdir()
    (workspace / ".gdstudio-workspace").write_text("", encoding="utf-8")
    shutil.copy(SCRIPT, kit / "templates" / "new-game.sh")
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    uv = bin_dir / "uv"
    uv.write_text(FAKE_UV, encoding="utf-8", newline="\n")
    uv.chmod(0o755)
    return workspace, kit, bin_dir


def _run(tmp_path: Path, answers: str) -> tuple[subprocess.CompletedProcess[str], list[str], Path]:
    workspace, kit, bin_dir = _workspace(tmp_path)
    log = tmp_path / "gds.log"
    env = dict(os.environ, GDS_LOG=str(log), PATH=f"{bin_dir}{os.pathsep}{os.environ['PATH']}")
    script = (kit / "templates" / "new-game.sh").as_posix()
    done = subprocess.run(
        [_bash(), script], input=answers, text=True, capture_output=True, env=env, timeout=60, check=False
    )
    calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
    return done, calls, workspace


def test_the_script_is_lf_and_the_windows_wrapper_runs_it():
    assert b"\r\n" not in SCRIPT.read_bytes()
    wrapper = (KIT / "templates" / "new-game.cmd").read_text(encoding="utf-8")
    assert "new-game.sh" in wrapper
    assert "Git" in wrapper


def test_it_asks_and_makes_the_game_locally(tmp_path):
    done, calls, _ = _run(tmp_path, "2\nmy-game\nn\n\n")
    assert done.returncode == 0, done.stdout + done.stderr
    assert calls == ["new game --list", "new game my-game --template 3d-third-person --local"]


def test_it_refuses_a_bad_number_a_bad_name_and_an_existing_folder(tmp_path):
    (tmp_path / "ws" / "repos" / "taken").mkdir(parents=True)
    done, calls, _ = _run(tmp_path, "9\n1\nBad_Name\ntaken\nok-name\nn\n\n")
    assert done.returncode == 0, done.stdout + done.stderr
    assert "Type a number from the list." in done.stdout
    assert "Use lowercase letters" in done.stdout
    assert "repos/taken already exists" in done.stdout
    assert calls[-1] == "new game ok-name --template 3d-blank --local"
