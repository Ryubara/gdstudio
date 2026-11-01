"""The `gds` command: GDStudio's tooling for agents and people (docs/tools.md)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from gds_tools import refs, sync, workspace
from gds_tools.manifest import ManifestError, load_tools


def _cmd_init(args: argparse.Namespace) -> int:
    root = Path(args.workspace) if args.workspace else workspace.default_root(Path.cwd())
    fetch = None
    if args.fetch:
        fetch = [name.strip() for part in args.fetch for name in part.split(",") if name.strip()]
    return workspace.init(root, fetch, clone=not args.no_clone, dry_run=args.dry_run)


def _cmd_tool_path(args: argparse.Namespace) -> int:
    print(workspace.tool_path(args.name))
    return 0


def _cmd_tool_list(args: argparse.Namespace) -> int:
    kit = workspace.kit_checkout() or workspace.require_workspace() / "repos" / workspace.KIT
    for tool in load_tools(kit / "tools.toml").values():
        print(f"{tool.name:18} {tool.version:10} {'default' if tool.default else 'opt-in'}")
    return 0


def _cmd_refs_fetch(args: argparse.Namespace) -> int:
    folder = refs.fetch_link(args.url, workspace.require_workspace() / "refs")
    print(f"written: {folder}")
    return 0


def _cmd_sync(args: argparse.Namespace) -> int:
    kit = workspace.kit_checkout() or workspace.require_workspace() / "repos" / workspace.KIT
    game = Path(args.game).resolve()
    if args.check:
        problems = sync.drift(kit, game)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print("in sync with the kit" if not problems else f"{len(problems)} file(s) out of sync", file=sys.stderr)
        return 1 if problems else 0
    print(f"{sync.sync(kit, game)} file(s) changed in {game.name}")
    return 0


def _cmd_doctor(args: argparse.Namespace) -> int:
    root = workspace.require_workspace()
    print(f"workspace: {root}")
    bad = 0
    for check in workspace.check_prerequisites():
        print(f"  {'ok  ' if check.ok else 'MISSING'} {check.name}: {check.detail}")
        bad += not check.ok
    for name in ("godot", "blender"):
        try:
            print(f"  ok      {name}: {workspace.tool_path(name, root)}")
        except workspace.WorkspaceError as error:
            print(f"  MISSING {name}: {error}")
            bad += 1
    return 1 if bad else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="gds", description="GDStudio tooling")
    sub = parser.add_subparsers(dest="group", required=True)

    ws = sub.add_parser("workspace", help="set up and inspect the workspace").add_subparsers(dest="cmd", required=True)
    init = ws.add_parser("init", help="create folders, clone repositories, fetch pinned tools")
    init.add_argument("--workspace", help="the workspace folder (default: around this checkout, else here)")
    init.add_argument("--fetch", action="append", help="tools to fetch: names, 'all' or 'none' (default: defaults)")
    init.add_argument("--no-clone", action="store_true", help="do not clone missing repositories")
    init.add_argument("--dry-run", action="store_true", help="print the steps without doing them")
    init.set_defaults(func=_cmd_init)

    tools = sub.add_parser("tool", help="pinned tools").add_subparsers(dest="cmd", required=True)
    path = tools.add_parser("path", help="print the program of an installed tool")
    path.add_argument("name")
    path.set_defaults(func=_cmd_tool_path)
    tools.add_parser("list", help="list the pinned tools").set_defaults(func=_cmd_tool_list)

    ref = sub.add_parser("refs", help="third-party references in <workspace>/refs").add_subparsers(
        dest="cmd", required=True
    )
    fetch_ref = ref.add_parser("fetch", help="fetch a poly.pizza model or bundle with its licence metadata")
    fetch_ref.add_argument("url")
    fetch_ref.set_defaults(func=_cmd_refs_fetch)

    syn = sub.add_parser("sync", help="write the kit's agent definitions and hook launcher into a game")
    syn.add_argument("game", help="the game repository (a checkout or worktree)")
    syn.add_argument("--check", action="store_true", help="only report files that differ from the kit")
    syn.set_defaults(func=_cmd_sync)

    sub.add_parser("doctor", help="check the workspace and its tools").set_defaults(func=_cmd_doctor)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (workspace.WorkspaceError, ManifestError, refs.RefsError) as error:
        print(f"gds: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
