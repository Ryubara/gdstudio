"""`gds new game` on GitHub (kit #779): each step with a fake `gh`, real git pushing to local bare repositories, and
the groundwork commands caught before they reach GitHub."""

from __future__ import annotations

import datetime
import json
import shutil
import subprocess
from pathlib import Path

import pytest

from gds_tools import cli, new_game
from gds_tools import new_game_github as github
from gds_tools.issues import IssueError

KIT = Path(__file__).resolve().parents[2]
FULL = "Ryubara/my-game"
CO_AUTHOR = "Claude Opus 5.5 <noreply@anthropic.com>"
GREEN = {"databaseId": 7, "status": "completed", "conclusion": "success", "url": "https://github.com/r/run/7"}
RUNNING = {"databaseId": 7, "status": "in_progress", "conclusion": "", "url": "https://github.com/r/run/7"}
FAILED = {"databaseId": 8, "status": "completed", "conclusion": "failure", "url": "https://github.com/r/run/8"}


@pytest.fixture(autouse=True)
def git_identity(monkeypatch, tmp_path):
    for key, value in {
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.invalid",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.invalid",
        "GIT_CONFIG_GLOBAL": str(tmp_path / "gitconfig"),
        "GIT_CONFIG_SYSTEM": str(tmp_path / "gitconfig"),
    }.items():
        monkeypatch.setenv(key, value)


def git(*args: str, cwd: Path | None = None) -> str:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True).stdout.strip()


