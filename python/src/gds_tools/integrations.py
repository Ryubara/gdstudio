"""What `gds workspace init` sets up around the checkouts (docs/workspace.md#integrations).

- The Godot MCP addon goes into every game's `game/addons/godot_mcp/`, enabled through an untracked
  `game/override.cfg` and excluded in the checkout's `.git/info/exclude`: third-party code never enters a public game
  repository, yet every machine gets it.
- The MCP servers of tools.toml's [mcp] table are registered with Claude Code for every checkout
  (`claude mcp add -s local`), unless Claude Code is missing or the server is registered already.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from collections.abc import Callable
from pathlib import Path

EXCLUDE_NOTE = "# gds workspace init: local-only Godot addons"

Run = Callable[[list[str], Path], subprocess.CompletedProcess[str]]
Log = Callable[[str], None]


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    """Run a command in `cwd`, capturing its output."""
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False)


def game_projects(repos: Path) -> list[Path]:
    """The Godot projects of the workspace's games: `repos/<name>/game/` and every worktree's
    `worktrees/<name>/<branch>/game/` (agents work there, and the untracked addons are not in a fresh worktree)."""
    worktrees = repos.parent / "worktrees"
    found = [*repos.glob("*/game/project.godot"), *worktrees.glob("*/*/game/project.godot")]
    return sorted(p.parent for p in found)


def install_godot_addon(tool_dir: Path, addon: str, source: str, project: Path, log: Log) -> bool:
    """Copy one pinned addon into a game, enable it in the untracked override.cfg and keep it out of git; True when
    something changed. `source` is the addon folder's path inside the unpacked archive."""
    src = tool_dir / source
    if not src.exists():
        return False
    target = project / "addons" / addon
    stamp_file = tool_dir / ".gds-installed"
    stamp = stamp_file.read_text(encoding="utf-8") if stamp_file.exists() else ""
    marker = target / ".gds-installed"
    changed = False
    if not marker.exists() or marker.read_text(encoding="utf-8") != stamp:
        shutil.rmtree(target, ignore_errors=True)
        shutil.copytree(src, target)
        marker.write_text(stamp, encoding="utf-8")
        changed = True
    if enable_plugin(project / "override.cfg", f"res://addons/{addon}/plugin.cfg"):
        changed = True
    exclude = project.parent / ".git" / "info" / "exclude"  # a worktree's .git is a file: its repo's exclude applies
    if exclude.parent.exists():
        lines = exclude.read_text(encoding="utf-8").splitlines() if exclude.exists() else []
        missing = [e for e in (f"/game/addons/{addon}/", "/game/override.cfg") if e not in lines]
        if missing:
            note = [EXCLUDE_NOTE] if EXCLUDE_NOTE not in lines else []
            exclude.write_text("\n".join([*lines, *note, *missing]) + "\n", encoding="utf-8")
            changed = True
    if changed:
        log(f"godot   {addon} in {project.parent.name}/game (untracked)")
    return changed


def enable_plugin(override: Path, plugin: str) -> bool:
    """List `plugin` in override.cfg's [editor_plugins] enabled array; True when the file changed."""
    text = override.read_text(encoding="utf-8") if override.exists() else ""
    found = re.search(r"^enabled=PackedStringArray\((.*)\)$", text, re.MULTILINE)
    entries = re.findall(r'"([^"]+)"', found.group(1)) if found else []
    if plugin in entries:
        return False
    line = "enabled=PackedStringArray(" + ", ".join(f'"{e}"' for e in [*entries, plugin]) + ")"
    if found:
        text = text[: found.start()] + line + text[found.end() :]
    else:
        text = (text.rstrip("\n") + "\n\n" if text.strip() else "") + f"[editor_plugins]\n\n{line}\n"
    override.write_text(text, encoding="utf-8")
    return True


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
