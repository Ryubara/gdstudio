"""`gds pr check-body` and the guard that refuses `gh pr create|edit` with a body `pr-rules` would refuse: both run
`groundwork.py check-body` (the function CI uses) in the checkout of the repository the pull request is for. The bodies
in fixtures/pr_bodies are the forms that failed after a push on 2026-11-02 (a `None` line without a reason, text after
the reason, a trailing full stop) and the other body rules; throwaway repositories stand for the kit and for a game
whose conventions differ."""

from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest
from git_seed import slim
from hook_support import patch

pytest.importorskip("yaml")

KIT = Path(__file__).resolve().parents[2]
BODIES = Path(__file__).parent / "fixtures" / "pr_bodies"
HOOKS = KIT / ".claude" / "hooks"
sys.path.insert(0, str(HOOKS))
_spec = importlib.util.spec_from_file_location("dispatch", HOOKS / "dispatch.py")
dispatch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dispatch)
guards = dispatch.guards
CONFIG = dispatch.load_config(None)

from gds_tools import cli, issues  # noqa: E402

REASON_NONE = "'None' needs a reason in parentheses"
FAILING = {
    "none-without-reason.txt": REASON_NONE,
    "none-text-after-reason.txt": REASON_NONE,
    "missing-section.txt": "missing the section ## Issues affected",
    "unticked-task.txt": "has an unticked task",
    "local-path.txt": "names a path on someone's machine",
    "bad-closing-line.txt": "a closing line must read 'Fixes #N'",
}
PASSING = ["good.txt", "none-with-full-stop.txt"]


def make_repo(path: Path, remote: str, conventions: str | None = None, groundwork: bool = True) -> Path:
    """A git checkout with the kit's conventions (or `conventions`) and, optionally, its own groundwork.py."""
    (path / ".github" / "scripts").mkdir(parents=True)
    if conventions is None:
        shutil.copy(KIT / ".github" / "conventions.yml", path / ".github" / "conventions.yml")
    else:
        (path / ".github" / "conventions.yml").write_text(conventions, encoding="utf-8", newline="\n")
    if groundwork:
        shutil.copy(KIT / ".github" / "scripts" / "groundwork.py", path / ".github" / "scripts" / "groundwork.py")
    subprocess.run(["git", "init", "-q", "-b", "main", str(path)], check=True)
    subprocess.run(["git", "-C", str(path), "remote", "add", "origin", remote], check=True)
    return path


def game_conventions() -> str:
    """The kit's conventions with one more required section: a game's own rules (deadnight's differ from the kit's)."""
    text = (KIT / ".github" / "conventions.yml").read_text(encoding="utf-8")
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip().startswith("sections:") and "Summary" in line:
            lines[i] = line.rstrip().rstrip("]") + ", Balance]"
            return "\n".join(lines) + "\n"
    pytest.skip("pull_requests.sections is not written on one line")


@pytest.fixture(scope="session")
def workspace_seed(tmp_path_factory: pytest.TempPathFactory) -> Path:
    """The kit's checkout and a game's, made once a session (four git processes) and copied by each test (kit #945)."""
    root = tmp_path_factory.mktemp("check-body-workspace") / "ws"
    (root / "repos").mkdir(parents=True)
    (root / ".gdstudio-workspace").write_text("", encoding="utf-8")
    make_repo(root / "repos" / "gdstudio", "https://github.com/Ryubara/gdstudio.git")
    make_repo(root / "repos" / "deadnight", "https://github.com/Ryubara/deadnight.git", game_conventions())
    return slim(root)


@pytest.fixture()
def workspace(workspace_seed: Path, tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> dict[str, Path]:
    # the real kit pauses Deadnight, and `gds pr check-body` refuses a paused repository (test_paused_prs.py)
    monkeypatch.setattr(issues, "paused_repositories", lambda kit: {})
    root = tmp_path / "ws"
    shutil.copytree(workspace_seed, root)
    return {"root": root, "kit": root / "repos" / "gdstudio", "game": root / "repos" / "deadnight"}


def shell(command: str, cwd: Path) -> dict:
    return {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd)}


def denied(payload: dict) -> str:
    out = dispatch.answer(payload, CONFIG)
    return out["hookSpecificOutput"]["permissionDecisionReason"] if out else ""


def run_gds(args: list[str], capsys: pytest.CaptureFixture[str]) -> tuple[int, str]:
    code = cli.main(args)
    return code, capsys.readouterr().err


# --- gds pr check-body -----------------------------------------------------------------------------------------------


@pytest.mark.parametrize("name", PASSING)
def test_a_body_that_passes_exits_zero(name, workspace, capsys):
    assert cli.main(["pr", "check-body", str(BODIES / name), "--repo", str(workspace["kit"])]) == 0
    assert "description: ok" in capsys.readouterr().out


@pytest.mark.parametrize("name", sorted(FAILING))
def test_each_recorded_failure_exits_one_with_its_reason(name, workspace, capsys):
    code, err = run_gds(["pr", "check-body", str(BODIES / name), "--repo", str(workspace["kit"])], capsys)
    assert code == 1
    assert FAILING[name] in err and "description: refused" in err


