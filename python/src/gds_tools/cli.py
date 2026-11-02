"""The `gds` command: GDStudio's tooling for agents and people (docs/tools.md)."""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from collections.abc import Callable
from pathlib import Path

from gds_tools import capture, issues, lessons, refs, sync, workspace, worktrees
from gds_tools.manifest import ManifestError, load_tools
from gds_tools.quiet_run import run_quiet


def _cmd_init(args: argparse.Namespace) -> int:
    root = Path(args.workspace) if args.workspace else workspace.default_root(Path.cwd())
    fetch = None
    if args.fetch:
        fetch = [name.strip() for part in args.fetch for name in part.split(",") if name.strip()]
    return workspace.init(root, fetch, clone=not args.no_clone, dry_run=args.dry_run, mcp=not args.no_mcp)


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


GODOT_TIMEOUT = capture.GODOT_TIMEOUT


QUIET_TIMEOUT = GODOT_TIMEOUT


def split_godot_args(argv: list[str]) -> tuple[float, list[str]]:
    """`gds godot [--timeout SECONDS] [--] <godot arguments>`: the timeout and the arguments that go to Godot.

    Done by hand because argparse rejects Godot's own options (`--path`, `--headless`) in front of a positional.
    """
    return split_quiet_args(argv, GODOT_TIMEOUT)


def split_quiet_args(argv: list[str], default_timeout: float = QUIET_TIMEOUT) -> tuple[float, list[str]]:
    """`[--timeout SECONDS] [--] <the rest>`: the timeout and the rest, untouched (the rest is another program's)."""
    rest = list(argv)
    timeout = float(default_timeout)
    if rest[:1] == ["--timeout"]:
        if len(rest) < 2:
            raise workspace.WorkspaceError("--timeout needs a number of seconds")
        try:
            timeout = float(rest[1])
        except ValueError:
            raise workspace.WorkspaceError(f"--timeout needs a number of seconds, not {rest[1]!r}") from None
        rest = rest[2:]
    if rest[:1] == ["--"]:
        rest = rest[1:]
    return timeout, rest


WITH_AUDIO = "--with-audio"  # a `gds godot` option, never passed on: leave Godot's audio driver alone
AUDIO_DRIVER = "--audio-driver"  # Godot's own option; its value `Dummy` is the driver that plays nothing


def parse_godot_args(argv: list[str]) -> tuple[float, bool, list[str]]:
    """`gds godot [--timeout S] [--with-audio] [--] <godot arguments>` (the two options in either order): the timeout,
    whether the sound is wanted, and the arguments that go to Godot."""
    with_audio = argv[:1] == [WITH_AUDIO]
    timeout, rest = split_godot_args(argv[1:] if with_audio else argv)
    if rest[:1] == [WITH_AUDIO]:
        with_audio, rest = True, rest[1:]
        if rest[:1] == ["--"]:
            rest = rest[1:]
    return timeout, with_audio, rest


def mute_godot(args: list[str], with_audio: bool = False) -> list[str]:
    """`args` for Godot with `--audio-driver Dummy` in front unless the audio is wanted: `--with-audio` was given, or
    the arguments already pick a driver (`--audio-driver WASAPI`, `--audio-driver=Dummy`). Agents never listen: the
    audio checks read the mixer, which the Dummy driver still runs (docs/godot/no-focus.md#sound)."""
    if with_audio or any(a == AUDIO_DRIVER or a.startswith(f"{AUDIO_DRIVER}=") for a in args):
        return args
    return [AUDIO_DRIVER, "Dummy", *args]


def run_godot_command(argv: list[str]) -> int:
    """Run the pinned Godot with `argv` on a private desktop, without taking the focus and without sound
    (docs/godot/no-focus.md); `--with-audio` keeps the sound."""
    timeout, with_audio, rest = parse_godot_args(argv)
    root = workspace.require_workspace()
    godot = workspace.tool_path("godot", root)
    return _stream_quiet([str(godot), *mute_godot(rest, with_audio)], timeout, "godot")


def run_quiet_command(argv: list[str]) -> int:
    """Run any command (and every program it starts) on the private desktop with the cursor kept free: a browser
    probe under pointer lock, a test runner, a script that starts Godot (docs/godot/no-focus.md)."""
    timeout, rest = split_quiet_args(argv)
    if not rest:
        raise workspace.WorkspaceError("usage: gds quiet [--timeout SECONDS] -- <command> [arguments]")
    return _stream_quiet(resolve_program(rest), timeout, rest[0])


def resolve_program(cmd: list[str]) -> list[str]:
    """`cmd` with its program found on PATH: CreateProcess runs only an .exe it is given by name, so a batch file
    (`npx.cmd`, `pnpm.cmd`) goes through `cmd /c`."""
    found = shutil.which(cmd[0])
    if not found:
        return cmd
    if found.lower().endswith((".cmd", ".bat")):
        return [os.environ.get("COMSPEC", "cmd.exe"), "/d", "/c", found, *cmd[1:]]
    return [found, *cmd[1:]]


