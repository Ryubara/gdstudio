"""The `gds` command: GDStudio's tooling for agents and people (docs/studio/index.md)."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from collections.abc import Callable
from datetime import datetime
from pathlib import Path

from gds_tools import (
    bench_web,
    brief,
    capture,
    disk,
    evals,
    integrations,
    issues,
    layout,
    lessons,
    new_game,
    new_game_github,
    pr,
    refs,
    scripts,
    sweep,
    sync,
    template_test,
    workspace,
    worktrees,
)
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
    out = capture.frames_folder(project, Path.cwd(), root, args.name, args.out)
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
    clip = capture.encode_clip(ffmpeg, Path(args.folder).resolve(), gif=args.gif, max_seconds=args.max_seconds)
    print(f"written: {clip}")
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
    audio checks read the mixer, which the Dummy driver still runs (docs/engines/godot/no-focus.md#sound)."""
    if with_audio or any(a == AUDIO_DRIVER or a.startswith(f"{AUDIO_DRIVER}=") for a in args):
        return args
    return [AUDIO_DRIVER, "Dummy", *args]


def run_godot_command(argv: list[str]) -> int:
    """Run the pinned Godot with `argv` on a private desktop, without taking the focus and without sound
    (docs/engines/godot/no-focus.md); `--with-audio` keeps the sound."""
    timeout, with_audio, rest = parse_godot_args(argv)
    root = workspace.require_workspace()
    godot = workspace.tool_path("godot", root)
    args = capture.tell_movie_end(mute_godot(rest, with_audio))
    return _stream_quiet([str(godot), *args], timeout, "godot")


def run_quiet_command(argv: list[str]) -> int:
    """Run any command (and every program it starts) on the private desktop with the cursor kept free: a browser
    probe under pointer lock, a test runner, a script that starts Godot (docs/engines/godot/no-focus.md)."""
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
    # The addon is copied, never enabled: say what the game's project.godot still needs (kit #814).
    if (game / sync.GAME_PROJECT / "project.godot").is_file():
        for problem in layout.addon_problems(game / sync.GAME_PROJECT):
            print(f"warning: {problem}", file=sys.stderr)
    return 0


def _cmd_new_game(args: argparse.Namespace) -> int:
    if args.list:
        kit = workspace.kit_checkout() or Path(__file__).resolve().parents[3]
        for name in new_game.available(kit):
            print(f"{name:<20} {new_game.load_template(kit, name).description}")
        return 0
    if not args.name or not args.template:
        raise new_game.NewGameError("give the game's name and --template (`gds new game --list` prints the templates)")
    if args.remote and not args.local:
        raise new_game.NewGameError("--remote records an existing repository and goes with --local")
    root = workspace.require_workspace(Path(args.workspace)) if args.workspace else workspace.require_workspace()
    kit = workspace.kit_checkout() or root / "repos" / workspace.KIT
    options = None
    if not args.local:
        options = new_game_github.Options(
            private=args.private,
            wait=not args.no_wait,
            wait_minutes=args.wait_minutes,
            co_author=args.co_author or "",
            kit_pr=not args.no_kit_pr,
        )
    made = new_game.new_game(
        kit,
        root,
        args.name,
        args.template,
        title=args.title,
        description=args.description,
        remote=args.remote,
        licence=args.licence,
        holder=args.copyright,
        options=options,
    )
    print(f"made {made.repo}")
    print(f"from {kit} ({workspace.describe_kit(kit)})")
    published = made.published
    if published:
        print(f"repository  {published.url.removesuffix('.git')}")
        for result in (published.ci, published.docs):
            if result:
                print(f"{result.workflow:<11} {result.conclusion or 'not finished'} {result.url}".rstrip())
        print(f"pages       {published.pages_url} ({'answers' if published.pages_live else 'not answering'})")
        if published.kit_pr:
            print(f"kit PR      {published.kit_pr}")
    print("left to do:" if made.todo else "nothing left to do")
    for step in made.todo:
        print(f"  - {step}")
    if published and options and options.wait and not published.green:
        print("gds: the first CI run or the Pages site is not green", file=sys.stderr)
        return 1
    return 0


def _template_context() -> tuple[Path, Path]:
    """The kit checkout `gds` runs from (the template files are read from it as they are on disk) and the real
    workspace, whose marker, local file and GdUnit4 folder a throwaway workspace copies."""
    root = workspace.require_workspace()
    return workspace.kit_checkout() or root / "repos" / workspace.KIT, root