def test_it_gives_the_same_answer_as_groundwork_itself(workspace):
    """`gds pr check-body` is `groundwork.py check-body`, not a second implementation of its rules."""
    for name in [*PASSING, *FAILING]:
        direct = subprocess.run(
            [
                sys.executable,
                str(KIT / ".github" / "scripts" / "groundwork.py"),
                "check-body",
                "--body",
                str(BODIES / name),
            ],
            cwd=workspace["kit"],
            capture_output=True,
            text=True,
        )
        ours = cli.main(["pr", "check-body", str(BODIES / name), "--repo", str(workspace["kit"])])
        assert ours == direct.returncode, name


def test_the_title_turns_on_the_title_rules(workspace, capsys):
    """A Fix title needs a `Lessons:` link; without --title the body alone is judged."""
    body = workspace["root"] / "body.md"
    text = (BODIES / "good.txt").read_text(encoding="utf-8")
    kept = [ln for ln in text.splitlines() if not ln.startswith("Lessons:")]
    body.write_text("\n".join(kept) + "\n", encoding="utf-8")
    title = workspace["root"] / "title.txt"
    title.write_text("net: Fix the lag\n", encoding="utf-8")
    kit = str(workspace["kit"])
    code, err = run_gds(["pr", "check-body", str(body), "--title", str(title), "--repo", kit], capsys)
    assert code == 1 and "Lessons" in err
    assert cli.main(["pr", "check-body", str(body), "--repo", kit]) == 0


def test_the_conventions_are_those_of_the_checkout_it_runs_in(workspace, capsys):
    """The same body passes in the kit and fails in the game whose conventions need a ## Balance section."""
    assert cli.main(["pr", "check-body", str(BODIES / "good.txt"), "--repo", str(workspace["kit"])]) == 0
    code, err = run_gds(["pr", "check-body", str(BODIES / "good.txt"), "--repo", str(workspace["game"])], capsys)
    assert code == 1 and "missing the section ## Balance" in err


def test_a_game_without_its_own_groundwork_uses_the_kits_with_its_own_conventions(workspace, monkeypatch, capsys):
    (workspace["game"] / ".github" / "scripts" / "groundwork.py").unlink()
    monkeypatch.setattr(cli.workspace, "kit_checkout", lambda: workspace["kit"])
    code, err = run_gds(["pr", "check-body", str(BODIES / "good.txt"), "--repo", str(workspace["game"])], capsys)
    assert code == 1 and "missing the section ## Balance" in err


def test_a_folder_that_is_not_a_checkout_exits_two(tmp_path, capsys):
    code, err = run_gds(["pr", "check-body", str(BODIES / "good.txt"), "--repo", str(tmp_path)], capsys)
    assert code == 2 and "not in a git checkout" in err


# --- the guard -------------------------------------------------------------------------------------------------------


@pytest.mark.parametrize("name", PASSING)
def test_the_guard_lets_a_passing_body_through(name, workspace):
    body = BODIES / name
    assert denied(shell(f"gh pr create --title 'x: Add y' --body-file {body}", workspace["kit"])) == ""
    assert denied(shell(f"gh pr edit 7 --body-file {body}", workspace["kit"])) == ""


@pytest.mark.parametrize("name", sorted(FAILING))
def test_the_guard_refuses_a_failing_body_and_names_the_command(name, workspace):
    body = BODIES / name
    for command in (f"gh pr create --title 'x: Add y' --body-file {body}", f"gh pr edit 7 --body-file={body}"):
        reason = denied(shell(command, workspace["kit"]))
        assert FAILING[name] in reason, command
        assert "gds pr check-body " in reason and body.name in reason and "uv run --project" in reason
        assert "--title <title file>" in reason or "edit" in command


def test_the_guard_judges_a_literal_body_and_passes_the_title_to_the_check(workspace):
    """A literal `--body` is read as it stands (one with a backtick or `$(` is a shell substitution: not judged)."""
    kit = workspace["kit"]
    bad = (BODIES / "none-without-reason.txt").read_text(encoding="utf-8").replace("`", "")
    reason = denied(shell(f"gh pr create --title 'x: Add y' --body '{bad}'", kit))
    assert REASON_NONE in reason and "<body file>" in reason
    good = (BODIES / "good.txt").read_text(encoding="utf-8").replace("`", "")
    assert denied(shell(f"gh pr create --title 'x: Add y' --body '{good}'", kit)) == ""
    fix = denied(shell(f"gh pr create --title 'net: Fix the lag' --body-file {BODIES / 'good.txt'}", kit))
    assert fix == ""  # good.txt already links its lesson
    kept = "\n".join(ln for ln in good.splitlines() if not ln.startswith("Lessons:"))
    fix = denied(shell(f"gh pr create --title 'net: Fix the lag' --body '{kept}'", kit))
    assert "Lessons" in fix


def test_the_guard_runs_in_the_checkout_of_the_repository_it_is_run_in(workspace):
    body = BODIES / "good.txt"
    assert denied(shell(f"gh pr edit 7 --body-file {body}", workspace["kit"])) == ""
    reason = denied(shell(f"gh pr edit 7 --body-file {body}", workspace["game"]))
    assert "missing the section ## Balance" in reason and "(deadnight)" in reason


