"""`gds pr check-body` and the guard that refuses `gh pr create|edit` with a body `pr-rules` would refuse: both run
`groundwork.py check-body` (the function CI uses) in the checkout of the repository the pull request is for. The bodies
in fixtures/pr_bodies are the forms that failed after a push on 2026-11-02 (a `None` line without a reason, text after
the reason, a trailing full stop) and the other body rules; throwaway repositories stand for the kit and for a game
whose conventions differ."""

from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

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

from gds_tools import cli  # noqa: E402

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


@pytest.fixture()
def workspace(tmp_path: Path) -> dict[str, Path]:
    root = tmp_path / "ws"
    (root / "repos").mkdir(parents=True)
    (root / ".gdstudio-workspace").write_text("", encoding="utf-8")
    kit = make_repo(root / "repos" / "gdstudio", "https://github.com/Ryubara/gdstudio.git")
    game = make_repo(root / "repos" / "deadnight", "https://github.com/Ryubara/deadnight.git", game_conventions())
    return {"root": root, "kit": kit, "game": game}


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
    assert denied(shell(f"gh pr comment 7 --body-file {bad}", kit)) == ""
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
    monkeypatch.setattr(guards, "body_of", lambda words, cwd: reads.append(1) or real(words, cwd))
    body = BODIES / "none-without-reason.txt"
    reason = denied(shell(f"gh pr edit 7 --body-file {body} --attach {workspace['root']}/after.png", workspace["kit"]))
    assert REASON_NONE in reason and "has no reference" in reason
    assert len(reads) == 1
