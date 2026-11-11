"""The red-main guard (docs/studio/hooks-red-main.md#red-main): while an issue titled `CI failing on the default
branch` is open in a repository, no merge command lands a pull request there, except the fix forward, whose body says
`Fixes #<that issue>`. Merging main into a branch is not a merge command and stays allowed. GitHub's answer decides;
when it cannot be asked the call goes through with a warning."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from hook_support import REAL_RED_MAIN, denied, guards, patch

RED = (1230, "CI failing on the default branch: ci")
FIX_FORWARD = "## Summary\n\nThe flake fixed.\n\nFixes #1230\n"
FEATURE = "## Summary\n\nA minimap.\n\nFixes #1101\n"


@pytest.fixture()
def gh(monkeypatch):
    """`gh` with no network: o/r has issue 1230 open (red main), o/green has none; pull request 12 is a feature, 13 the
    fix forward; any call naming o/down fails. Records every command."""
    seen: list[list[str]] = []
    state = {"open": {"o/r": [RED], "o/green": []}}

    def fake(command, cwd, what):
        seen.append(command)
        text = " ".join(command)
        if "o/down" in text:
            raise LookupError(f"{what} failed: no network")
        if command[1:3] == ["issue", "list"]:
            repo = command[command.index("-R") + 1]
            return "\n".join(f"{n}\t{title}" for n, title in state["open"][repo])
        if command[1:3] == ["pr", "view"]:
            number = next((w for w in command[3:] if w.isdigit()), "12")
            repo = command[command.index("-R") + 1] if "-R" in command else "o/r"
            body = FIX_FORWARD if number == "13" else FEATURE
            return json.dumps({"number": int(number), "url": f"https://github.com/{repo}/pull/{number}", "body": body})
        raise AssertionError(f"unexpected gh call: {command}")

    patch(monkeypatch, "red_main", REAL_RED_MAIN)
    patch(monkeypatch, "gh_text", fake)
    guards.take_warnings()
    return seen, state


def refused(command: str, cwd: Path) -> str:
    return " ".join(reason for words in guards.segments(command) for reason in guards.check_red_main(words, cwd))


# --- refused while main is red ---


@pytest.mark.parametrize(
    "command",
    [
        "gh pr merge 12 --squash -R o/r",
        "gh pr merge 12 --squash --auto -R o/r",  # auto-merge would land it the moment its checks pass
        "gh pr merge --repo o/r --auto --squash 12",
        "gh pr merge 12",  # the repository read from the pull request's address
        "gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=squash -f sha=abc",
        "gh api --method PUT /repos/o/r/pulls/12/merge",
        "gh api repos/o/r/pulls/12/merge -f merge_method=squash",
    ],
)
def test_a_merge_while_main_is_red_is_refused(command, gh, tmp_path):
    text = refused(command, tmp_path)
    assert "o/r#1230" in text and "CI failing on the default branch: ci" in text
    assert "studio/starting-work.md#landing" in text
    assert "Fixes #1230" in text  # how the fix forward is told apart


def test_the_refusal_comes_through_the_hook(gh, tmp_path):
    payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": str(tmp_path)}
    text = denied({**payload, "tool_input": {"command": "gh api -X PUT repos/o/r/pulls/12/merge -f sha=abc"}})
    assert "o/r#1230" in text


def test_every_open_red_issue_is_named(gh, tmp_path):
    gh[1]["open"]["o/r"] = [RED, (1240, "CI failing on the default branch: docs")]
    text = refused("gh pr merge 12 -R o/r", tmp_path)
    assert "o/r#1230" in text and "o/r#1240" in text


# --- allowed ---


@pytest.mark.parametrize(
    "command",
    [
        "gh pr merge 13 --squash -R o/r",
        "gh pr merge 13 --auto --squash -R o/r",
        "gh api -X PUT repos/o/r/pulls/13/merge",
    ],
)
def test_the_fix_forward_lands(command, gh, tmp_path):
    assert refused(command, tmp_path) == ""
    assert guards.take_warnings() == []


def test_a_merge_while_main_is_green_passes_on_one_call(gh, tmp_path):
    assert refused("gh api -X PUT repos/o/green/pulls/12/merge", tmp_path) == ""
    assert [c[1:3] for c in gh[0]] == [["issue", "list"]]  # the body is read only when main is red


def test_an_issue_with_another_title_is_not_red_main(gh, tmp_path):
    gh[1]["open"]["o/green"] = [(5, "CI failing on a branch: ci"), (6, "ci: Fix the CI failing on the default page")]
    assert refused("gh pr merge 12 -R o/green", tmp_path) == ""


@pytest.mark.parametrize(
    "command",
    [
        "gh pr merge 12 --disable-auto -R o/r",  # turning auto-merge off is always allowed
        "gh api repos/o/r/pulls/12/merge",  # a read: has it merged?
        "gh api -X GET repos/o/r/pulls/12/merge",
        "gh pr view 12 -R o/r",
        "gh pr checks 12 -R o/r",
        "git merge origin/main",  # merging main into a branch
        "uv run --project python gds merge-main --path .",
    ],
)
def test_nothing_else_is_judged(command, gh, tmp_path):
    assert refused(command, tmp_path) == ""
    assert gh[0] == []


def test_a_github_failure_warns_and_lets_the_merge_through(gh, tmp_path):
    assert refused("gh pr merge 12 -R o/down", tmp_path) == ""
    warnings = " ".join(guards.take_warnings())
    assert "could not check" in warnings and "CI failing on the default branch" in warnings


# --- which bodies fix the red issue ---


@pytest.mark.parametrize(
    "body",
    ["Fixes #1230", "fixes: #1230", "Closes #1230", "Resolved #1230", "Fixes o/r#1230", "- Fixes #1230"],
)
def test_a_closing_keyword_names_the_issue(body):
    assert 1230 in guards.fixed_issues(body, "o/r")


@pytest.mark.parametrize(
    "body",
    ["Refs #1230", "Fixes #12300", "Fixes o/other#1230", "Fixes #123", "Fixes #1101 after #1230 lands"],
)
def test_a_mention_is_not_a_fix(body):
    assert 1230 not in guards.fixed_issues(body, "o/r")