def _cmd_template_test(args: argparse.Namespace) -> int:
    kit, root = _template_context()
    result = template_test.run_template_test(
        kit,
        root,
        args.name,
        suites=args.suite,
        keep=args.keep,
        fixed_fps=None if args.real_clock else args.fixed_fps,
        godot_args=template_test.split_args(args.godot_args),
        gdunit_args=template_test.split_args(args.gdunit_args),
        timeout=args.timeout,
    )
    return result.code


def _cmd_template_game(args: argparse.Namespace) -> int:
    kit, root = _template_context()
    # stdout is the game's path alone (a script reads it); the source line goes with the hints, to stderr
    game = template_test.make_game(kit, root, args.name, log=lambda line: print(line, file=sys.stderr, flush=True))
    print(game)
    print(f"remove it with `gds template clean {game}`", file=sys.stderr)
    return 0


def _cmd_template_bench_web(args: argparse.Namespace) -> int:
    kit, root = _template_context()
    return bench_web.run_bench_web(
        kit,
        root,
        args.name,
        args.scene,
        run=args.run,
        probe_args=template_test.split_args(args.probe_args),
        keep=args.keep,
    ).code


def _cmd_template_clean(args: argparse.Namespace) -> int:
    folder = template_test.throwaway_of(Path(args.path))
    if not template_test.remove_throwaway(folder):
        print(f"gds: could not remove {folder}; delete it by hand", file=sys.stderr)
        return 1
    print(f"removed {folder}")
    return 0


def _cmd_check_layout(args: argparse.Namespace) -> int:
    problems = layout.check(Path(args.project))
    for problem in problems:
        print(f"  {problem}", file=sys.stderr)
    print(
        "layout: ok" if not problems else f"layout: {len(problems)} problem(s)",
        file=sys.stderr if problems else sys.stdout,
    )
    return 1 if problems else 0


def _cmd_check_scripts(args: argparse.Namespace) -> int:
    root = workspace.require_workspace()
    kit = workspace.kit_checkout() or root / "repos" / workspace.KIT
    report = scripts.check(workspace.tool_path("godot", root), Path(args.project), kit)
    for path in report.failed:
        print(f"  {path}: does not parse", file=sys.stderr)
    for line in report.details:
        print(f"    {line}", file=sys.stderr)
    if report.ok:
        print(f"scripts: {report.parsed} parse")
        return 0
    print(f"scripts: {len(report.failed)} of {report.parsed} do not parse", file=sys.stderr)
    return 1


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


def _prepare_worktree(
    root: Path, repo: str, branch: str, *, fresh: bool = False, ledger: Path | None = None
) -> Callable[[issues.Issue], issues.Prepared]:
    """What `issues.start` runs once the window allows the start: the branch and worktree of the issue, with the git
    hooks of the repository verified (docs/studio/starting-work.md#worktree). A worktree the issue already has (a
    takeover) is
    reused with its hooks checked, unless `fresh`; two candidates are refused."""
    name = repo.split("/")[-1]
    checkout = root / "repos" / name
    folder = root / "worktrees" / name

    def prepare(issue: issues.Issue) -> issues.Prepared:
        try:
            found = []
            if not fresh and (checkout / ".git").exists():
                entries = issues.load_ledger(ledger) if ledger else {}
                mine = issues.ledger_key(repo, issue.number)
                others = frozenset(e.get("branch", "") for key, e in entries.items() if key != mine) - {""}
                known = entries.get(mine, {}).get("branch", "")
                found = worktrees.existing(
                    checkout, folder, issue.title, issue.number, branch=branch, known=known, others=others
                )
            if found:
                made = worktrees.reuse(found)
                undo: Callable[[], None] = lambda: None  # noqa: E731  # it holds an agent's work: never removed
                lines = [f"branch {made.branch} (existing)", f"worktree {made.path.as_posix()}", *made.hooks]
            else:
                made = worktrees.create(checkout, folder, issue.title, issue.number, branch=branch)
                undo = lambda: worktrees.remove(checkout, made.path, made.branch)  # noqa: E731
                lines = [
                    f"branch {made.branch} from origin {made.base[:10]}",
                    f"worktree {made.path.as_posix()}",
                    *made.hooks,
                ]
        except worktrees.WorktreeError as error:
            raise issues.IssueError(f"{repo}#{issue.number} was not started: {error}") from error
        lines += _install_addons(root, made.path)
        return issues.Prepared(branch=made.branch, path=made.path.as_posix(), lines=lines, undo=undo)

    return prepare