def test_the_guard_follows_gh_dash_r_to_the_named_repository(workspace):
    """From the kit's checkout, `gh -R Ryubara/deadnight` is judged by deadnight's conventions, and the kit's own by the
    kit's; a repository with no checkout is not judged."""
    body = BODIES / "good.txt"
    kit = workspace["kit"]
    reason = denied(shell(f"gh pr edit 7 -R Ryubara/deadnight --body-file {body}", kit))
    assert "missing the section ## Balance" in reason
    assert denied(shell(f"gh pr edit 7 --repo Ryubara/gdstudio --body-file {body}", kit)) == ""
    assert denied(shell(f"gh pr edit 7 -R Ryubara/elsewhere --body-file {body}", kit)) == ""


def test_the_guard_does_not_judge_what_it_cannot_read(workspace):
    kit = workspace["kit"]
    for command in (
        "gh pr create --title x --body-file missing.md",
        "gh pr create --title x --body-file -",
        'gh pr create --title x --body "$(cat body.md)"',
        "gh pr edit 7 --add-label bug",
        "gh pr edit 7 --title 'x: Add y'",
        "gh pr create --fill",
    ):
        assert denied(shell(command, kit)) == "", command


def test_the_guard_leaves_other_commands_and_a_disabled_rule_alone(workspace):
    kit = workspace["kit"]
    bad = BODIES / "none-without-reason.txt"
    assert denied(shell(f"gh issue create --title x --body-file {bad}", kit)) == ""
    assert "pr-rules" not in denied(shell(f"gh pr comment 7 --body-file {bad}", kit))
    off = {**CONFIG, "pr_body": {"enforce": False}}
    out = dispatch.answer(shell(f"gh pr edit 7 --body-file {bad}", kit), off)
    assert out is None


def test_the_guard_lets_a_command_through_when_the_checker_is_missing(workspace):
    (workspace["kit"] / ".github" / "scripts" / "groundwork.py").unlink()
    (workspace["kit"] / ".github" / "conventions.yml").unlink()
    body = BODIES / "none-without-reason.txt"
    assert denied(shell(f"gh pr edit 7 --body-file {body}", workspace["kit"])) == ""


def test_one_body_read_serves_both_checks(workspace, monkeypatch):
    """`--attach` and the description rules read the body once and both can refuse it in the same answer."""
    reads = []
    real = guards.body_of
    patch(monkeypatch, "body_of", lambda *args: reads.append(1) or real(*args))
    body = BODIES / "none-without-reason.txt"
    reason = denied(shell(f"gh pr edit 7 --body-file {body} --attach {workspace['root']}/after.png", workspace["kit"]))
    assert REASON_NONE in reason and "has no reference" in reason
    assert len(reads) == 1


# --- --attach and the description rules agree (kit #186) -------------------------------------------------------------


def visual_body(tmp_path: Path, before: str = "./before.png", after: str = "./after.png") -> Path:
    """good.txt with a Before:/After: pair of `./` references in ## Screenshots, as `gh pr create --attach` wants."""
    text = (BODIES / "good.txt").read_text(encoding="utf-8")
    old = "Screenshots: none (checker code and docs only, nothing visible)"
    new = f"- **Before:** ![before]({before})\n- **After:** ![after]({after})"
    assert old in text
    path = tmp_path / "body.md"
    path.write_text(text.replace(old, new), encoding="utf-8", newline="\n")
    return path


ATTACHED = "--attach {d}/before.png --attach {d}/after.png"


@pytest.fixture()
def scratch(workspace) -> Path:
    """<workspace>/scratch/game/task: where captures and the body file live, beside the checkouts, never inside one."""
    folder = workspace["root"] / "scratch" / "game" / "task"
    folder.mkdir(parents=True)
    return folder


KIT_PR = "gh pr {verb} -R Ryubara/gdstudio --body-file {body} {flags}"


def test_local_references_that_attach_uploads_pass_both_guards(workspace, scratch):
    """Failed first: the description rules saw `./before.png`, not an upload, and refused the Before:/After: pair."""
    body = visual_body(scratch)
    flags = ATTACHED.format(d=scratch)
    for verb in ("create --title 'godot: Add y'", "edit 7"):
        # run from the folder that holds the images: `gh` swaps `./before.png` for the upload only there (kit #242)
        command = f"cd {scratch} && " + KIT_PR.format(verb=verb, body=body, flags=flags)
        assert denied(shell(command, workspace["kit"])) == ""


def test_the_same_body_without_attach_is_refused(workspace, tmp_path):
    body = visual_body(tmp_path)
    reason = denied(shell(f"gh pr create --title 'godot: Add y' --body-file {body}", workspace["kit"]))
    assert "'Before:' capture" in reason and "'After:' capture" in reason


