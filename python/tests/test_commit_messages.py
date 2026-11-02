"""The commit message checks: the `commit-msg` hook, the `pre-push` hook and the `commits` check of CI are one set of
functions in .github/scripts/groundwork.py, and they judge the message as it is stored (kit issue #107)."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

KIT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("groundwork_messages", KIT / ".github" / "scripts" / "groundwork.py")
groundwork = importlib.util.module_from_spec(_spec)
sys.modules["groundwork_messages"] = groundwork
_spec.loader.exec_module(groundwork)

CONV = groundwork.load(KIT / ".github" / "conventions.yml")
TRAILER = "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
CLEAN = f"tools: Add a thing\n\nWhy.\n\n{TRAILER}\n"
# What `git merge -m <message>` then `git commit --no-edit` stores after a conflict (deadnight #503).
CONFLICTED = f"Merge origin/main into a-branch\n\n{TRAILER}\n\n# Conflicts:\n#\tpath/to/file.gd\n"
# What the editor gives the commit-msg hook: the message, then git's help text.
EDITOR = (
    f"{CLEAN}\n# Please enter the commit message for your changes. Lines starting\n# with '#' will be ignored.\n#\n"
)


def ci(message: str) -> list[str]:
    """What the `commits` check of CI says about a stored message."""
    return groundwork.commits_problems(CONV, [("a" * 40, message)], None)


def hook(message: str) -> list[str]:
    """What the commit-msg hook says about the file it is given."""
    return groundwork.commit_problems(CONV, groundwork.stored_message(message))


def test_a_clean_message_passes_everywhere():
    assert ci(CLEAN) == [] and hook(CLEAN) == []


def test_the_conflicts_paragraph_fails_the_hook_exactly_as_it_fails_ci():
    """The bug: the hook dropped every '#' line and passed what CI refused."""
    assert ci(CONFLICTED) and hook(CONFLICTED) == [p.split(": ", 1)[1] for p in ci(CONFLICTED)]
    assert any("paragraph of '#' lines" in p for p in hook(CONFLICTED))


def test_the_editors_help_text_is_not_part_of_the_message():
    assert hook(EDITOR) == []
    verbose = f"{CLEAN}\n# ------------------------ >8 ------------------------\ndiff --git a/f b/f\n+x\n"
    assert hook(verbose) == []


def test_a_hash_line_in_an_editor_message_is_stripped_like_git_does():
    typed = f"tools: Add a thing\n\n# a note to self\n\n{TRAILER}\n\n# Please enter the commit message for you\n"
    assert hook(typed) == []


def test_the_trailer_must_still_be_last():
    assert hook(f"{CLEAN}\nA closing remark.\n") != []


def git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), "-c", "user.email=a@example.org", "-c", "user.name=t", *args],
        capture_output=True,
        text=True,
        check=check,
    )


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    path = tmp_path / "repo"
    path.mkdir()
    git(path, "init", "-q", "-b", "main")
    (path / "f").write_text("base\n", encoding="utf-8")
    git(path, "add", "f")
    git(path, "commit", "-q", "-m", "build: Add a file")
    return path


def commit(repo: Path, message: str, *flags: str) -> None:
    """Commit the staged work with the message in a file, as the agents do."""
    (repo.parent / "msg.txt").write_text(message, encoding="utf-8", newline="\n")
    git(repo, "commit", "-q", "-F", str(repo.parent / "msg.txt"), *flags)


def conflicted_merge(repo: Path) -> None:
    """A real merge with a conflict, committed with `git merge -m` then `git commit --no-edit`."""
    git(repo, "checkout", "-q", "-b", "side")
    (repo / "f").write_text("side\n", encoding="utf-8")
    git(repo, "commit", "-q", "-am", "build: Update the side")
    git(repo, "checkout", "-q", "main")
    (repo / "f").write_text("main\n", encoding="utf-8")
    git(repo, "commit", "-q", "-am", "build: Update main")
    git(repo, "checkout", "-q", "-b", "work", "side")
    merged = git(repo, "merge", "-m", f"Merge main\n\n{TRAILER}", "main", check=False)
    assert merged.returncode != 0
    (repo / "f").write_text("resolved\n", encoding="utf-8")
    git(repo, "add", "f")
    git(repo, "commit", "--no-edit", "-q")


CONV_PATH = str(KIT / ".github" / "conventions.yml")


def push_check(*args: str) -> int:
    return groundwork.main(["--conventions", CONV_PATH, "check-push", *args])


def test_a_real_merge_committed_with_no_edit_is_refused_before_the_push(repo, monkeypatch, capsys):
    conflicted_merge(repo)
    stored = git(repo, "log", "-1", "--format=%B").stdout
    assert "# Conflicts:" in stored  # git keeps it with --no-edit: the stored message is what CI sees
    assert ci(stored) != []
    monkeypatch.chdir(repo)
    assert push_check("--range", "main..work") == 1
    err = capsys.readouterr().err
    assert "paragraph of '#' lines" in err and "git commit --amend" in err and "no force push is needed" in err


def test_the_amended_merge_passes_the_push_check(repo, monkeypatch, capsys):
    conflicted_merge(repo)
    git(repo, "commit", "--amend", "-q", "--cleanup=strip", "-m", f"Merge origin/main into work\n\n{TRAILER}")
    monkeypatch.chdir(repo)
    assert push_check("--range", "main..work") == 0, capsys.readouterr().err


def test_the_push_check_reads_pre_commits_range_and_skips_a_deletion(repo, monkeypatch, capsys):
    def head() -> str:
        return git(repo, "rev-parse", "HEAD").stdout.strip()

    base = head()
    (repo / "f").write_text("more\n", encoding="utf-8")
    git(repo, "add", "f")
    commit(repo, "tools: Add a thing\n\nNo trailer here.\n")
    monkeypatch.setenv("PRE_COMMIT_FROM_REF", base)
    monkeypatch.setenv("PRE_COMMIT_TO_REF", head())
    monkeypatch.chdir(repo)
    assert push_check() == 0  # no trailer is required, only a correct one
    (repo / "f").write_text("again\n", encoding="utf-8")
    git(repo, "add", "f")
    commit(repo, f"whatever I like\n\n{TRAILER}\n")
    monkeypatch.setenv("PRE_COMMIT_TO_REF", head())
    assert push_check() == 1
    assert "whatever I like" in capsys.readouterr().err
    monkeypatch.setenv("PRE_COMMIT_TO_REF", "0" * 40)  # deleting a branch pushes no commits
    assert push_check() == 0


def test_the_commits_a_merge_of_main_brings_are_not_judged_again(repo, monkeypatch, capsys):
    """Main's squash commits end in ` (#N)` and may pass 72 characters; they are main's, not the push's."""
    git(repo, "checkout", "-q", "-b", "work")
    (repo / "g").write_text("work\n", encoding="utf-8")
    git(repo, "add", "g")
    commit(repo, f"tools: Add a thing\n\n{TRAILER}\n")
    remote_tip = git(repo, "rev-parse", "HEAD").stdout.strip()
    git(repo, "checkout", "-q", "main")
    (repo / "h").write_text("main\n", encoding="utf-8")
    git(repo, "add", "h")
    commit(repo, f"hooks: Add a stop check for task agents that end before their report (#155)\n\n{TRAILER}\n")
    git(repo, "update-ref", "refs/remotes/origin/main", "main")
    git(repo, "checkout", "-q", "work")
    git(repo, "merge", "-q", "--no-ff", "-m", f"Merge origin/main into work\n\n{TRAILER}", "main")
    monkeypatch.setenv("PRE_COMMIT_FROM_REF", remote_tip)
    monkeypatch.setenv("PRE_COMMIT_TO_REF", git(repo, "rev-parse", "HEAD").stdout.strip())
    monkeypatch.chdir(repo)
    assert push_check() == 0, capsys.readouterr().err
    git(repo, "update-ref", "-d", "refs/remotes/origin/main")  # without origin/main the same push is judged in full
    assert push_check() == 1
    assert "at most 72" in capsys.readouterr().err
