"""The merge guard of the hooks (docs/studio/hooks.md#behind): a merge command on a pull request whose head lacks the
tip of its base branch is refused, and the refusal names the missing commits and the command to run. The answer comes
from GitHub's compare API, never the local clone; a GitHub failure lets the call through with a visible warning."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest
from hook_support import patch

KIT = Path(__file__).resolve().parents[2]
HOOKS = KIT / ".claude" / "hooks"
sys.path.insert(0, str(HOOKS))
_spec = importlib.util.spec_from_file_location("dispatch", HOOKS / "dispatch.py")
dispatch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dispatch)
guards = dispatch.guards

HEAD = "cafe" * 10
MISSING = ["a1b2c3d4e feat: Add the minimap", "f5e6d7c8b docs: Update the loop"]


def info(behind_by: int = 2, commits=None, number: int = 12, repo: str = "o/r", branch: str = "feature") -> dict:
    return {
        "repo": repo,
        "number": number,
        "base": "main",
        "branch": branch,
        "behind_by": behind_by,
        "commits": MISSING[:behind_by] if commits is None else commits,
    }


@pytest.fixture()
def asked(monkeypatch):
    """`behind` with no network: pull request 12 is two commits behind, 13 contains main, 14 cannot be read."""
    seen: list[tuple] = []

    def fake(target, repo, cwd):
        seen.append((target, repo))
        if str(target) == "14":
            return None, "gh pr view failed: no network"
        return (info(0) if str(target) == "13" else info()), ""

    patch(monkeypatch, "behind", fake)
    patch(monkeypatch, "red_main", lambda target, repo, cwd: ({"open": [], "fixes": False}, ""))  # main is green
    guards.take_warnings()
    return seen


def refused(command: str, tmp_path: Path) -> str:
    return " ".join(reason for words in guards.segments(command) for reason in guards.check_behind(words, tmp_path))


# --- the refusal ---


@pytest.mark.parametrize(
    "command",
    [
        "gh pr merge 12 --squash",
        "gh pr merge 12 --squash --auto",  # auto-merge lands it later, still behind
        "gh pr merge --auto --squash 12",
        "gh pr merge -R o/r 12 --squash",
        "gh.exe pr merge 12",
        "gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=squash",
        "gh api --method PUT /repos/o/r/pulls/12/merge",
        "gh api repos/o/r/pulls/12/merge -f merge_method=squash",
    ],
)
def test_a_merge_of_a_pull_request_behind_its_base_is_refused(command, asked, tmp_path):
    text = refused(command, tmp_path)
    assert "2 commits behind main" in text
    assert "a1b2c3d4e feat: Add the minimap" in text and "f5e6d7c8b docs: Update the loop" in text
    assert "gds merge-main --path" in text


def test_a_pull_request_that_contains_the_tip_of_its_base_passes(asked, tmp_path):
    assert refused("gh pr merge 13 --squash", tmp_path) == ""
    assert refused("gh api -X PUT repos/o/r/pulls/13/merge", tmp_path) == ""
    assert guards.take_warnings() == []


@pytest.mark.parametrize(
    "command",
    [
        "gh pr merge 12 --disable-auto",  # turning auto-merge off is always allowed
        "gh api repos/o/r/pulls/12/merge",  # a read: has it merged?
        "gh api -X GET repos/o/r/pulls/12/merge",
        "gh pr view 12",
        "gh pr edit 12 --title x",
        "gh pr checks 12",
        "git merge main",
    ],
)
def test_nothing_else_asks_github(command, asked, tmp_path):
    assert refused(command, tmp_path) == ""
    assert asked == []


def test_one_commit_is_singular_and_a_long_list_is_cut(monkeypatch, tmp_path):
    many = [f"{i:09x} commit {i}" for i in range(12)]
    patch(monkeypatch, "behind", lambda *a: (info(12, many), ""))
    text = refused("gh pr merge 12", tmp_path)
    assert "12 commits behind main" in text and "commit 4" in text and "commit 5" not in text and "7 more" in text
    patch(monkeypatch, "behind", lambda *a: (info(1), ""))
    assert "1 commit behind main" in refused("gh pr merge 12", tmp_path)


def test_the_repository_named_is_the_one_asked(asked, tmp_path):
    refused("gh pr merge --repo o/deadnight 12 --squash", tmp_path)
    refused("gh api -X PUT repos/o/deadnight/pulls/13/merge", tmp_path)
    assert asked == [("12", "o/deadnight"), ("13", "o/deadnight")]


def test_the_current_branchs_pull_request_is_looked_up(asked, tmp_path):
    refused("gh pr merge --squash --auto", tmp_path)
    assert asked == [("", None)]


def test_the_refusal_reaches_a_session_beside_the_hold(asked, monkeypatch, tmp_path):
    patch(monkeypatch, "held", lambda target, repo, cwd: True)
    payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": str(tmp_path)}
    payload["tool_input"] = {"command": "gh pr merge 12 --squash --auto"}
    out = dispatch.answer(payload, dispatch.load_config(None))
    reason = out["hookSpecificOutput"]["permissionDecisionReason"]
    assert out["hookSpecificOutput"]["permissionDecision"] == "deny"
    assert "a maintainer holds it" in reason and "2 commits behind main" in reason


# --- a GitHub failure fails open, visibly ---


def test_a_failed_lookup_lets_the_call_through_with_a_warning(asked, tmp_path):
    assert refused("gh pr merge 14 --squash", tmp_path) == ""
    warnings = guards.take_warnings()
    assert len(warnings) == 1 and "could not check" in warnings[0] and "no network" in warnings[0]
    assert guards.take_warnings() == []  # taken once


def test_the_warning_reaches_a_session_and_nothing_is_denied(asked, monkeypatch, tmp_path):
    patch(monkeypatch, "held", lambda target, repo, cwd: False)
    payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": str(tmp_path)}
    payload["tool_input"] = {"command": "gh pr merge 14 --squash"}
    out = dispatch.answer(payload, dispatch.load_config(None))
    assert "permissionDecision" not in out.get("hookSpecificOutput", {})
    assert "could not check" in out["systemMessage"]
    assert "could not check" in out["hookSpecificOutput"]["additionalContext"]


def test_a_clean_call_has_no_answer(asked, monkeypatch, tmp_path):
    patch(monkeypatch, "held", lambda target, repo, cwd: False)
    payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": str(tmp_path)}
    payload["tool_input"] = {"command": "gh pr merge 13 --squash"}
    assert dispatch.answer(payload, dispatch.load_config(None)) is None


# --- behind(): what is asked of GitHub ---


class FakeGh:
    """`gh` for `behind`: answers `pr view` and the two compare calls from a script; records every command."""

    def __init__(self, behind_by=2, view=None, fail=(), junk=()):
        self.behind_by, self.fail, self.junk, self.commands = behind_by, set(fail), set(junk), []
        self.view = view or {
            "number": 12,
            "baseRefName": "main",
            "headRefName": "feature",
            "headRefOid": HEAD,
            "url": "https://github.com/o/r/pull/12",
        }

    def __call__(self, command, **kwargs):
        self.commands.append(command)
        if command[:3] == ["gh", "pr", "view"]:
            key, out = "view", json.dumps(self.view)
        else:
            endpoint = next(word for word in command if word.startswith("repos/"))
            key = "behind" if endpoint.endswith(f"...{HEAD}") else "missing"
            out = str(self.behind_by) if key == "behind" else "\n".join(MISSING[: self.behind_by])
        if key in self.fail:
            return subprocess.CompletedProcess(command, 1, "", f"{key} failed: HTTP 502")
        return subprocess.CompletedProcess(command, 0, "not json{" if key in self.junk else out, "")


def run_behind(monkeypatch, tmp_path, gh, target="12", repo="o/r"):
    monkeypatch.setattr(guards.subprocess, "run", gh)
    return guards.behind(target, repo, tmp_path)


def test_behind_compares_the_head_with_its_base_on_github(monkeypatch, tmp_path):
    gh = FakeGh()
    found, error = run_behind(monkeypatch, tmp_path, gh)
    assert error == ""
    assert found == info(2, MISSING)
    assert gh.commands[0][:6] == ["gh", "pr", "view", "12", "-R", "o/r"]
    paths = [next(w for w in c if w.startswith("repos/")) for c in gh.commands[1:]]
    assert paths == [f"repos/o/r/compare/main...{HEAD}", f"repos/o/r/compare/{HEAD}...main"]


def test_behind_asks_for_the_missing_commits_only_when_there_are_some(monkeypatch, tmp_path):
    gh = FakeGh(behind_by=0)
    found, error = run_behind(monkeypatch, tmp_path, gh)
    assert error == "" and found["behind_by"] == 0 and found["commits"] == []
    assert len(gh.commands) == 2


def test_the_repository_comes_from_the_pull_request_when_none_is_named(monkeypatch, tmp_path):
    gh = FakeGh()
    found, _ = run_behind(monkeypatch, tmp_path, gh, target="", repo=None)
    assert found["repo"] == "o/r" and gh.commands[0][:3] == ["gh", "pr", "view"] and "-R" not in gh.commands[0]


def test_a_missing_commit_list_still_refuses_with_the_count(monkeypatch, tmp_path):
    found, error = run_behind(monkeypatch, tmp_path, FakeGh(fail=("missing",)))
    assert error == "" and found["behind_by"] == 2 and found["commits"] == []


def test_a_count_without_commits_is_still_a_refusal(monkeypatch, tmp_path):
    patch(monkeypatch, "behind", lambda *a: (info(2, []), ""))
    text = refused("gh pr merge 12", tmp_path)
    assert "2 commits behind main" in text and "missing:" not in text


@pytest.mark.parametrize(
    ("gh", "why"),
    [
        (FakeGh(fail=("view",)), "pull request"),
        (FakeGh(fail=("behind",)), "compare"),
        (FakeGh(junk=("view",)), "pull request"),
        (FakeGh(junk=("behind",)), "compare"),
        (FakeGh(view={"number": 12}), "pull request"),
    ],
)
def test_behind_says_why_it_could_not_tell(monkeypatch, tmp_path, gh, why):
    found, error = run_behind(monkeypatch, tmp_path, gh)
    assert found is None and why in error


def test_behind_survives_a_missing_gh(monkeypatch, tmp_path):
    def run(command, **kwargs):
        raise OSError("no gh")

    found, error = run_behind(monkeypatch, tmp_path, run)
    assert found is None and "no gh" in error


def test_behind_survives_a_timeout(monkeypatch, tmp_path):
    def run(command, **kwargs):
        raise subprocess.TimeoutExpired(command, 20)

    found, error = run_behind(monkeypatch, tmp_path, run)
    assert found is None and "timed out" in error


# --- the command to run ---


def git(path: Path, *args: str) -> str:
    out = subprocess.run(["git", "-C", str(path), *args], check=True, capture_output=True, text=True)
    return out.stdout.strip()


@pytest.fixture()
def tree(tmp_path):
    main = tmp_path / "repos" / "game"
    main.mkdir(parents=True)
    git(main, "init", "-q", "-b", "main")
    git(main, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init")
    other = tmp_path / "worktrees" / "game" / "feature"
    git(main, "worktree", "add", "-q", "-b", "feature", str(other))
    return main, other


def test_the_worktree_of_a_branch_is_found_from_any_checkout(tree):
    main, other = tree
    assert guards.worktree_of("feature", main) == other.resolve()
    assert guards.worktree_of("feature", other) == other.resolve()
    assert guards.worktree_of("missing", main) is None
    assert guards.worktree_of("feature", main / "nowhere") is None


def test_the_refusal_names_the_worktree_and_the_kit_command(tree, tmp_path, monkeypatch):
    main, other = tree
    (tmp_path / guards.MARKER).write_text("")
    patch(monkeypatch, "behind", lambda *a: (info(), ""))
    text = refused("gh pr merge 12 --squash", main)
    assert f"gds merge-main --path {other.resolve().as_posix()}" in text
    assert f"uv run --project {(tmp_path / 'repos' / 'gdstudio' / 'python').as_posix()} gds merge-main" in text
    patch(monkeypatch, "behind", lambda *a: (info(branch="unknown"), ""))
    assert "gds merge-main --path <worktree>" in refused("gh pr merge 12 --squash", main)