def _install_addons(root: Path, tree: Path) -> list[str]:
    """The pinned Godot addons (GdUnit4, the MCP addon) installed into the Godot project of a worktree `gds issue start`
    made or reused, untracked as `gds workspace init` installs them (docs/studio/workspace.md#integrations); the lines
    say what was done. A failure here only says so: the worktree is made, and `gds workspace init` installs them too."""
    projects = integrations.checkout_projects(tree)
    if not projects:
        return []
    done: list[str] = []
    try:
        kit = workspace.kit_checkout() or root / "repos" / workspace.KIT
        missing = integrations.install_pinned_addons(
            load_tools(kit / "tools.toml").values(), root / "tools", projects, done.append
        )
    except (ManifestError, OSError, subprocess.CalledProcessError) as error:
        return [f"addons: not installed ({error}); run `gds workspace init`"]
    if missing:
        done.append(f"addons: {', '.join(missing)} not fetched; run `gds workspace init` to fetch and install them")
    return done


def _cmd_issue_start(args: argparse.Namespace) -> int:
    repo, number = _issue_ref(args)
    args.repo = repo
    root, settings, ledger = _issue_context(args)
    kit = workspace.kit_checkout() or workspace.require_workspace() / "repos" / workspace.KIT
    refused = disk.refusal(root, disk.load_limits(kit), f"starting {repo}#{number}")
    if refused:  # under the hard limit no agent and no worktree starts (docs/studio/workspace.md#disk)
        raise issues.IssueError(refused)
    for line in issues.start(
        repo,
        number,
        args.agent,
        gh=issues.run_gh,
        ledger=ledger,
        size=settings.window,
        branch=args.branch or "",
        brief_for=lambda issue: [p.line for p in brief.propose(kit, brief.fetch(repo, issue.number, issues.run_gh))],
        prepare=None
        if args.no_worktree
        else _prepare_worktree(root, repo, args.branch or "", fresh=args.fresh, ledger=ledger),
        paused=issues.paused_reason(kit, repo),
    ):
        print(line)
    return 0


def _cmd_issue_list(args: argparse.Namespace) -> int:
    args.repo = args.repo or issues.default_repo(issues.run_gh)
    root, settings, ledger = _issue_context(args)
    kit = workspace.kit_checkout() or root / "repos" / workspace.KIT
    paused = issues.paused_reason(kit, args.repo)
    print(
        "\n".join(issues.list_issues(args.repo, gh=issues.run_gh, ledger=ledger, size=settings.window, paused=paused))
    )
    return 0


def _cmd_issue_release(args: argparse.Namespace) -> int:
    repo, number = _issue_ref(args)
    args.repo = repo
    _, _, ledger = _issue_context(args)
    print("\n".join(issues.release(repo, number, gh=issues.run_gh, ledger=ledger, agent=args.agent or "")))
    return 0


def _cmd_issue_block(args: argparse.Namespace) -> int:
    repo, number = _issue_ref(args)
    args.repo = repo
    _, _, ledger = _issue_context(args)
    lines = issues.block(
        repo, number, args.on, args.why, gh=issues.run_gh, ledger=ledger, who=args.by, conflict=args.conflict or ()
    )
    print("\n".join(lines))
    return 0


def _cmd_issue_unblock(args: argparse.Namespace) -> int:
    repo, number = _issue_ref(args)
    args.repo = repo
    _, _, ledger = _issue_context(args)
    print("\n".join(issues.unblock(repo, number, gh=issues.run_gh, ledger=ledger)))
    return 0


def _cmd_issue_done(args: argparse.Namespace) -> int:
    repo, number = _issue_ref(args)
    args.repo = repo
    _, _, ledger = _issue_context(args)
    print("\n".join(issues.done(repo, number, ledger=ledger)))
    return 0


def _cmd_merge_main(args: argparse.Namespace) -> int:
    path = Path(args.path).resolve() if args.path else Path.cwd()
    issues.refuse_paused(workspace.kit_checkout(), issues.checkout_repo(path), "gds merge-main")
    print("\n".join(worktrees.merge_main(path, co_author=args.co_author or "", resume=args.resume)))
    return 0


def _cmd_pr_hold(args: argparse.Namespace) -> int:
    """`gds pr hold <owner/repo>#N`: the label, then a wait until GitHub's `hold` check is red."""
    repo, number = _issue_ref(args)
    issues.refuse_paused(workspace.kit_checkout(), repo, f"gds pr hold {repo}#{number}")
    print("\n".join(pr.hold(repo, number, gh=issues.run_gh)))
    return 0