def test_only_the_attached_files_count_as_uploaded(workspace, scratch):
    """Attaching the after capture does not make the before reference an upload."""
    body = visual_body(scratch)
    command = f"cd {scratch} && " + KIT_PR.format(
        verb="create --title 'godot: Add y'", body=body, flags=f"--attach {scratch}/after.png"
    )
    reason = denied(shell(command, workspace["kit"]))
    assert "the 'Before:' capture is missing" in reason and "the 'After:' capture is missing" not in reason


def test_a_reference_by_bare_name_and_a_labelled_attach_count_too(workspace, scratch):
    body = visual_body(scratch, before="before.png", after="./after.png")
    flags = f"--attach '{scratch}/before.png#Before' --attach {scratch}/after.png"
    command = f"cd {scratch} && " + KIT_PR.format(verb="create --title 'godot: Add y'", body=body, flags=flags)
    assert denied(shell(command, workspace["kit"])) == ""


# --- --attach rewrites a reference only when it is the same file (kit #242) -------------------------------------------
# Deadnight #611 and #637 were opened from the worktree with `--attach` paths in the scratch folder and `./before.png`
# references in the body. `gh` compares the two as files, so it left the references local and appended the uploads
# after `## AI use`; the guard matched them by file name and let it through.


def test_attach_from_another_folder_leaves_the_references_local_and_both_guards_refuse_it(workspace, scratch):
    """Failed first: the command was let through, and the pull request reached CI with `./before.png` references."""
    body = visual_body(scratch)
    command = KIT_PR.format(verb="create --title 'godot: Add y'", body=body, flags=ATTACHED.format(d=scratch))
    reason = denied(shell(command, workspace["kit"]))
    assert "does not name the attached file" in reason and "is a different file from `./before.png`" in reason
    assert f"{workspace['kit'].as_posix()}/before.png" in reason  # where `gh` looks for the reference
    assert "cd <dir> && gh pr create" in reason  # what to do
    assert "the 'Before:' capture is missing" in reason  # the body guard agrees: nothing would be uploaded in place


def test_powershell_is_guarded_the_same_way(workspace, scratch):
    body = visual_body(scratch)
    command = KIT_PR.format(verb="create --title 'godot: Add y'", body=body, flags=ATTACHED.format(d=scratch))
    payload = {**shell(command, workspace["kit"]), "tool_name": "PowerShell"}
    assert "does not name the attached file" in denied(payload)
    moved = {**shell(f"Set-Location '{scratch}'; {command}", workspace["kit"]), "tool_name": "PowerShell"}
    assert denied(moved) == ""


def test_attach_is_allowed_from_the_images_folder(workspace, scratch):
    """`gh` rewrites `./before.png` when it runs where the images are, whatever form the `--attach` path has."""
    body = visual_body(scratch)
    verb = "create --title 'godot: Add y'"
    relative = f"cd {scratch} && " + KIT_PR.format(
        verb=verb, body=body, flags="--attach ./before.png --attach ./after.png"
    )
    absolute = f"cd {scratch} && " + KIT_PR.format(verb=verb, body=body, flags=ATTACHED.format(d=scratch))
    assert denied(shell(relative, workspace["kit"])) == ""
    assert denied(shell(absolute, workspace["kit"])) == ""


def test_attach_is_allowed_from_anywhere_when_the_reference_has_the_same_absolute_path(workspace, scratch):
    body = visual_body(scratch, before=f"{scratch.as_posix()}/before.png", after=f"{scratch.as_posix()}/after.png")
    command = KIT_PR.format(verb="create --title 'godot: Add y'", body=body, flags=ATTACHED.format(d=scratch))
    assert denied(shell(command, workspace["kit"])) == ""


def test_a_relative_attach_path_and_a_reference_to_the_same_file_match(workspace, scratch):
    """The paths differ in form, not in file."""
    kit = workspace["kit"]
    relative = Path(os.path.relpath(scratch, kit)).as_posix()
    body = visual_body(scratch, before=f"{relative}/before.png", after=f"{relative}/after.png")
    command = KIT_PR.format(verb="create --title 'godot: Add y'", body=body, flags=ATTACHED.format(d=scratch))
    assert denied(shell(command, kit)) == ""


def test_a_cd_that_cannot_be_followed_cannot_place_a_relative_reference(workspace, scratch):
    body = visual_body(scratch)
    command = "cd $DIR && " + KIT_PR.format(
        verb="create --title 'godot: Add y'", body=body, flags=ATTACHED.format(d=scratch)
    )
    reason = denied(shell(command, workspace["kit"]))
    assert "does not name the attached file" in reason and "a folder this hook cannot follow" in reason


def test_gds_pr_check_body_by_hand_still_wants_uploaded_captures(workspace, tmp_path, capsys):
    """The command has no `--attach`: a `./` reference is not an upload there, so its answer is unchanged."""
    body = visual_body(tmp_path)
    title = tmp_path / "title.txt"
    title.write_text("godot: Add y\n", encoding="utf-8")
    code, err = run_gds(["pr", "check-body", str(body), "--title", str(title), "--repo", str(workspace["kit"])], capsys)
    assert code == 1 and "'Before:' capture" in err