def _stream_quiet(cmd: list[str], timeout: float, name: str) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    def show(text: str) -> None:
        sys.stdout.write(text)
        sys.stdout.flush()

    outcome = run_quiet(cmd, timeout=timeout, on_output=show)
    if outcome.timed_out:
        print(f"gds: {name} did not finish within {timeout:g} s and was stopped", file=sys.stderr)
        return 124
    return outcome.returncode


def _cmd_sync(args: argparse.Namespace) -> int:
    kit = workspace.kit_checkout() or workspace.require_workspace() / "repos" / workspace.KIT
    game = Path(args.game).resolve()
    if args.check:
        problems = sync.drift(kit, game)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        print("in sync with the kit" if not problems else f"{len(problems)} file(s) out of sync", file=sys.stderr)
        return 1 if problems else 0
    try:
        print(f"{sync.sync(kit, game)} file(s) changed in {game.name}")
    except sync.SyncError as error:
        print(f"gds: {error}", file=sys.stderr)
        return 1
    return 0


def _issue_context(args: argparse.Namespace) -> tuple[Path, issues.Settings, Path]:
    """The workspace, the issue settings for the repository (`--repo`, else the one around the current folder) and the
    ledger file."""
    root = workspace.require_workspace()
    kit = workspace.kit_checkout() or root / "repos" / workspace.KIT
    repo = getattr(args, "repo", None) or ""
    game = root / "repos" / repo.split("/")[-1] if repo else None
    settings = issues.load_settings(kit, game if game and game.is_dir() else None)
    if getattr(args, "window", None):
        settings = issues.Settings(window=args.window, ledger=settings.ledger)
    return root, settings, root / settings.ledger


def _issue_ref(args: argparse.Namespace) -> tuple[str, int]:
    """`owner/repo#N` of the command, with the current folder's repository for a bare `#N`."""
    try:
        return issues.parse_ref(args.ref)
    except issues.IssueError:
        return issues.parse_ref(args.ref, issues.default_repo(issues.run_gh))


def _prepare_worktree(root: Path, repo: str, branch: str) -> Callable[[issues.Issue], issues.Prepared]:
    """What `issues.start` runs once the window allows the start: the branch and worktree of the issue, with the git
    hooks of the repository verified (docs/starting-work.md#worktree)."""
    name = repo.split("/")[-1]
    checkout = root / "repos" / name

    def prepare(issue: issues.Issue) -> issues.Prepared:
        try:
            made = worktrees.create(checkout, root / "worktrees" / name, issue.title, issue.number, branch=branch)
        except worktrees.WorktreeError as error:
            raise issues.IssueError(f"{repo}#{issue.number} was not started: {error}") from error
        where = made.path.as_posix()
        return issues.Prepared(
            branch=made.branch,
            path=where,
            lines=[f"branch {made.branch} from origin {made.base[:10]}", f"worktree {where}", *made.hooks],
            undo=lambda: worktrees.remove(checkout, made.path, made.branch),
        )

    return prepare


def _cmd_issue_start(args: argparse.Namespace) -> int:
    repo, number = _issue_ref(args)
    args.repo = repo
    root, settings, ledger = _issue_context(args)
    kit = workspace.kit_checkout() or workspace.require_workspace() / "repos" / workspace.KIT
    areas = lessons.Areas.load(kit / lessons.AREAS_FILE) if (kit / lessons.AREAS_FILE).is_file() else None
    for line in issues.start(
        repo,
        number,
        args.agent,
        gh=issues.run_gh,
        ledger=ledger,
        size=settings.window,
        branch=args.branch or "",
        areas_for=areas.for_labels if areas else None,
        prepare=None if args.no_worktree else _prepare_worktree(root, repo, args.branch or ""),
    ):
        print(line)
    return 0


def _cmd_issue_list(args: argparse.Namespace) -> int:
    args.repo = args.repo or issues.default_repo(issues.run_gh)
    _, settings, ledger = _issue_context(args)
    print("\n".join(issues.list_issues(args.repo, gh=issues.run_gh, ledger=ledger, size=settings.window)))
    return 0


def _cmd_issue_release(args: argparse.Namespace) -> int:
    repo, number = _issue_ref(args)
    args.repo = repo
    _, _, ledger = _issue_context(args)
    print("\n".join(issues.release(repo, number, gh=issues.run_gh, ledger=ledger, agent=args.agent or "")))
    return 0


def _cmd_issue_done(args: argparse.Namespace) -> int:
    repo, number = _issue_ref(args)
    args.repo = repo
    _, _, ledger = _issue_context(args)
    print("\n".join(issues.done(repo, number, ledger=ledger)))
    return 0