def _cmd_pr_check_body(args: argparse.Namespace) -> int:
    """`gds pr check-body <file>`: the description rules of `pr-rules`, run here before `gh pr create|edit`."""
    here = Path(args.repo).resolve() if args.repo else Path.cwd()
    repo = pr.repo_root(here)
    if repo is None:
        raise pr.PrCheckError(f"{here} is not in a git checkout; pass --repo <checkout>")
    issues.refuse_paused(workspace.kit_checkout(), issues.checkout_repo(repo), "gds pr check-body")
    read = lambda source: sys.stdin.read() if source == "-" else Path(source).read_text(encoding="utf-8-sig")  # noqa: E731
    title = None
    if args.title:
        lines = read(args.title).splitlines()
        title = lines[0] if lines else ""
    body, kit = read(args.body), workspace.kit_checkout()
    attach = [spec.split("#", 1)[0] for spec in args.attach or []]  # gh's `path#label` drops its label
    missing = pr.missing_attachments(attach, Path.cwd())
    body = pr.as_uploaded(body, [spec for spec in attach if spec not in missing], Path.cwd())
    changed, why = pr.branch_changes(repo)
    result = pr.check_body(repo, body, title, kit=kit, changed=None if why else changed)
    if missing:
        where = Path.cwd().as_posix()
        result = pr.BodyCheck(
            False,
            [f"`--attach {spec}`: no such file (looked in {where}), so `gh` cannot upload it" for spec in missing]
            + result.reasons,
        )
    docs = pr.check_docs(repo, body, kit=kit)
    if result.ok:
        print("description: ok")
    else:
        print("description: refused", file=sys.stderr)
        for reason in result.reasons:
            print(f"  - {reason}", file=sys.stderr)
    if docs.unknown:  # not an "ok": the rule depends on the branch's files
        print(f"docs: cannot tell, {docs.unknown}; pr-rules will judge it after the push")
    elif docs.ok:
        print("docs: ok")
    else:
        print("docs: refused", file=sys.stderr)
        for reason in docs.reasons:
            print(f"  - {reason}", file=sys.stderr)
    return 0 if result.ok and docs.ok else 1


def _cmd_learn(args: argparse.Namespace) -> int:
    """`gds learn <topic or words>`: the existing sections closest to the words, with their rules, before anyone writes
    a new one (docs/studio/rules.md#find)."""
    kit = workspace.kit_checkout() or workspace.require_workspace() / "repos" / workspace.KIT
    root = Path(args.kit) if args.kit else kit
    print(lessons.learn_text(root, " ".join(args.words), args.limit))
    return 0


def _cmd_brief(args: argparse.Namespace) -> int:
    """`gds brief <owner/repo>#N`: the `Read:` lines of the sections a task agent reads before it starts, for its
    prompt (docs/studio/starting-work.md#starting-an-agent)."""
    kit = workspace.kit_checkout() or workspace.require_workspace() / "repos" / workspace.KIT if not args.kit else None
    kit = Path(args.kit) if args.kit else kit
    repo, number = brief.parse_ref(args.ref)
    print(brief.text(kit, brief.fetch(repo, number, issues.run_gh), args.limit, args.why))
    return 0


def _eval_context() -> tuple[Path, Path]:
    """The kit checkout and the workspace's tools folder."""
    root = workspace.require_workspace()
    kit = workspace.kit_checkout() or root / "repos" / workspace.KIT
    return kit, root / "tools"


def _cmd_eval_list(args: argparse.Namespace) -> int:
    kit, _ = _eval_context()
    for task in evals.tasks(kit).values():
        print(f"{task.name:18} {task.agent:16} {task.title}")
    return 0


def _cmd_eval_prepare(args: argparse.Namespace) -> int:
    kit, tools_dir = _eval_context()
    task = evals.get(kit, args.name)
    target = Path(args.folder).resolve()
    evals.prepare(task, target, kit, tools_dir, workspace.tool_path, print)
    print(f"ready: {target}")
    return 0


def _cmd_eval_check(args: argparse.Namespace) -> int:
    kit, _ = _eval_context()
    task = evals.get(kit, args.name)
    data = evals.check(task, Path(args.folder).resolve(), workspace.tool_path, lambda _line: None, kit)
    print(evals.table(data))
    return 0 if all(r["pass"] for r in data["rows"]) else 1


def _cmd_eval_prompt(args: argparse.Namespace) -> int:
    kit, _ = _eval_context()
    print(evals.prompt(evals.get(kit, args.name), Path(args.folder).resolve(), args.issue, args.gds_project))
    return 0