# --- gds pr check-body --attach: the captures the command will upload (kit #1188) -----------------------------------
# Three agents on 2026-11-11 (PRs #1165, #1168, #1175) could not pass `gds pr check-body` with `./after.png` references:
# the file is only uploaded by `gh pr create --attach`, so the command run alone always said the captures were missing.


def check_by_hand(workspace, folder: Path, body: Path, capsys, *attach: str) -> tuple[int, str]:
    """`cd <folder> && gds pr check-body <body> --title <title> --attach ...`, as `gh pr create` would run there."""
    title = folder / "title.txt"
    title.write_text("godot: Add y\n", encoding="utf-8")
    args = ["pr", "check-body", str(body), "--title", str(title), "--repo", str(workspace["kit"])]
    for spec in attach:
        args += ["--attach", spec]
    return run_gds(args, capsys)


def captures(folder: Path, *names: str) -> None:
    for name in names:
        (folder / name).write_bytes(b"PNG")


def test_check_body_counts_local_files_about_to_be_attached(workspace, scratch, capsys, monkeypatch):
    """Failed first: `--attach` was not an argument, and without it the pair was refused as missing."""
    body = visual_body(scratch)
    captures(scratch, "before.png", "after.png")
    monkeypatch.chdir(scratch)
    code, err = check_by_hand(workspace, scratch, body, capsys, "./before.png", f"{scratch}/after.png")
    assert code == 0, err


def test_check_body_still_refuses_a_reference_that_is_not_attached(workspace, scratch, capsys, monkeypatch):
    """Attaching the after capture does not make `./before.png` an upload: CI's own words come back."""
    body = visual_body(scratch)
    captures(scratch, "before.png", "after.png")
    monkeypatch.chdir(scratch)
    code, err = check_by_hand(workspace, scratch, body, capsys, "./after.png")
    assert code == 1
    assert "the 'Before:' capture is missing" in err and "the 'After:' capture is missing" not in err


def test_check_body_refuses_an_attach_file_that_does_not_exist(workspace, scratch, capsys, monkeypatch):
    """`gh` cannot upload a file that is not there, so the reference stays local and the capture is missing."""
    body = visual_body(scratch)
    captures(scratch, "before.png")
    monkeypatch.chdir(scratch)
    code, err = check_by_hand(workspace, scratch, body, capsys, "./before.png", "./after.png")
    assert code == 1
    assert "`--attach ./after.png`: no such file" in err
    assert "the 'After:' capture is missing" in err and "the 'Before:' capture is missing" not in err


def test_check_body_passes_uploaded_addresses_without_attach(workspace, scratch, capsys):
    upload = "https://github.com/user-attachments/assets/11111111-2222-3333-4444-555555555555"
    body = visual_body(scratch, before=upload, after=upload)
    code, err = check_by_hand(workspace, scratch, body, capsys)
    assert code == 0, err