def _cmd_merge_main(args: argparse.Namespace) -> int:
    path = Path(args.path).resolve() if args.path else Path.cwd()
    print("\n".join(worktrees.merge_main(path, co_author=args.co_author or "", resume=args.resume)))
    return 0


def _cmd_lessons(args: argparse.Namespace) -> int:
    """`gds lessons [area ...]`: the checks of the mistakes glossary for some areas, or the list of areas."""
    kit = workspace.kit_checkout() or workspace.require_workspace() / "repos" / workspace.KIT
    areas = lessons.Areas.load(kit / lessons.AREAS_FILE)
    if not args.areas:
        for name, description in areas.names.items():
            print(f"{name:10} {description}")
        return 0
    unknown = [a for a in args.areas if a not in areas.names]
    if unknown:
        raise workspace.WorkspaceError(f"unknown area {unknown[0]!r}; `gds lessons` lists them")
    print(lessons.checks_text(lessons.build(kit), args.areas, args.limit))
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
    init.add_argument("--no-mcp", action="store_true", help="do not register MCP servers with Claude Code")
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

    sub.add_parser(
        "godot",
        help="run the pinned Godot with no focus and no sound: gds godot [--timeout S] [--with-audio] [--] <args>",
    )
    sub.add_parser(
        "quiet",
        help="run any command (a browser probe, a script) on the private desktop with the cursor kept free: "
        "gds quiet [--timeout S] -- <command>",
    )

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

    syn = sub.add_parser(
        "sync", help="write the kit's agent definitions, checker, hook launcher and message-check hooks into a game"
    )
    syn.add_argument("game", help="the game repository (a checkout or worktree)")
    syn.add_argument("--check", action="store_true", help="only report files that differ from the kit")
    syn.set_defaults(func=_cmd_sync)

    iss = sub.add_parser("issue", help="start issues oldest first (docs/starting-work.md)").add_subparsers(
        dest="cmd", required=True
    )
    ref_help = "the issue, as owner/repo#N (#N or N for the repository of the current folder)"
    start = iss.add_parser("start", help="start an issue if it is in the window: label, assign, comment, ledger")
    start.add_argument("ref", help=ref_help)
    start.add_argument("--agent", required=True, help="the agent (or person) that takes it, for the comment and ledger")
    start.add_argument("--branch", help="the name of the branch to make (default: from the issue title)")
    start.add_argument("--no-worktree", action="store_true", help="do not make the branch and worktree (no code work)")
    start.add_argument("--window", type=int, help="override the window size for this call (default: hooks.toml)")
    start.set_defaults(func=_cmd_issue_start)
    lst = iss.add_parser("list", help="the window, the issues in progress with their owners, the blocked ones")
    lst.add_argument("repo", nargs="?", help="owner/repo (default: the repository of the current folder)")
    lst.add_argument("--window", type=int, help="override the window size for this call")
    lst.set_defaults(func=_cmd_issue_list)
    rel = iss.add_parser("release", help="put a stopped issue back in the line as S-ready-to-start")
    rel.add_argument("ref", help=ref_help)
    rel.add_argument("--agent", help="who stops, for the comment")
    rel.set_defaults(func=_cmd_issue_release)
    fin = iss.add_parser("done", help="clear an issue from the ledger (a merged Fixes pull request does it anyway)")
    fin.add_argument("ref", help=ref_help)
    fin.set_defaults(func=_cmd_issue_done)

    mrg = sub.add_parser("merge-main", help="merge origin/main into the branch of a worktree with a clean message")
    mrg.add_argument("--path", help="the worktree (default: the current folder)")
    mrg.add_argument("--co-author", help="<model name> <noreply address> (default: the newest trailer on the branch)")
    mrg.add_argument("--continue", dest="resume", action="store_true", help="commit the merge once conflicts are fixed")
    mrg.set_defaults(func=_cmd_merge_main)

    les = sub.add_parser("lessons", help="the checks of past mistakes by area (built from docs/lessons)")
    les.add_argument("areas", nargs="*", help="areas to print (default: list the areas)")
    les.add_argument("--limit", type=int, default=12, help="newest items per area (default: 12)")
    les.set_defaults(func=_cmd_lessons)

    sub.add_parser("doctor", help="check the workspace and its tools").set_defaults(func=_cmd_doctor)
    return parser


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    try:
        if argv[:1] == ["godot"]:
            return run_godot_command(argv[1:])
        if argv[:1] == ["quiet"]:
            return run_quiet_command(argv[1:])
        args = build_parser().parse_args(argv)
        return args.func(args)
    except (
        workspace.WorkspaceError,
        worktrees.WorktreeError,
        ManifestError,
        refs.RefsError,
        capture.CaptureError,
        issues.IssueError,
    ) as error:
        print(f"gds: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