def _cmd_worktree_sweep(args: argparse.Namespace) -> int:
    root = workspace.require_workspace()
    settings = sweep.Settings(
        idle_hours=args.idle_hours,
        use_idle=not args.no_idle,
        grace_minutes=args.grace_minutes,
        max_keep_bytes=int(args.max_keep_mb * 1024 * 1024),
    )
    print(f"worktree sweep {'(dry run) ' if args.dry_run else ''}{datetime.now().astimezone():%Y-%m-%d %H:%M}")
    try:
        with sweep.lock(root):
            report = sweep.sweep(
                root,
                apply=not args.dry_run,
                settings=settings,
                only=args.only or (),
                repos=args.repo or (),
                deadline_seconds=args.deadline,
            )
    except sweep.Locked as error:
        print(f"skipped: {error}")
        return 0
    print("\n".join(report.lines()))
    return 0


def _cmd_disk_guard(args: argparse.Namespace) -> int:
    root = workspace.require_workspace()
    limits = disk.load_limits(workspace.kit_checkout() or root / "repos" / workspace.KIT)
    print(f"disk guard {'(dry run) ' if args.dry_run else ''}{datetime.now().astimezone():%Y-%m-%d %H:%M}")
    try:
        with sweep.lock(root, disk.LOCK):
            report = disk.guard(root, limits, apply=not args.dry_run, force=args.force)
    except sweep.Locked as error:
        print(f"skipped: {error}")
        return 0
    print("\n".join(report.lines()))
    return 1 if report.level == "hard" else 0