def test_check_body_wording_is_the_checkers_own(workspace, scratch, capsys, monkeypatch):
    """The reasons printed for a refused pair are the lines `groundwork.py check-body` (CI's `body` job) prints."""
    body = visual_body(scratch)
    captures(scratch, "after.png")
    monkeypatch.chdir(scratch)
    code, err = check_by_hand(workspace, scratch, body, capsys, "./after.png")
    uploaded = scratch / "uploaded.md"
    uploaded.write_text(
        body.read_text(encoding="utf-8").replace("(./after.png)", f"({guards.UPLOAD_STAND_IN})"), encoding="utf-8"
    )
    direct = subprocess.run(
        [
            sys.executable,
            str(KIT / ".github" / "scripts" / "groundwork.py"),
            "check-body",
            "--body",
            str(uploaded),
            "--title",
            str(scratch / "title.txt"),
        ],
        cwd=workspace["kit"],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    expected = [line.strip() for line in direct.stderr.splitlines() if line.strip().startswith("- ")]
    assert code == 1 and direct.returncode == 1 and expected
    for line in expected:
        assert line in err


def test_the_guard_names_the_check_body_command_with_the_same_attach_files(workspace, scratch):
    """Failed first: the guard told the agent to run `gds pr check-body <file>` without `--attach`, which refuses the
    very captures the guard had counted as uploaded."""
    body = visual_body(scratch)
    command = f"cd {scratch} && " + KIT_PR.format(
        verb="create --title 'godot: Add y'", body=body, flags="--attach ./after.png"
    )
    reason = denied(shell(command, workspace["kit"]))
    assert "the 'Before:' capture is missing" in reason
    assert "gds pr check-body " in reason and " --title <title file> --attach ./after.png`" in reason
    assert f"run it in {scratch.as_posix()}" in reason


@pytest.mark.parametrize(
    "files, cwd_name",
    [
        (["./before.png"], "task"),
        (["before.png#Before", "after.png"], "task"),
        (["{d}/after.png"], "elsewhere"),
        (["https://example.com/x.png"], "task"),
        ([], "task"),
    ],
)
def test_the_command_and_the_hook_swap_the_same_references(files, cwd_name, scratch):
    """`gds pr check-body --attach` and the PR-create guard judge one body: their swaps agree (writing-checks.md)."""
    from gds_tools import pr

    text = visual_body(scratch, before="./before.png", after=f"{scratch}/after.png").read_text(encoding="utf-8")
    cwd = scratch if cwd_name == "task" else scratch.parent
    specs = [f.format(d=scratch).split("#", 1)[0] for f in files]
    assert pr.as_uploaded(text, specs, cwd) == guards.as_uploaded(text, specs, cwd)
    assert pr.UPLOAD_STAND_IN == guards.UPLOAD_STAND_IN


# --- a relative --body-file after a leading cd (kit #213) ------------------------------------------------------------


@pytest.fixture()
def folder(workspace: dict[str, Path]) -> Path:
    """`notes dir/sub dir` in the kit checkout (the repository that judges the body), holding body.md, a body
    `pr-rules` refuses (so a body that was read shows as a refusal)."""
    where = workspace["kit"] / "notes dir" / "sub dir"
    where.mkdir(parents=True)
    shutil.copy(BODIES / "none-without-reason.txt", where / "body.md")
    return where


@pytest.mark.parametrize(
    "template",
    [
        'cd "{dir}" && gh pr edit 7 --body-file body.md',
        'cd "{dir}"; gh pr edit 7 --body-file ./body.md',
        "cd '{dir}' && gh pr edit 7 --body-file=body.md",
    ],
)
def test_a_relative_body_file_is_read_from_the_absolute_cd_folder(template, folder, workspace):
    assert REASON_NONE in denied(shell(template.format(dir=folder.as_posix()), workspace["kit"]))


def test_a_relative_body_file_is_read_from_a_relative_cd_folder(folder, workspace):
    here = folder.parent
    command = 'cd "sub dir" && gh pr edit 7 --body-file body.md'
    assert REASON_NONE in denied(shell(command, here))
    two = 'cd "notes dir" && cd "sub dir" && gh pr edit 7 --body-file body.md'
    assert REASON_NONE in denied(shell(two, here.parent))


def test_the_cd_folder_is_where_the_file_is_looked_for(folder, workspace):
    """The file is not in the `cd` folder: the reason names the folder it looked in and offers the absolute path."""
    command = f'cd "{folder.parent.as_posix()}" && gh pr edit 7 --body-file body.md --attach {folder}/a.png'
    reason = denied(shell(command, workspace["kit"]))
    assert "does not exist yet" in reason and "notes dir/body.md" in reason and "absolute path" in reason


@pytest.mark.skipif(sys.platform != "win32", reason="Git Bash drive paths are a Windows form")
def test_a_git_bash_drive_path_and_cd_d_are_followed(folder, workspace):
    drive = folder.as_posix()
    msys = f"/{drive[0].lower()}{drive[2:]}"
    assert REASON_NONE in denied(shell(f'cd "{msys}" && gh pr edit 7 --body-file body.md', workspace["kit"]))
    assert REASON_NONE in denied(shell(f'cd /d "{drive}" && gh pr edit 7 --body-file body.md', workspace["kit"]))


@pytest.mark.parametrize("cd", ["cd $DIR", "cd -", "cd", "cd a b", "cd $(pwd)/x"])
def test_a_cd_that_cannot_be_followed_asks_for_an_absolute_path(cd, folder, workspace):
    """A `cd` this hook cannot parse leaves a relative body file unplaced: the reason says so."""
    reason = denied(shell(f"{cd} && gh pr edit 7 --body-file body.md --attach {folder}/a.png", workspace["kit"]))
    assert "use an absolute path" in reason and "does not exist yet" not in reason
    assert denied(shell(f'{cd} && gh pr edit 7 --body-file "{folder.as_posix()}/body.md"', workspace["kit"])) != ""


def test_an_unparsable_cd_lets_a_relative_body_through_without_attach(folder, workspace):
    """Nothing to judge when the body cannot be placed, as with a body that is not written yet."""
    assert denied(shell("cd $DIR && gh pr edit 7 --body-file body.md", workspace["kit"])) == ""


# --- the docs rule against the branch's diff (kit #215) ---------------------------------------------------------------

GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false"]


def branch_with(repo: Path, files: dict[str, str], branch: str = "feature") -> Path:
    """Commit the repository's files on main, call that origin/main, then commit `files` on a new branch."""
    subprocess.run([*GIT, "-C", str(repo), "add", "-A"], check=True)
    subprocess.run([*GIT, "-C", str(repo), "commit", "-q", "-m", "base"], check=True)
    subprocess.run(["git", "-C", str(repo), "update-ref", "refs/remotes/origin/main", "HEAD"], check=True)
    subprocess.run(["git", "-C", str(repo), "checkout", "-q", "-b", branch], check=True)
    for name, text in files.items():
        target = repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8", newline="\n")
    subprocess.run([*GIT, "-C", str(repo), "add", "-A"], check=True)
    subprocess.run([*GIT, "-C", str(repo), "commit", "-q", "-m", "change"], check=True)
    return repo


def docs_body(tmp_path: Path, with_docs_line: str = "") -> Path:
    """good.txt, with a `Docs: none` line when asked (the line is read exactly, as pr-rules reads it)."""
    text = (BODIES / "good.txt").read_text(encoding="utf-8")
    assert "Docs: none" not in text
    path = tmp_path / "docs-body.md"
    path.write_text(text + (f"\n{with_docs_line}\n" if with_docs_line else ""), encoding="utf-8", newline="\n")
    return path


def test_code_changed_without_docs_or_a_docs_line_is_refused(workspace, tmp_path, capsys):
    kit = branch_with(workspace["kit"], {"python/src/gds_tools/new.py": "x = 1\n"})
    code, err = run_gds(["pr", "check-body", str(docs_body(tmp_path)), "--repo", str(kit)], capsys)
    assert code == 1 and "docs: refused" in err and "code changed without a docs change" in err


def test_a_docs_none_line_passes_the_docs_rule(workspace, tmp_path, capsys):
    kit = branch_with(workspace["kit"], {"python/src/gds_tools/new.py": "x = 1\n"})
    body = docs_body(tmp_path, "Docs: none")
    assert cli.main(["pr", "check-body", str(body), "--repo", str(kit)]) == 0
    assert "docs: ok" in capsys.readouterr().out


def test_a_changed_docs_file_passes_the_docs_rule(workspace, tmp_path, capsys):
    kit = branch_with(workspace["kit"], {"python/src/gds_tools/new.py": "x = 1\n", "docs/page.md": "# Page\n"})
    assert cli.main(["pr", "check-body", str(docs_body(tmp_path)), "--repo", str(kit)]) == 0
    assert "docs: ok" in capsys.readouterr().out


def test_a_change_to_neither_code_nor_docs_passes_the_docs_rule(workspace, tmp_path, capsys):
    kit = branch_with(workspace["kit"], {"notes.txt": "hi\n"})
    assert cli.main(["pr", "check-body", str(docs_body(tmp_path)), "--repo", str(kit)]) == 0
    assert "docs: ok" in capsys.readouterr().out


@pytest.mark.parametrize("state", ["no-commits", "on-main", "detached", "no-origin"])
def test_without_a_branch_the_docs_rule_says_it_cannot_tell(state, workspace, tmp_path, capsys):
    kit = workspace["kit"]
    if state != "no-commits":
        branch_with(kit, {"python/src/gds_tools/new.py": "x = 1\n"})
        if state == "on-main":
            subprocess.run(["git", "-C", str(kit), "checkout", "-q", "main"], check=True)
        elif state == "detached":
            subprocess.run(["git", "-C", str(kit), "checkout", "-q", "--detach"], check=True)
        else:
            subprocess.run(["git", "-C", str(kit), "update-ref", "-d", "refs/remotes/origin/main"], check=True)
    assert cli.main(["pr", "check-body", str(docs_body(tmp_path)), "--repo", str(kit)]) == 0
    out = capsys.readouterr().out
    assert "docs: cannot tell" in out and "docs: ok" not in out


def test_the_guard_refuses_a_code_branch_without_a_docs_line(workspace, tmp_path):
    kit = branch_with(workspace["kit"], {"python/src/gds_tools/new.py": "x = 1\n"})
    body = docs_body(tmp_path)
    assert "code changed without a docs change" in denied(shell(f"gh pr edit 7 --body-file {body}", kit))
    ok = docs_body(tmp_path, "Docs: none")
    assert denied(shell(f"gh pr edit 7 --body-file {ok}", kit)) == ""


def test_the_guard_does_not_judge_the_docs_rule_without_a_branch(workspace, tmp_path):
    assert denied(shell(f"gh pr edit 7 --body-file {docs_body(tmp_path)}", workspace["kit"])) == ""


@pytest.mark.parametrize(
    ("changed", "refused"),
    [("docs/studio/hooks.md", False), ("docs/page.md", True)],
)
def test_a_fix_names_a_section_its_branch_edits(workspace, tmp_path, capsys, changed, refused):
    """`Lessons: docs/studio/hooks.md#pr-body` holds only when the branch changes that page (gdstudio #769): the rule is
    written into the section in the same pull request. `gds pr check-body` passes the branch's files to the checker."""
    kit = branch_with(workspace["kit"], {changed: "# Page\n"})
    title = tmp_path / "title.txt"
    title.write_text("hooks: Fix the body check\n", encoding="utf-8")
    body = tmp_path / "body.md"
    text = (
        (BODIES / "good.txt").read_text(encoding="utf-8").replace("Testing\n\n", "Testing\n\nFailed first: none (x).\n")
    )
    body.write_text(text, encoding="utf-8", newline="\n")
    code, err = run_gds(["pr", "check-body", str(body), "--title", str(title), "--repo", str(kit)], capsys)
    assert ("does not change that page" in err) is refused, err


# --- a listed Screenshots none line (kit #931) -----------------------------------------------------------------------

NONE_LINE = "Screenshots: none (checker code and docs only, nothing visible)"


@pytest.mark.parametrize(
    "line",
    [NONE_LINE, f"- {NONE_LINE}", f"* {NONE_LINE}", f"  - {NONE_LINE}", "- **Screenshots:** none (a text check)"],
    ids=["bare", "dash", "star", "indented", "bold"],
)
def test_a_screenshots_none_line_passes_bare_or_listed(line, workspace, tmp_path, capsys):
    """Failed first: `- Screenshots: none (reason)` was read as a missing Before:/After: pair for a `godot` title."""
    text = (BODIES / "good.txt").read_text(encoding="utf-8")
    assert NONE_LINE in text
    body, title = tmp_path / "body.md", tmp_path / "title.txt"
    body.write_text(text.replace(NONE_LINE, line), encoding="utf-8", newline="\n")
    title.write_text("godot: Add y\n", encoding="utf-8")
    args = ["pr", "check-body", str(body), "--title", str(title), "--repo", str(workspace["kit"])]
    assert run_gds(args, capsys)[0] == 0


@pytest.mark.parametrize(
    "line", ["- Screenshots: none", "- Screenshots: none (a reason) and more", "- Screenshots: none ()"]
)
def test_a_listed_screenshots_none_line_still_needs_its_reason(line, workspace, tmp_path, capsys):
    text = (BODIES / "good.txt").read_text(encoding="utf-8")
    body, title = tmp_path / "body.md", tmp_path / "title.txt"
    body.write_text(text.replace(NONE_LINE, line), encoding="utf-8", newline="\n")
    title.write_text("godot: Add y\n", encoding="utf-8")
    args = ["pr", "check-body", str(body), "--title", str(title), "--repo", str(workspace["kit"])]
    code, err = run_gds(args, capsys)
    assert code == 1 and "needs a reason in parentheses" in err


# --- Read first: sections from origin/main, as CI reads them (kit #1131) ---------------------------------------------

MAIN_PAGE = "# Hooks\n\n## Docs {#docs}\n\nOn main.\n"
BRANCH_PAGE = "# New\n\n## Fresh {#fresh}\n\nOnly on the branch.\n"


def read_first_branch(workspace: dict[str, Path]) -> Path:
    """The kit with docs/studio/hooks.md#docs on origin/main and a branch that adds docs/studio/new.md#fresh."""
    page = workspace["kit"] / "docs" / "studio" / "hooks.md"
    page.parent.mkdir(parents=True)
    page.write_text(MAIN_PAGE, encoding="utf-8", newline="\n")
    return branch_with(workspace["kit"], {"docs/studio/new.md": BRANCH_PAGE})


def read_first_body(tmp_path: Path, read_first: str, lessons: str) -> tuple[Path, Path]:
    """good.txt with its `Read first:` and `Lessons:` lines replaced, and an Add title (no lesson is required)."""
    text = (BODIES / "good.txt").read_text(encoding="utf-8")
    text = text.replace("Read first: studio/hooks.md#docs", f"Read first: {read_first}")
    text = text.replace("Lessons: docs/studio/hooks.md#pr-body", f"Lessons: {lessons}")
    body, title = tmp_path / "read-first-body.md", tmp_path / "read-first-title.txt"
    body.write_text(text, encoding="utf-8", newline="\n")
    title.write_text("tools: Add a section lookup\n", encoding="utf-8", newline="\n")
    return body, title


def test_a_read_first_section_only_the_branch_has_is_refused(workspace, tmp_path, capsys):
    kit = read_first_branch(workspace)
    body, title = read_first_body(tmp_path, "studio/new.md#fresh", "studio/new.md#fresh")
    code, err = run_gds(["pr", "check-body", str(body), "--title", str(title), "--repo", str(kit)], capsys)
    assert code == 1 and "do not exist" in err and "studio/new.md#fresh" in err and "origin/main" in err


def test_a_read_first_section_on_main_and_a_lessons_section_the_branch_adds_pass(workspace, tmp_path, capsys):
    kit = read_first_branch(workspace)
    body, title = read_first_body(tmp_path, "studio/hooks.md#docs", "studio/new.md#fresh")
    code, err = run_gds(["pr", "check-body", str(body), "--title", str(title), "--repo", str(kit)], capsys)
    assert code == 0, err


def test_a_read_first_section_the_branch_removes_still_counts(workspace, tmp_path, capsys):
    kit = read_first_branch(workspace)
    (kit / "docs" / "studio" / "hooks.md").unlink()  # the author read it on main; the branch may move it
    body, title = read_first_body(tmp_path, "studio/hooks.md#docs", "studio/new.md#fresh")
    code, err = run_gds(["pr", "check-body", str(body), "--title", str(title), "--repo", str(kit)], capsys)
    assert code == 0, err


def test_the_guard_refuses_a_read_first_section_only_the_branch_has(workspace, tmp_path):
    kit = read_first_branch(workspace)
    body, _ = read_first_body(tmp_path, "studio/new.md#fresh", "studio/new.md#fresh")
    command = f'gh pr create --title "tools: Add a section lookup" --body-file {body}'
    assert "studio/new.md#fresh" in denied(shell(command, kit))
    ok, _ = read_first_body(tmp_path, "studio/hooks.md#docs", "studio/new.md#fresh")
    assert denied(shell(f'gh pr create --title "tools: Add a section lookup" --body-file {ok}', kit)) == ""
