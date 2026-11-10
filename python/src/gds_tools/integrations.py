"""What `gds workspace init` sets up around the checkouts (docs/studio/workspace.md#integrations).

- The pinned Godot addons (the MCP addon, GdUnit4) go into every game's `game/addons/<name>/`, and into the kit's own
  Godot project (`godot/`, where `gds_ui` is edited and tested), excluded in the checkout's `.git/info/exclude`. Their
  editor plugins are appended to the `[editor_plugins]` list of the real `project.godot`, since the Godot 4.7 editor
  ignores `override.cfg` altogether (`ProjectSettings::setup` skips it in the editor; #1005), and a local git filter
  (`local_plugins.sh`, named in `.git/info/attributes` and `.git/config`) drops them on the way into git and adds them
  back on checkout: no commit, diff or `git status` names them, so third-party code and its enablement never enter a
  public repository, yet every machine gets them.
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
#: The local git filter that keeps the local-only plugins out of project.godot's commits, and its script's file name
#: (beside this module, copied into the checkout's git folder).
FILTER = "gds-local-plugins"
FILTER_SCRIPT = "local_plugins.sh"
#: project.godot's `enabled=PackedStringArray(...)` line; group 1 is what is between the brackets.
PLUGIN_LIST = re.compile(r"^enabled=PackedStringArray\((.*)\)\r?$", re.MULTILINE)

Run = Callable[[list[str], Path], subprocess.CompletedProcess[str]]
Log = Callable[[str], None]


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    """Run a command in `cwd`, capturing its output."""
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False)


#: The folder of a checkout that holds its Godot project: `game/` in a game, `godot/` in the kit (the addons' project).
PROJECT_FOLDERS = ("game", "godot")


def game_projects(repos: Path) -> list[Path]:
    """The Godot projects of the workspace: `repos/<name>/game/` (a game) or `repos/<name>/godot/` (the kit), and the
    same in every worktree `worktrees/<name>/<branch>/` (agents work there, and the untracked addons are not in a
    fresh worktree)."""
    worktrees = repos.parent / "worktrees"
    found = []
    for folder in PROJECT_FOLDERS:
        found += [*repos.glob(f"*/{folder}/project.godot"), *worktrees.glob(f"*/*/{folder}/project.godot")]
    return sorted(p.parent for p in found)


def install_godot_addon(tool_dir: Path, addon: str, source: str, project: Path, log: Log) -> bool:
    """Copy one pinned addon into a game, enable it in its project.godot and keep both out of git; True when something
    changed. `source` is the addon folder's path inside the unpacked archive."""
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
    plugin = f"res://addons/{addon}/plugin.cfg"
    common = git_common_dir(project.parent)
    if common is not None:
        changed |= _exclude(common, f"/{project.name}/addons/{addon}/")
        changed |= keep_out_of_commits(common, project.name, addon)
    changed |= retire_override(project / "override.cfg", plugin)
    if enable_plugin(project / "project.godot", plugin):
        changed = True
        refresh_index(project.parent, f"{project.name}/project.godot")
    elif plugin not in _plugin_list(project / "project.godot"):
        log(f"  skip enabling {addon}: {project.name}/project.godot has no [editor_plugins] list to join")
    if changed:
        log(f"godot   {addon} in {project.parent.name}/{project.name} (untracked)")
    return changed


def git_common_dir(checkout: Path) -> Path | None:
    """The git folder a checkout shares with its worktrees (its `info/` and `config`), or None outside git."""
    dot = checkout / ".git"
    if dot.is_dir():
        return dot
    if not dot.is_file():
        return None
    text = dot.read_text(encoding="utf-8").strip()
    if not text.startswith("gitdir:"):
        return None
    gitdir = (checkout / text.removeprefix("gitdir:").strip()).resolve()
    common = gitdir / "commondir"
    return (gitdir / common.read_text(encoding="utf-8").strip()).resolve() if common.exists() else gitdir


def _exclude(common: Path, entry: str) -> bool:
    """Add `entry` to the checkout's `info/exclude`; True when the file changed."""
    exclude = common / "info" / "exclude"
    lines = exclude.read_text(encoding="utf-8").splitlines() if exclude.exists() else []
    if entry in lines:
        return False
    exclude.parent.mkdir(parents=True, exist_ok=True)
    note = [EXCLUDE_NOTE] if EXCLUDE_NOTE not in lines else []
    exclude.write_text("\n".join([*lines, *note, entry]) + "\n", encoding="utf-8")
    return True