def _cmd_disk_status(args: argparse.Namespace) -> int:
    root = workspace.require_workspace()
    limits = disk.load_limits(workspace.kit_checkout() or root / "repos" / workspace.KIT)
    free = disk.free_bytes(root)
    status = disk.read_status(root)
    print(
        f"disk: {free / disk.GB:.1f} GB free: {disk.level(free, limits)} (soft {limits.soft_gb:g} GB, hard "
        f"{limits.hard_gb:g} GB)"
    )
    if status:
        print(f"last guard run {status.get('checked', '?')}: {status.get('line', '')}")
        for row in status.get("biggest", []):
            print(f"  {row['gb']:8.1f} GB  {row['path']}")
    return 1 if disk.level(free, limits) == "hard" else 0


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
    for check in workspace.check_services(root):  # warnings: signing in is the person's step, not the bootstrap's
        print(f"  {'ok  ' if check.ok else 'WARN'}    {check.name}: {check.detail}")
    print("\n".join(sweep.disk_lines(root)))  # a warning only: low space is not a missing prerequisite
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
    frames.add_argument(
        "--out", help="write the frames to this folder instead (default: the scratch folder of the folder gds runs in)"
    )
    frames.set_defaults(func=_cmd_capture_frames)
    sheet = cap.add_parser("sheet", help="tile a folder's frames into one labelled contact sheet PNG")
    sheet.add_argument("folder")
    sheet.add_argument("--every", type=int, default=1, help="use every K-th frame (default: 1)")
    sheet.add_argument("--columns", type=int, default=4, help="tiles per row (default: 4)")
    sheet.set_defaults(func=_cmd_capture_sheet)
    clip = cap.add_parser("clip", help="encode a folder's frames to an MP4 (or GIF) small enough for GitHub")
    clip.add_argument("folder")
    clip.add_argument(
        "--gif",
        action="store_true",
        help="make a GIF (short, silent, one subject) instead of an MP4, within its budget",
    )
    clip.add_argument(
        "--max-seconds",
        type=float,
        default=capture.CLIP_MAX_SECONDS,
        help=f"cut the clip after this many seconds (default {capture.CLIP_MAX_SECONDS:g}); it still has to fit 9 MB",
    )
    clip.set_defaults(func=_cmd_capture_clip)

    syn = sub.add_parser(
        "sync", help="write the kit's agent definitions, checker, hook launcher and message-check hooks into a game"
    )
    syn.add_argument("game", help="the game repository (a checkout or worktree)")
    syn.add_argument("--check", action="store_true", help="only report files that differ from the kit")
    syn.set_defaults(func=_cmd_sync)

    new = sub.add_parser(
        "new", help="make something new from a template (docs/engines/godot/new-game.md)"
    ).add_subparsers(dest="cmd", required=True)
    game = new.add_parser(
        "game",
        help="make a game repository from a template and publish it on GitHub: files, sync, git, the repository, "
        "its settings, the first CI run and Pages, the kit pull request",
    )
    game.add_argument(
        "name", nargs="?", help="the repository's name: lowercase words joined by hyphens, such as `my-game`"
    )
    game.add_argument("--template", help="a folder of the kit's templates/ with a template.toml (see --list)")
    game.add_argument("--list", action="store_true", help="print the templates, a line each, and stop")
    game.add_argument("--title", help="the game's name as people read it (default: the name, capitalised)")
    game.add_argument("--description", help="one line for the README, the docs site and the project settings")
    game.add_argument("--licence", default="MIT", help="the game's SPDX licence (default: MIT)")
    game.add_argument("--copyright", help="the licence's copyright holder (default: the kit's GitHub owner)")
    game.add_argument("--local", action="store_true", help="stop at the local repository: nothing goes to GitHub")
    game.add_argument("--private", action="store_true", help="make the GitHub repository private (default: public)")
    game.add_argument("--no-wait", action="store_true", help="do not wait for the first CI run and the Pages deploy")
    game.add_argument(
        "--wait-minutes",
        type=float,
        default=new_game_github.DEFAULT_WAIT_MINUTES,
        help="how long to wait for the first CI run and the Pages deploy",
    )
    game.add_argument(
        "--co-author", help="the agent's trailer for the kit commit, such as `Claude Opus 5.5 <noreply@anthropic.com>`"
    )
    game.add_argument("--no-kit-pr", action="store_true", help="do not open the kit pull request for workspace.toml")
    game.add_argument(
        "--remote", help="with --local: an existing GitHub repository's url, recorded as origin and in workspace.toml"
    )
    game.add_argument("--workspace", help="the workspace folder (default: the one around the current folder)")
    game.set_defaults(func=_cmd_new_game)

    tpl = sub.add_parser(
        "template", help="run a template where it can run (docs/engines/godot/new-game.md#proof)"
    ).add_subparsers(dest="cmd", required=True)
    tpl_test = tpl.add_parser(
        "test",
        help="make a game from the working tree's template in a throwaway workspace of its own, parse its scripts, run "
        "its GdUnit4 suites and remove what was made",
    )
    tpl_test.add_argument("name", help="a template of the kit's templates/ (`gds new game --list`)")
    tpl_test.add_argument(
        "--suite",
        action="append",
        default=[],
        help="a suite to run (`tests/core/test_x.gd` or `res://tests/...`); repeat for several, in the order given "
        "(default: all of res://tests, as CI does)",
    )
    tpl_test.add_argument("--keep", action="store_true", help="keep the game and print its path")
    tpl_test.add_argument(
        "--fixed-fps",
        type=int,
        default=template_test.CI_FIXED_FPS,
        help="run Godot with --fixed-fps N: every frame is one tick, no waiting on the clock "
        f"(default {template_test.CI_FIXED_FPS}, as CI runs the suites)",
    )
    tpl_test.add_argument(
        "--real-clock",
        action="store_true",
        help="run on the real clock, with no --fixed-fps (CI does not: a green run here may fail there)",
    )
    tpl_test.add_argument(
        "--godot-args",
        help="more arguments for Godot in one string, joined with `=` (`--godot-args='--audio-driver Dummy'`)",
    )
    tpl_test.add_argument("--gdunit-args", help="more arguments for GdUnit4, as --godot-args")
    tpl_test.add_argument(
        "--timeout", type=float, default=template_test.GDUNIT_TIMEOUT, help="seconds before the GdUnit4 run is stopped"
    )
    tpl_test.set_defaults(func=_cmd_template_test)
    tpl_game = tpl.add_parser("game", help="the same game, imported and kept for captures and probes; prints its path")
    tpl_game.add_argument("name", help="a template of the kit's templates/")
    tpl_game.set_defaults(func=_cmd_template_game)
    tpl_bench = tpl.add_parser(
        "bench-web",
        help="export a bench scene of the template to the web in a throwaway game (the bench as the main scene, "
        "tools/* in the Web pack) and print the build's folder; --run reads it with the bench's probe under gds quiet "
        "(docs/engines/godot/web-probes.md#bench-web)",
    )
    tpl_bench.add_argument("name", help="a template of the kit's templates/")
    tpl_bench.add_argument(
        "scene", help="the bench: its name (`nav_cost_bench`), `tools/bench/<name>.tscn` or its res:// path"
    )
    tpl_bench.add_argument(
        "--run", action="store_true", help="run the bench's probe (<name>.py beside it) on the build, then remove it"
    )
    tpl_bench.add_argument(
        "--probe-args", help="more arguments for the probe after the build folder, in one string (`--probe-args=4`)"
    )
    tpl_bench.add_argument("--keep", action="store_true", help="with --run: keep the game and its build")
    tpl_bench.set_defaults(func=_cmd_template_bench_web)
    tpl_clean = tpl.add_parser("clean", help="remove a workspace made by `template test --keep` or `template game`")
    tpl_clean.add_argument("path", help="the game's path or its workspace folder")
    tpl_clean.set_defaults(func=_cmd_template_clean)

    chk_group = sub.add_parser("check", help="checks of a game's files").add_subparsers(dest="cmd", required=True)
    lay = chk_group.add_parser("layout", help="the folder, naming and dependency rules of a Godot project")
    lay.add_argument("project", nargs="?", default="game", help="the folder holding project.godot (default: game)")
    lay.set_defaults(func=_cmd_check_layout)
    scr = chk_group.add_parser("scripts", help="every GDScript of a Godot project parses (the pinned Godot, headless)")
    scr.add_argument("project", nargs="?", default="game", help="the folder holding project.godot (default: game)")
    scr.set_defaults(func=_cmd_check_scripts)

    iss = sub.add_parser("issue", help="start issues oldest first (docs/studio/starting-work.md)").add_subparsers(
        dest="cmd", required=True
    )
    ref_help = "the issue, as owner/repo#N (#N or N for the repository of the current folder)"
    start = iss.add_parser("start", help="start an issue if it is in the window: label, assign, comment, ledger")
    start.add_argument("ref", help=ref_help)
    start.add_argument("--agent", required=True, help="the agent (or person) that takes it, for the comment and ledger")
    start.add_argument("--branch", help="the name of the branch to make (default: from the issue title)")
    start.add_argument("--no-worktree", action="store_true", help="do not make the branch and worktree (no code work)")
    start.add_argument(
        "--fresh",
        action="store_true",
        help="make a new branch and worktree even when the issue already has one (default: reuse it, a takeover)",
    )
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
    blk = iss.add_parser(
        "block", help="take an issue out of the line with a reason: S-blocked and a 'Blocked (...): waits on' line"
    )
    blk.add_argument("ref", help=ref_help)
    blk.add_argument(
        "--on",
        required=True,
        help="#N (or owner/repo#N) of the open issue or pull request it waits on, or 'maintainer'; #N must be named "
        "as a dependency in the issue body (in its '### Blocked by' section, or 'Depends on: #N', 'Starts after #N', "
        "'Carried from #N') unless --conflict names the files",
    )
    blk.add_argument(
        "--conflict",
        nargs="+",
        metavar="PATH",
        help="the files both issues would edit in ways a merge cannot settle (a reason in place of a dependency; "
        "'same subsystem' or 'same agent' is not one: docs/studio/starting-work.md#parallel)",
    )
    blk.add_argument("--why", required=True, help="the reason, in a sentence (written to the issue body)")
    blk.add_argument("--by", default="coordinator", help="who blocks it, for the body line (default: coordinator)")
    blk.set_defaults(func=_cmd_issue_block)
    unb = iss.add_parser(
        "unblock", help="put a blocked issue back in the line (its blocker closed, or the wait is over)"
    )
    unb.add_argument("ref", help=ref_help)
    unb.set_defaults(func=_cmd_issue_unblock)
    fin = iss.add_parser("done", help="clear an issue from the ledger (a merged Fixes pull request does it anyway)")
    fin.add_argument("ref", help=ref_help)
    fin.set_defaults(func=_cmd_issue_done)

    mrg = sub.add_parser("merge-main", help="merge origin/main into the branch of a worktree with a clean message")
    mrg.add_argument("--path", help="the worktree (default: the current folder)")
    mrg.add_argument("--co-author", help="<model name> <noreply address> (default: the newest trailer on the branch)")
    mrg.add_argument("--continue", dest="resume", action="store_true", help="commit the merge once conflicts are fixed")
    mrg.set_defaults(func=_cmd_merge_main)

    wt = sub.add_parser("worktree", help="worktree upkeep (docs/studio/workspace.md#sweep)").add_subparsers(
        dest="cmd", required=True
    )
    swp = wt.add_parser(
        "sweep",
        help="remove finished worktrees (merged pull request, closed issue, idle) and keep their artwork and notes",
    )
    swp.add_argument("--dry-run", action="store_true", help="report what would be removed; change nothing")
    swp.add_argument(
        "--idle-hours",
        type=float,
        default=6.0,
        help="hours untouched before a worktree no pull request or issue claims is finished (default: 6)",
    )
    swp.add_argument("--no-idle", action="store_true", help="only pull request and issue rules: never the idle rule")
    swp.add_argument(
        "--grace-minutes", type=float, default=30.0, help="a worktree touched more recently is left (default: 30)"
    )
    swp.add_argument(
        "--max-keep-mb",
        type=float,
        default=1024,
        help="refuse a worktree with more files to keep than this (default: 1024)",
    )
    swp.add_argument("--only", nargs="+", metavar="NAME", help="only the worktree folders with these names")
    swp.add_argument("--repo", nargs="+", metavar="REPO", help="only the worktrees of these repositories")
    swp.add_argument("--deadline", type=float, default=1200, help="seconds after which the sweep stops (default: 1200)")
    swp.set_defaults(func=_cmd_worktree_sweep)

    dsk = sub.add_parser("disk", help="the disk guard (docs/studio/workspace.md#disk)").add_subparsers(
        dest="cmd", required=True
    )
    grd = dsk.add_parser(
        "guard",
        help="below the soft limit: sweep, clear idle import caches and finished scratch downloads; write the status",
    )
    grd.add_argument("--dry-run", action="store_true", help="report what would be freed; delete nothing")
    grd.add_argument("--force", action="store_true", help="free what the rules allow even above the soft limit")
    grd.set_defaults(func=_cmd_disk_guard)
    dsk.add_parser("status", help="free space, level and the last guard run's biggest folders").set_defaults(
        func=_cmd_disk_status
    )

    prs = sub.add_parser("pr", help="pull request helpers").add_subparsers(dest="pr_command", required=True)
    chk = prs.add_parser("check-body", help="check a pull request description with the rules of pr-rules")
    chk.add_argument("body", help="the description: a file, or - for stdin")
    chk.add_argument("--title", help="the title (a file, first line): also checks the title-based rules")
    chk.add_argument("--repo", help="a folder in the checkout the pull request is for (default: the current folder)")
    chk.add_argument(
        "--attach",
        action="append",
        metavar="FILE",
        help="a file `gh pr create|edit --attach` will upload: a `](FILE)` reference counts as uploaded; relative "
        "paths are read from the current folder, as gh reads them (repeat for each file)",
    )
    chk.set_defaults(func=_cmd_pr_check_body)
    hol = prs.add_parser("hold", help="hold a pull request: S-hold on, and wait until the `hold` check is red")
    hol.add_argument("ref", help="the pull request: owner/repo#N, or #N in its checkout")
    hol.set_defaults(func=_cmd_pr_hold)

    lrn = sub.add_parser("learn", help="the sections closest to some words, with their rules (update one first)")
    lrn.add_argument("words", nargs="+", help="the topic or words of the mistake")
    lrn.add_argument("--limit", type=int, default=5, help="sections to print (default: 5)")
    lrn.add_argument("--kit", help="the kit checkout or worktree to search (default: the workspace's kit)")
    lrn.set_defaults(func=_cmd_learn)

    brf = sub.add_parser("brief", help="the Read: lines of the sections a task agent reads first, for its prompt")
    brf.add_argument("ref", help="the issue or pull request: owner/repo#N")
    brf.add_argument("--limit", type=int, default=6, help="sections to propose (default: 6)")
    brf.add_argument("--why", action="store_true", help="say after each line why the section is proposed")
    brf.add_argument("--kit", help="the kit checkout or worktree whose docs to read (default: the workspace's kit)")
    brf.set_defaults(func=_cmd_brief)

    ev = sub.add_parser("eval", help="measured agent tasks (docs/studio/agent-evals.md)").add_subparsers(
        dest="cmd", required=True
    )
    ev.add_parser("list", help="the tasks, their agent and title").set_defaults(func=_cmd_eval_list)
    evp = ev.add_parser("prepare", help="make a fresh eval folder: the brief and its inputs")
    evp.add_argument("name")
    evp.add_argument("folder")
    evp.set_defaults(func=_cmd_eval_prepare)
    evc = ev.add_parser("check", help="measure an eval folder's delivery; exit 0 when every number is met")
    evc.add_argument("name")
    evc.add_argument("folder")
    evc.set_defaults(func=_cmd_eval_check)
    evq = ev.add_parser("prompt", help="the fixed prompt of a run, for the Agent call")
    evq.add_argument("name")
    evq.add_argument("folder")
    evq.add_argument("--issue", required=True, help="owner/repo#N the run is made under")
    evq.add_argument("--gds-project", default=evals.GDS_PROJECT, help="the python/ folder whose gds the agent runs")
    evq.set_defaults(func=_cmd_eval_prompt)

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
        pr.PrCheckError,
        new_game.NewGameError,
        template_test.TemplateTestError,
        new_game_github.GitHubError,
        scripts.ScriptCheckError,
        FileNotFoundError,
        evals.EvalError,
    ) as error:
        print(f"gds: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
