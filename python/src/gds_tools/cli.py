"""The `gds` command: GDStudio's tooling for agents and people (docs/tools.md)."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from gds_tools import capture, refs, workspace
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


def _cmd_capture_frames(args: argparse.Namespace) -> int:
    root = workspace.require_workspace()
    project = Path(args.project).resolve()
    out = capture.scratch_folder(project, root) / capture.safe_name(args.name)
    frames = capture.capture_frames(
        workspace.tool_path("godot", root), project, out, args.scene, args.seconds, args.fps
    )
    print(f"written: {len(frames)} frames in {out}")
    return 0


def _cmd_capture_sheet(args: argparse.Namespace) -> int:
    print(f"written: {capture.contact_sheet(Path(args.folder), args.every, args.columns)}")
    return 0


def _cmd_capture_clip(args: argparse.Namespace) -> int:
    ffmpeg = workspace.tool_path("ffmpeg")
    print(f"written: {capture.encode_clip(ffmpeg, Path(args.folder).resolve(), gif=args.gif)}")
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

    cap = sub.add_parser("capture", help="frames, contact sheets and clips as proof").add_subparsers(
        dest="cmd", required=True
    )
    frames = cap.add_parser("frames", help="run a scene in Movie Maker and write its frames to scratch/")
    frames.add_argument("--project", required=True, help="the game's project folder (holds project.godot)")
    frames.add_argument("--scene", help="scene to run, e.g. res://main.tscn (default: the main scene)")
    frames.add_argument("--seconds", type=float, default=5, help="length of the capture (default: 5)")
    frames.add_argument("--fps", type=int, default=capture.DEFAULT_FPS, help="frames per second (default: 10)")
    frames.add_argument("--name", default="capture", help="folder name under scratch/<repo>/<branch>/")
    frames.set_defaults(func=_cmd_capture_frames)
    sheet = cap.add_parser("sheet", help="tile a folder's frames into one labelled contact sheet PNG")
    sheet.add_argument("folder")
    sheet.add_argument("--every", type=int, default=1, help="use every K-th frame (default: 1)")
    sheet.add_argument("--columns", type=int, default=4, help="tiles per row (default: 4)")
    sheet.set_defaults(func=_cmd_capture_sheet)
    clip = cap.add_parser("clip", help="encode a folder's frames to an MP4 (or GIF) small enough for GitHub")
    clip.add_argument("folder")
    clip.add_argument("--gif", action="store_true", help="make a GIF instead of an MP4")
    clip.set_defaults(func=_cmd_capture_clip)

    sub.add_parser("doctor", help="check the workspace and its tools").set_defaults(func=_cmd_doctor)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (workspace.WorkspaceError, ManifestError, refs.RefsError, capture.CaptureError) as error:
        print(f"gds: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
