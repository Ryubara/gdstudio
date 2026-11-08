"""`gds workspace init`: build the GDStudio workspace on any machine (docs/workspace.md#bootstrap).

It creates the workspace folders, clones the kit and any registered repositories, downloads the pinned tools,
writes `gdstudio.local.toml` (the tool paths every script reads) and checks the prerequisites. Each step is skipped
when its result is already there, so running it again is safe; `--dry-run` prints the steps without doing them.
"""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

from gds_tools import fetch, integrations
from gds_tools.manifest import ManifestError, Tool, load_mcp, load_tools, load_workspace, platform_key, resolve_fetch

#: A file at the workspace root that marks it, so every tool finds the workspace from any folder inside it.
MARKER = ".gdstudio-workspace"
LOCAL_FILE = "gdstudio.local.toml"
KIT = "gdstudio"


class WorkspaceError(Exception):
    """The workspace cannot be found or set up."""


@dataclass(frozen=True)
class Check:
    """One prerequisite and whether this machine has it."""

    name: str
    ok: bool
    detail: str
    required: bool = True


def kit_checkout() -> Path | None:
    """The gdstudio checkout this code runs from, or None when it runs from an installed copy (uvx)."""
    root = Path(__file__).resolve().parents[3]
    return root if (root / "tools.toml").exists() and (root / "workspace.toml").exists() else None


def find_workspace(start: Path) -> Path | None:
    """The workspace holding `start`: the nearest folder upwards with the marker file."""
    for folder in (start.resolve(), *start.resolve().parents):
        if (folder / MARKER).exists():
            return folder
    return None


def require_workspace(start: Path | None = None) -> Path:
    """The workspace around `start` (default: the current folder); WorkspaceError outside one."""
    found = find_workspace(start or Path.cwd())
    if found is None:
        raise WorkspaceError("not inside a GDStudio workspace; run the bootstrap script (docs/workspace.md)")
    return found


def default_root(cwd: Path) -> Path:
    """The workspace to set up when none is named: the one around a kit checkout, else `cwd`."""
    kit = kit_checkout()
    if kit is not None and kit.parent.name == "repos":
        return kit.parent.parent
    return find_workspace(cwd) or cwd


def run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    """Run a command, capturing its output as text."""
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, check=False)


def check_prerequisites() -> list[Check]:
    """Git, Git LFS and uv: what every workspace needs."""
    checks: list[Check] = []
    git = shutil.which("git")
    checks.append(Check("git", git is not None, run(["git", "--version"]).stdout.strip() if git else "not on PATH"))
    if git:
        lfs = run(["git", "lfs", "version"])
        checks.append(Check("git-lfs", lfs.returncode == 0, lfs.stdout.strip() or "install Git LFS (git-lfs.com)"))
    uv = shutil.which("uv")
    checks.append(Check("uv", uv is not None, run(["uv", "--version"]).stdout.strip() if uv else "not on PATH"))
    return checks


def check_services(root: Path) -> list[Check]:
    """What agents need besides the tools, as warnings: a signed-in `gh` (every `gds issue` and `gds pr` command asks
    GitHub), the Railway CLI when a game deploys (it has a `deploy/` folder), and the pinned Godot's export templates
    when a game exports (it has `game/export_presets.cfg`). A bootstrap cannot sign in for anyone, so none is required.
    """
    checks: list[Check] = []
    gh = shutil.which("gh")
    if gh is None:
        checks.append(
            Check("gh", False, "not on PATH: install the GitHub CLI (cli.github.com), then `gh auth login`", False)
        )
    else:
        signed_in = run([gh, "auth", "status"]).returncode == 0
        detail = "signed in" if signed_in else "not signed in: run `gh auth login` (gds issue and gds pr need it)"
        checks.append(Check("gh", signed_in, detail, False))
    repos = root / "repos"
    games = sorted(p for p in repos.iterdir() if (p / "game" / "project.godot").is_file()) if repos.is_dir() else []
    deploying = [g.name for g in games if (g / "deploy").is_dir()]
    if deploying:
        railway = shutil.which("railway")
        if railway is None:
            names = ", ".join(deploying)
            detail = f"not on PATH, and {names} deploys: install it (docs.railway.com/cli), then `railway login`"
            checks.append(Check("railway", False, detail, False))
        else:
            signed_in = run([railway, "whoami"]).returncode == 0
            detail = "signed in" if signed_in else "not signed in: run `railway login`"
            checks.append(Check("railway", signed_in, detail, False))
    exporting = [g.name for g in games if (g / "game" / "export_presets.cfg").is_file()]
    if exporting:
        try:
            godot: Path | None = tool_path("godot", root)
        except WorkspaceError:
            godot = None  # the tool check already reports a missing Godot
        if godot is not None:
            installed = any((godot.parent / "editor_data" / "export_templates").glob("*.stable"))
            detail = (
                "installed"
                if installed
                else f"missing, and {', '.join(exporting)} exports: `gds workspace init --fetch godot-templates` (1 GB)"
            )
            checks.append(Check("godot export templates", installed, detail, False))
    return checks


