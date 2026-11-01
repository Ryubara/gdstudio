"""What `gds workspace init` sets up around the checkouts (docs/workspace.md#integrations).

- The Godot MCP addon goes into every game's `game/addons/godot_mcp/`, enabled through an untracked
  `game/override.cfg` and excluded in the checkout's `.git/info/exclude`: third-party code never enters a public game
  repository, yet every machine gets it.
- The MCP servers of tools.toml's [mcp] table are registered with Claude Code for every checkout
  (`claude mcp add -s local`), unless Claude Code is missing or the server is registered already.
"""

from __future__ import annotations

import shutil
import subprocess
from collections.abc import Callable
from pathlib import Path

ADDON = "godot_mcp"
OVERRIDE_LINE = 'enabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")'
EXCLUDES = ("/game/addons/godot_mcp/", "/game/override.cfg")

Run = Callable[[list[str], Path], subprocess.CompletedProcess[str]]
Log = Callable[[str], None]


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    """Run a command in `cwd`, capturing its output."""
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False)


def game_projects(repos: Path) -> list[Path]:
    """The Godot projects of the workspace's games: `repos/<name>/game/project.godot`."""
    return sorted(p.parent for p in repos.glob("*/game/project.godot"))


def install_godot_addon(addon_tool_dir: Path, project: Path, log: Log) -> bool:
    """Copy the Godot MCP addon into one game, enable it locally and keep it out of git; True when changed."""
    source = addon_tool_dir / "addons" / ADDON
    if not source.exists():
        return False
    target = project / "addons" / ADDON
    stamp = (
        (addon_tool_dir / ".gds-installed").read_text(encoding="utf-8")
        if (addon_tool_dir / ".gds-installed").exists()
        else ""
    )
    marker = target / ".gds-installed"
    changed = False
    if not marker.exists() or marker.read_text(encoding="utf-8") != stamp:
        shutil.rmtree(target, ignore_errors=True)
        shutil.copytree(source, target)
        marker.write_text(stamp, encoding="utf-8")
        changed = True
    override = project / "override.cfg"
    text = override.read_text(encoding="utf-8") if override.exists() else ""
    if OVERRIDE_LINE not in text:
        override.write_text(
            text + ("\n" if text and not text.endswith("\n") else "") + f"[editor_plugins]\n\n{OVERRIDE_LINE}\n",
            encoding="utf-8",
        )
        changed = True
    exclude = project.parent / ".git" / "info" / "exclude"
    if exclude.parent.exists():
        lines = exclude.read_text(encoding="utf-8").splitlines() if exclude.exists() else []
        missing = [e for e in EXCLUDES if e not in lines]
        if missing:
            exclude.write_text(
                "\n".join([*lines, "# gds workspace init: local-only Godot MCP addon", *missing]) + "\n",
                encoding="utf-8",
            )
            changed = True
    if changed:
        log(f"godot   MCP addon in {project.parent.name}/game (untracked)")
    return changed


def resolve_command(command: list[str], tools_root: Path, folders: dict[str, str]) -> list[str]:
    """MCP command words with `{tool:<name>}` replaced by that tool's install folder."""
    out = []
    for word in command:
        for name, folder in folders.items():
            word = word.replace(f"{{tool:{name}}}", (tools_root / folder).as_posix())
        out.append(word)
    return out


def register_mcp(checkouts: list[Path], servers: dict[str, list[str]], log: Log, runner: Run = run) -> int:
    """Register each MCP server for each checkout unless it is there; returns how many were added."""
    if shutil.which("claude") is None:
        log("skip    MCP registration: Claude Code (`claude`) is not on PATH")
        return 0
    added = 0
    for checkout in checkouts:
        for name, command in servers.items():
            if runner(["claude", "mcp", "get", name], checkout).returncode == 0:
                continue
            result = runner(["claude", "mcp", "add", "-s", "local", name, "--", *command], checkout)
            if result.returncode == 0:
                log(f"mcp     {name} for {checkout.name}")
                added += 1
            else:
                log(f"  FAILED mcp {name} for {checkout.name}: {result.stderr.strip()}")
    return added