def keep_out_of_commits(common: Path, project: str, addon: str) -> bool:
    """Set up the local `gds-local-plugins` git filter (local_plugins.sh) on `<project>/project.godot`, naming `addon`
    among the plugins it strips on the way in and adds back on the way out; True when something changed. Everything
    lives in the git folder (`info/attributes`, `config`), so nothing of it is committed."""
    changed = False
    script = common / FILTER_SCRIPT
    body = (Path(__file__).parent / FILTER_SCRIPT).read_text(encoding="utf-8")
    if not script.exists() or script.read_text(encoding="utf-8") != body:
        script.write_text(body, encoding="utf-8", newline="\n")
        changed = True
    attributes = common / "info" / "attributes"
    lines = attributes.read_text(encoding="utf-8").splitlines() if attributes.exists() else []
    line = f"/{project}/project.godot filter={FILTER}"
    if line not in lines:
        attributes.parent.mkdir(parents=True, exist_ok=True)
        note = [EXCLUDE_NOTE] if EXCLUDE_NOTE not in lines else []
        attributes.write_text("\n".join([*lines, *note, line]) + "\n", encoding="utf-8")
        changed = True
    config = ["git", "config", "--file", str(common / "config")]
    current = subprocess.run([*config, "--get", f"filter.{FILTER}.clean"], capture_output=True, text=True, check=False)
    addons = current.stdout.strip().split(" %f ", 1)[1].split() if " %f " in current.stdout else []
    if addon in addons and f'"{script.as_posix()}"' in current.stdout:
        return changed
    addons = [a for a in addons if a != addon] + [addon]
    for mode in ("clean", "smudge"):
        command = f'sh "{script.as_posix()}" {mode} %f {" ".join(addons)}'
        subprocess.run([*config, f"filter.{FILTER}.{mode}", command], check=True, capture_output=True)
    return True


def refresh_index(checkout: Path, path: str) -> None:
    """Record a filtered file's new size in the checkout's index when only filtered lines changed. Git takes a file
    whose size differs from the index for modified without running the clean filter (`git diff` is empty, `git status`
    still says `M`), so after the plugins are appended the unchanged blob is added again; a file with a real change of
    its own is left alone (adding it would stage that change)."""

    def git(*args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["git", *args], cwd=checkout, capture_output=True, text=True, check=False)

    filtered, staged = git("hash-object", f"--path={path}", "--", path), git("rev-parse", f":{path}")
    if filtered.returncode == 0 and staged.returncode == 0 and filtered.stdout.strip() == staged.stdout.strip():
        git("add", "--", path)


def _plugin_list(project_file: Path) -> list[str]:
    """The plugins of project.godot's `[editor_plugins] enabled=` line, in order ([] when it has none)."""
    text = project_file.read_bytes().decode("utf-8") if project_file.exists() else ""
    found = PLUGIN_LIST.search(text)
    return re.findall(r'"([^"]+)"', found.group(1)) if found else []


def enable_plugin(project_file: Path, plugin: str) -> bool:
    """Append `plugin` to project.godot's `[editor_plugins] enabled=` list, as the smudge filter does; True when the
    file changed. A project with no list (or an empty one) is left alone: the filter could not take a section of its own
    back out, and every GDStudio game and the kit's `godot/` commit one (gds_ui)."""
    text = project_file.read_bytes().decode("utf-8") if project_file.exists() else ""
    found = PLUGIN_LIST.search(text)
    if found is None or '"' not in found.group(1) or f'"{plugin}"' in found.group(1):
        return False
    text = text[: found.end(1)] + f', "{plugin}"' + text[found.end(1) :]
    project_file.write_bytes(text.encode("utf-8"))
    return True


def retire_override(override: Path, plugin: str) -> bool:
    """Take `plugin` out of the untracked override.cfg the kit used to write (the 4.7 editor never read it, #1005),
    deleting the file once nothing else is left in it; True when the file changed."""
    if not override.exists():
        return False
    text = override.read_text(encoding="utf-8")
    entry = f'"{plugin}"'
    new = text.replace(f", {entry}", "").replace(f"{entry}, ", "").replace(entry, "")
    if new == text:
        return False
    if re.fullmatch(r"\s*\[editor_plugins\]\s*enabled=PackedStringArray\(\)\s*", new):
        override.unlink()
    else:
        override.write_text(new, encoding="utf-8")
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