def write_local_config(root: Path, tools: dict[str, Tool], key: str) -> Path:
    """Write gdstudio.local.toml with the path of every installed tool's program; returns its path."""
    lines = [
        "# Written by `gds workspace init`; machine-specific, never committed. Rerun init to refresh it.",
        f'platform = "{key}"',
        "",
        "[tools]",
    ]
    for tool in tools.values():
        item = tool.platforms.get(key)
        if item is None or not item.exe:
            continue
        exe = root / "tools" / tool.folder / item.exe
        if exe.exists():
            lines.append(f"{tool.name.replace('-', '_')} = {_toml_string(exe.as_posix())}")
    path = root / LOCAL_FILE
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def _toml_string(value: str) -> str:
    """A TOML basic string."""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def tool_path(name: str, root: Path | None = None) -> Path:
    """The program of an installed pinned tool; WorkspaceError when it is not installed."""
    import tomllib

    root = root or require_workspace()
    local = root / LOCAL_FILE
    if not local.exists():
        raise WorkspaceError(f"{local} is missing; run `gds workspace init`")
    data = tomllib.loads(local.read_text(encoding="utf-8")).get("tools", {})
    value = data.get(name.replace("-", "_"))
    if not value or not Path(value).exists():
        raise WorkspaceError(f"{name} is not installed; run `gds workspace init --fetch {name}`")
    return Path(value)


def init(
    root: Path,
    fetch_names: list[str] | None,
    clone: bool,
    dry_run: bool,
    log=print,
    mcp: bool = True,
) -> int:
    """Set up the workspace at `root`; returns a process exit code."""
    root = root.resolve()
    log(f"workspace: {root}{'  (dry run)' if dry_run else ''}")

    # The kit's manifests: from this checkout, else from the workspace's clone of the kit (cloned first if needed).
    kit = kit_checkout() or root / "repos" / KIT
    if not (kit / "workspace.toml").exists():
        raise WorkspaceError(f"no gdstudio checkout at {kit}; run the bootstrap from a clone of the kit")
    spec = load_workspace(kit / "workspace.toml")
    tools = load_tools(kit / "tools.toml")

    for folder in spec.folders:
        path = root / folder
        if not path.exists():
            log(f"create  {folder}/")
            if not dry_run:
                path.mkdir(parents=True)
    if not (root / MARKER).exists():
        log(f"create  {MARKER}")
        if not dry_run:
            (root / MARKER).write_text("GDStudio workspace root (docs/workspace.md)\n", encoding="utf-8")

    failures = 0
    if clone:
        for repo in spec.repos.values():
            target = root / "repos" / repo.name
            if target.exists():
                continue
            log(f"clone   {repo.url} -> repos/{repo.name}")
            if not dry_run:
                result = run(["git", "clone", repo.url, str(target)])
                if result.returncode != 0:
                    log(f"  FAILED: {result.stderr.strip()}")
                    failures += 1

    key = platform_key()
    for tool in resolve_fetch(tools, fetch_names):
        try:
            item = tool.download_for(key)
        except ManifestError as error:
            log(f"skip    {tool.folder}: {error}")
            continue
        if fetch.is_installed(root / "tools", tool, item):
            log(f"ok      tools/{tool.folder}")
            continue
        log(f"fetch   {tool.folder}")
        if dry_run:
            continue
        try:
            archive = fetch.download(item, root / "cache" / "downloads", log)
            log(f"  verified {item.algorithm}; unpacking")
            fetch.install(tool, item, archive, root / "tools", tools)
        except (fetch.FetchError, ManifestError, OSError, subprocess.CalledProcessError) as error:
            log(f"  FAILED: {error}")
            failures += 1

    if not dry_run:
        log(f"write   {write_local_config(root, tools, key).name}")
        addons = [t for t in tools.values() if t.kind == "godot-addon" and (root / "tools" / t.folder).exists()]
        for project in integrations.game_projects(root / "repos"):
            for tool in addons:
                integrations.install_godot_addon(
                    root / "tools" / tool.folder, tool.extra["addon"], tool.extra["source"], project, log
                )
        if mcp:
            folders = {t.name: t.folder for t in tools.values()}
            servers = {
                n: integrations.resolve_command(c, root / "tools", folders)
                for n, c in load_mcp(kit / "tools.toml").items()
            }
            checkouts = sorted(p for p in (root / "repos").iterdir() if (p / ".git").exists())
            integrations.register_mcp(checkouts, servers, log)

    log("prerequisites:")
    for check in check_prerequisites():
        log(f"  {'ok  ' if check.ok else 'MISSING'} {check.name}: {check.detail}")
        if check.required and not check.ok:
            failures += 1
    log("done" if not failures else f"finished with {failures} problem(s)")
    return 0 if not failures else 1