@pytest.fixture
def kit(tmp_path) -> Path:
    """The parts of the kit the command reads, as a git checkout whose `origin` is a local bare repository."""
    copy = tmp_path / "kit"
    for rel in ("templates", "godot/addons", ".claude/agents", ".github/scripts", ".github/workflows"):
        shutil.copytree(KIT / rel, copy / rel, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    for rel in (
        "workspace.toml",
        "tools.toml",
        ".pre-commit-config.yaml",
        ".github/conventions.yml",
        ".github/pull_request_template.md",
        "docs/lessons/areas.toml",
    ):
        (copy / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(KIT / rel, copy / rel)
    origin = tmp_path / "kit-origin.git"
    git("init", "--bare", "-b", "main", str(origin))
    git("init", "-b", "main", cwd=copy)
    git("add", "-A", cwd=copy)
    git("commit", "-q", "-m", "kit", cwd=copy)
    git("remote", "add", "origin", str(origin), cwd=copy)
    git("push", "-q", "origin", "main", cwd=copy)
    return copy


@pytest.fixture
def root(tmp_path) -> Path:
    workspace = tmp_path / "workspace"
    (workspace / "repos").mkdir(parents=True)
    return workspace


@pytest.fixture
def game_origin(tmp_path) -> Path:
    """Where `main` is pushed: a bare repository standing in for the one `gh repo create` made."""
    bare = tmp_path / "game-origin.git"
    git("init", "--bare", "-b", "main", str(bare))
    return bare


class FakeGh:
    """`gh` as GitHub would answer it, recording every call."""

    def __init__(
        self,
        *,
        exists=False,
        signed_in=True,
        pages_refusals=0,
        dispatch_failures=0,
        runs=None,
        licences=None,
    ):
        self.calls: list[list[str]] = []
        self.exists = exists
        self.signed_in = signed_in
        self.pages_refusals = pages_refusals
        self.dispatch_failures = dispatch_failures
        self.runs = runs or {"ci.yml": [GREEN], "docs.yml": [GREEN]}
        self.licences = licences or {}
        self.body = ""

    def __call__(self, args: list[str]) -> str:
        self.calls.append(list(args))
        if args[:2] == ["auth", "status"]:
            if not self.signed_in:
                raise IssueError("gh auth status failed: You are not logged into any GitHub hosts")
            return ""
        if args[:2] == ["repo", "view"]:
            if self.exists:
                return '{"name": "my-game"}'
            raise IssueError(f"gh repo view {args[2]} failed: GraphQL: Could not resolve to a Repository")
        if args[:2] == ["repo", "create"]:
            return f"https://github.com/{args[2]}\n"
        if args[0] == "api" and args[-1] == "build_type=workflow":
            if self.pages_refusals:
                self.pages_refusals -= 1
                raise IssueError("gh api -X POST failed: HTTP 422")
            return "{}"
        if args[0] == "api" and args[1].startswith("licenses/"):
            key = args[1].split("/")[1]
            if key not in self.licences:
                raise IssueError("gh api licenses failed: HTTP 404")
            return json.dumps({"body": self.licences[key]})
        if args[0] == "api" and args[1].endswith("/pages"):
            return json.dumps({"html_url": f"https://ryubara.github.io/{args[1].split('/')[2]}/"})
        if args[:2] == ["workflow", "run"]:
            if self.dispatch_failures:
                self.dispatch_failures -= 1
                raise IssueError("gh workflow run failed: could not find any workflows named hold-sweep.yml")
            return ""
        if args[:2] == ["run", "list"]:
            queue = self.runs[args[args.index("--workflow") + 1]]
            return json.dumps([queue.pop(0) if len(queue) > 1 else queue[0]] if queue else [])
        if args[:2] == ["run", "rerun"]:
            return ""
        if args[:2] == ["pr", "create"]:
            self.body = Path(args[args.index("--body-file") + 1]).read_text(encoding="utf-8")
            return "https://github.com/Ryubara/gdstudio/pull/999\n"
        raise AssertionError(f"unexpected gh call: {args}")

    def called(self, *prefix: str) -> list[list[str]]:
        return [c for c in self.calls if c[: len(prefix)] == list(prefix)]


class Runner:
    """Real git; a fake `uvx` (the hooks come from the network); the groundwork commands recorded, never run."""

    def __init__(self, fail_step: str = ""):
        self.groundwork: list[list[str]] = []
        self.fail_step = fail_step

    def __call__(self, argv, *args, **kwargs):
        if argv[0] == "uvx":
            return subprocess.CompletedProcess(argv, 0, "", "")
        if any(str(a).endswith("groundwork.py") for a in argv):
            self.groundwork.append(list(argv))
            step = argv[[str(a).endswith("groundwork.py") for a in argv].index(True) + 1]
            failed = step == self.fail_step
            return subprocess.CompletedProcess(argv, 1 if failed else 0, "", "HTTP 403" if failed else "")
        return subprocess.run(argv, *args, **kwargs)


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds


def make(kit, root, game_origin, gh=None, run=None, options=None, fetch=lambda url: True, **kwargs):
    gh = gh or FakeGh()
    run = run or Runner()
    clock = Clock()
    made = new_game.new_game(
        kit,
        root,
        "my-game",
        "3d-blank",
        options=options or github.Options(co_author=CO_AUTHOR),
        log=lambda _: None,
        run=run,
        gh=gh,
        url=str(game_origin),
        sleep=clock.sleep,
        clock=clock,
        fetch=fetch,
        **kwargs,
    )
    return made, gh, run


def test_every_step_runs_in_order_and_the_proof_is_green(kit, root, game_origin):
    made, gh, run = make(kit, root, game_origin)
    routes = [" ".join(c[:2]) for c in gh.calls]
    order = ["auth status", "repo view", "repo create", "api -X", "workflow run", "run list", "pr create"]
    assert [r for r in dict.fromkeys(routes) if r in order] == order
    published = made.published
    assert published.green and published.pages_live
    assert published.ci.url and published.docs.conclusion == "success"
    assert published.pages_url == "https://ryubara.github.io/my-game/"
    assert published.kit_pr.endswith("/pull/999")
    assert made.todo == []


def test_the_repository_is_public_by_default_with_the_pages_address_as_homepage(kit, root, game_origin):
    _, gh, _ = make(kit, root, game_origin)
    (create,) = gh.called("repo", "create")
    assert create[2] == FULL and "--public" in create
    assert create[create.index("--homepage") + 1] == "https://ryubara.github.io/my-game/"


def test_private_makes_it_private(kit, root, game_origin):
    _, gh, _ = make(kit, root, game_origin, options=github.Options(private=True))
    (create,) = gh.called("repo", "create")
    assert "--private" in create and "--public" not in create


def test_main_is_pushed_and_the_runs_are_those_of_the_pushed_commit(kit, root, game_origin):
    made, gh, _ = make(kit, root, game_origin)
    pushed = git("rev-parse", "main", cwd=game_origin)
    assert pushed == git("rev-parse", "HEAD", cwd=made.repo)
    assert git("remote", "get-url", "origin", cwd=made.repo) == str(game_origin)
    assert all(c[c.index("--commit") + 1] == pushed for c in gh.called("run", "list"))


def test_pages_is_set_to_github_actions_before_the_push(kit, root, game_origin):
    _, gh, _ = make(kit, root, game_origin)
    (pages,) = [c for c in gh.calls if c[-1] == "build_type=workflow"]
    assert pages == ["api", "-X", "POST", f"repos/{FULL}/pages", "-f", "build_type=workflow"]


def test_pages_refused_on_the_empty_repository_is_set_after_the_push_and_the_deploy_is_rerun(kit, root, game_origin):
    gh = FakeGh(pages_refusals=2, runs={"ci.yml": [GREEN], "docs.yml": [FAILED, RUNNING, GREEN]})
    made, gh, _ = make(kit, root, game_origin, gh=gh)
    assert len([c for c in gh.calls if c[-1] == "build_type=workflow"]) == 3  # POST, PUT refused; POST taken
    assert gh.called("run", "rerun") == [["run", "rerun", "8", "--failed", "-R", FULL]]
    assert made.published.docs.conclusion == "success" and made.published.green


def test_a_failed_deploy_is_not_rerun_when_pages_was_there_before_the_push(kit, root, game_origin):
    gh = FakeGh(runs={"ci.yml": [GREEN], "docs.yml": [FAILED]})
    made, gh, _ = make(kit, root, game_origin, gh=gh)
    assert gh.called("run", "rerun") == []
    assert not made.published.green and not made.published.pages_live


def test_pages_refused_twice_stops_with_what_to_do(kit, root, game_origin):
    with pytest.raises(github.GitHubError, match="Pages"):
        make(kit, root, game_origin, gh=FakeGh(pages_refusals=4))


def test_labels_settings_and_ruleset_are_applied_to_the_new_repository(kit, root, game_origin):
    made, _, run = make(kit, root, game_origin)
    steps = [argv[argv.index(".github/scripts/groundwork.py") + 1] for argv in run.groundwork]
    assert steps == ["labels", "settings", "ruleset"]
    for argv in run.groundwork:
        assert argv[-3:] == ["-R", FULL, "--apply"]


def test_a_groundwork_step_that_fails_stops_the_command(kit, root, game_origin):
    with pytest.raises(github.GitHubError, match="ruleset --apply failed"):
        make(kit, root, game_origin, run=Runner(fail_step="ruleset"))


def test_the_hold_sweep_runs_once_and_is_retried_until_github_takes_it(kit, root, game_origin):
    _, gh, _ = make(kit, root, game_origin, gh=FakeGh(dispatch_failures=2))
    assert gh.called("workflow", "run") == [["workflow", "run", "hold-sweep.yml", "-R", FULL]] * 3


def test_a_hold_sweep_github_never_takes_is_left_as_a_step(kit, root, game_origin):
    made, _, _ = make(kit, root, game_origin, gh=FakeGh(dispatch_failures=99))
    assert any("hold-sweep.yml" in step for step in made.todo)


def test_a_run_that_does_not_finish_in_time_is_reported_unfinished(kit, root, game_origin):
    gh = FakeGh(runs={"ci.yml": [RUNNING], "docs.yml": [RUNNING]})
    made, _, _ = make(kit, root, game_origin, gh=gh, options=github.Options(wait_minutes=1))
    assert made.published.ci.conclusion == "" and made.published.ci.url
    assert not made.published.green


def test_a_site_that_does_not_answer_is_not_green(kit, root, game_origin):
    made, _, _ = make(kit, root, game_origin, fetch=lambda url: False)
    assert made.published.docs.conclusion == "success" and not made.published.pages_live
    assert not made.published.green


def test_no_wait_leaves_the_proof_as_a_step(kit, root, game_origin):
    made, gh, _ = make(kit, root, game_origin, options=github.Options(wait=False))
    assert gh.called("run", "list") == []
    assert any("watch the first CI run" in step for step in made.todo)


def test_the_kit_pull_request_adds_the_game_on_its_own_branch(kit, root, game_origin):
    made, gh, _ = make(kit, root, game_origin)
    tree = root / "worktrees" / "gdstudio" / "workspace-add-my-game"
    assert f'[repos.my-game]\nurl = "https://github.com/{FULL}.git"\nrole = "game"' in (
        tree / "workspace.toml"
    ).read_text(encoding="utf-8")
    assert "[repos.my-game]" not in (kit / "workspace.toml").read_text(encoding="utf-8")  # the checkout is untouched
    message = git("log", "-1", "--format=%B", "origin/workspace-add-my-game", cwd=kit)
    assert message.splitlines()[0] == "workspace: Add the my-game game"
    assert message.splitlines()[-1] == f"Co-Authored-By: {CO_AUTHOR}"
    (create,) = gh.called("pr", "create")
    assert create[create.index("--head") + 1] == "workspace-add-my-game"
    assert create[create.index("--title") + 1] == "workspace: Add the my-game game"
    assert "Commits written by:** an AI" in gh.body and "Model:** Claude Opus 5.5" in gh.body
    assert "success (https://github.com/r/run/7)" in gh.body
    assert "answers" in gh.body


def test_the_kit_pull_request_without_a_co_author_says_a_person(kit, root, game_origin):
    _, gh, _ = make(kit, root, game_origin, options=github.Options())
    assert "Commits written by:** a person" in gh.body and "Model:** n/a" in gh.body
    assert "Co-Authored-By" not in git("log", "-1", "--format=%B", "origin/workspace-add-my-game", cwd=kit)


def test_no_kit_pr_opens_none(kit, root, game_origin):
    made, gh, _ = make(kit, root, game_origin, options=github.Options(kit_pr=False))
    assert gh.called("pr", "create") == [] and made.published.kit_pr == ""


def test_the_kit_pull_request_description_passes_the_kits_own_check(kit, root, game_origin):
    from gds_tools import pr

    _, gh, _ = make(kit, root, game_origin)
    assert pr.check_body(KIT, gh.body, "workspace: Add the my-game game", kit=KIT).ok


def test_an_existing_repository_stops_the_command_before_a_file_is_written(kit, root, game_origin):
    with pytest.raises(github.GitHubError, match="exists on GitHub already"):
        make(kit, root, game_origin, gh=FakeGh(exists=True))
    assert not (root / "repos" / "my-game").exists()


def test_gh_signed_out_stops_the_command_before_a_file_is_written(kit, root, game_origin):
    with pytest.raises(github.GitHubError, match="not signed in"):
        make(kit, root, game_origin, gh=FakeGh(signed_in=False))
    assert not (root / "repos" / "my-game").exists()


def test_a_remote_goes_only_with_local(kit, root, game_origin):
    with pytest.raises(new_game.NewGameError, match="--local"):
        make(kit, root, game_origin, remote="https://github.com/Ryubara/my-game.git")


def test_every_new_game_is_mit_with_the_kit_owner_as_holder(kit, root, game_origin):
    made, gh, _ = make(kit, root, game_origin)
    text = (made.repo / "LICENSE").read_text(encoding="utf-8")
    assert text.startswith("MIT License\n")
    assert f"Copyright (c) {datetime.date.today().year} Ryubara\n" in text
    assert gh.called("api", "licenses/mit") == []  # MIT is the template's own file, nobody asked


def test_copyright_names_another_holder(kit, root, game_origin):
    made, _, _ = make(kit, root, game_origin, holder="Someone Else")
    assert "Someone Else" in (made.repo / "LICENSE").read_text(encoding="utf-8")


def test_another_licence_comes_from_github_with_the_year_and_holder(kit, root, game_origin):
    gh = FakeGh(licences={"apache-2.0": "Apache License\nCopyright [yyyy] [name of copyright owner]\n"})
    made, _, _ = make(kit, root, game_origin, gh=gh, licence="Apache-2.0")
    text = (made.repo / "LICENSE").read_text(encoding="utf-8")
    assert text == f"Apache License\nCopyright {datetime.date.today().year} Ryubara\n"


def test_an_unknown_licence_is_refused_before_a_file_is_written(kit, root, game_origin):
    with pytest.raises(new_game.NewGameError, match="no licence 'NOPE-1.0'"):
        make(kit, root, game_origin, licence="NOPE-1.0")
    assert not (root / "repos" / "my-game").exists()


@pytest.fixture
def workspace_root(root, kit, monkeypatch):
    monkeypatch.setattr(cli.workspace, "kit_checkout", lambda: kit)
    (root / ".gdstudio-workspace").write_text("marker\n", encoding="utf-8")
    return root


def capture_call(monkeypatch, made):
    seen = {}

    def fake(*args, **kwargs):
        seen.update(kwargs)
        return made

    monkeypatch.setattr(new_game, "new_game", fake)
    return seen


def test_the_command_publishes_by_default_and_prints_the_urls(workspace_root, monkeypatch, capsys):
    published = github.Published(FULL, f"https://github.com/{FULL}.git", "https://ryubara.github.io/my-game/")
    published.ci = github.RunResult("ci.yml", "success", "https://x/ci")
    published.docs = github.RunResult("docs.yml", "success", "https://x/docs")
    published.pages_live, published.kit_pr = True, "https://x/pull/1"
    seen = capture_call(monkeypatch, new_game.Made(workspace_root / "repos" / "my-game", True, [], published))
    code = cli.main(["new", "game", "my-game", "--template", "3d-blank", "--workspace", str(workspace_root)])
    out = capsys.readouterr().out
    assert code == 0
    assert seen["options"] == github.Options() and seen["licence"] == "MIT"
    for text in (f"https://github.com/{FULL}", "https://x/ci", "https://ryubara.github.io/my-game/", "x/pull/1"):
        assert text in out


def test_the_command_fails_when_the_proof_is_not_green(workspace_root, monkeypatch, capsys):
    published = github.Published(FULL, "u", "p", ci=github.RunResult("ci.yml", "failure", "https://x/ci"))
    capture_call(monkeypatch, new_game.Made(workspace_root / "repos" / "my-game", True, [], published))
    code = cli.main(["new", "game", "my-game", "--template", "3d-blank", "--workspace", str(workspace_root)])
    assert code == 1
    assert "not green" in capsys.readouterr().err


def test_the_flags_reach_the_options(workspace_root, monkeypatch):
    seen = capture_call(monkeypatch, new_game.Made(workspace_root / "repos" / "x", True, []))
    argv = ["new", "game", "x", "--template", "3d-blank", "--workspace", str(workspace_root), "--private"]
    argv += ["--no-wait", "--co-author", CO_AUTHOR, "--no-kit-pr", "--licence", "Apache-2.0", "--copyright", "Me"]
    assert cli.main(argv) == 0
    assert seen["options"] == github.Options(private=True, wait=False, co_author=CO_AUTHOR, kit_pr=False)
    assert seen["licence"] == "Apache-2.0" and seen["holder"] == "Me"


def test_local_sends_nothing_to_github(workspace_root, monkeypatch):
    seen = capture_call(monkeypatch, new_game.Made(workspace_root / "repos" / "x", True, []))
    argv = ["new", "game", "x", "--template", "3d-blank", "--local", "--workspace", str(workspace_root)]
    assert cli.main(argv) == 0
    assert seen["options"] is None


def test_list_prints_the_templates_a_line_each(capsys):
    assert cli.main(["new", "game", "--list"]) == 0
    out = capsys.readouterr().out
    assert out.startswith("3d-blank ") and "prototype level" in out


def test_a_name_and_template_are_needed_without_list(capsys):
    assert cli.main(["new", "game", "my-game"]) == 2
    assert "--list" in capsys.readouterr().err


def test_a_remote_without_local_is_refused_by_the_command(capsys):
    assert cli.main(["new", "game", "x", "--template", "3d-blank", "--remote", "https://github.com/a/b"]) == 2
    assert "--local" in capsys.readouterr().err


def test_the_lfs_hook_pre_commit_moved_aside_is_repaired_so_the_push_runs(kit, root, game_origin, monkeypatch):
    """The first real run died on `git push`: Git LFS's `#!/bin/sh` hook, moved to pre-push.legacy by pre-commit, is
    not found by pre-commit on Windows (worktrees.repair_legacy_hooks)."""
    from types import SimpleNamespace

    from gds_tools import worktrees

    monkeypatch.setattr(worktrees, "os", SimpleNamespace(name="nt"))

    class InstallsHooks(Runner):
        def __call__(self, argv, *args, **kwargs):
            if argv[:3] == ["uvx", "pre-commit", "install"]:
                hooks = Path(kwargs["cwd"]) / ".git" / "hooks"
                (hooks / "pre-push.legacy").write_text('#!/bin/sh\ngit lfs pre-push "$@"\n', encoding="utf-8")
            return super().__call__(argv, *args, **kwargs)

    made, gh, _ = make(kit, root, game_origin, run=InstallsHooks())
    legacy = (made.repo / ".git" / "hooks" / "pre-push.legacy").read_text(encoding="utf-8")
    assert legacy.startswith("#!/usr/bin/env sh\n")
    # The second real run named the kit pull request after the repaired hook: the loop reused the game's `name`.
    (create,) = gh.called("pr", "create")
    assert create[create.index("--head") + 1] == "workspace-add-my-game"
    assert create[create.index("--title") + 1] == "workspace: Add the my-game game"


def test_a_refused_push_shows_the_hooks_report_git_printed_on_stdout(tmp_path):
    def refused(argv, *args, **kwargs):
        if "push" in argv:
            return subprocess.CompletedProcess(argv, 1, "pushed commits follow the conventions...Failed", "error: x")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(github.GitHubError, match=r"(?s)conventions\.\.\.Failed.*error: x"):
        github.push(refused, tmp_path, "https://github.com/a/b.git")
