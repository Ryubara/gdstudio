"""The merge-result check (.github/scripts/merge_result.py, docs/studio/ci.md#merge-result): two branches that each
stay under a limit and together go over it are refused on the merge, while each alone passes.

The repository is a small one made here with the kit's own `mistakes.py` and `lessons.py`, so the limit is the real
page limit (50 KB) and nothing is downloaded: pre-commit (gdlint's max-file-lines) is left out, and its dry run is in
the pull request that added the check (gdstudio #1468).
"""

from __future__ import annotations

import importlib.util
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

KIT = Path(__file__).resolve().parents[2]
SCRIPT = KIT / ".github" / "scripts" / "merge_result.py"
PAGE = Path("docs/studio/page.md")

spec = importlib.util.spec_from_file_location("merge_result", SCRIPT)
merge_result = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = merge_result  # dataclasses look their module up there
spec.loader.exec_module(merge_result)


def git(repo: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(repo), "-c", "core.autocrlf=false", *args],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
        env={**merge_result.os.environ, **merge_result.IDENTITY},
    ).stdout.strip()


def filler(label: str, kilobytes: int) -> str:
    line = f"Text that {label} adds to the page, long enough to fill it at a steady rate of bytes per line.\n"
    return line * (kilobytes * 1024 // len(line) + 1)


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    root = tmp_path / "repo"
    for path in (
        ".github/scripts/mistakes.py",
        "python/src/gds_tools/__init__.py",
        "python/src/gds_tools/lessons.py",
    ):
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(KIT / path, root / path)
    (root / PAGE).parent.mkdir(parents=True)
    (root / PAGE).write_text(
        "# A page\n\nThe start.\n\n## The topic {#topic}\n\n" + filler("main", 28) + "\nThe end.\n",
        encoding="utf-8",
        newline="\n",
    )
    git(root.parent, "init", "-q", "-b", "main", str(root))
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "start")
    return root


def branch(repo: Path, name: str, before: str, text: str) -> None:
    """A branch off main that puts `text` in front of the line `before`."""
    git(repo, "checkout", "-q", "-b", name, "main")
    page = repo / PAGE
    page.write_text(page.read_text(encoding="utf-8").replace(before, text + before, 1), encoding="utf-8", newline="\n")
    git(repo, "commit", "-q", "-am", name)
    git(repo, "checkout", "-q", "main")


def size_kb(repo: Path, ref: str) -> float:
    return len(git(repo, "show", f"{ref}:{PAGE.as_posix()}").encode("utf-8")) / 1024


def test_two_branches_each_under_the_page_limit_are_refused_together(repo: Path):
    # Each branch adds 14 KB to a 28 KB page: 42 KB alone, 56 KB together, the limit is 50 KB.
    branch(repo, "a", "The start.", filler("branch a", 14))
    branch(repo, "b", "The end.", filler("branch b", 14))
    assert size_kb(repo, "a") < 50 and size_kb(repo, "b") < 50

    alone_a = merge_result.merge_result(repo, "main", "a", pre_commit=False)
    alone_b = merge_result.merge_result(repo, "main", "b", pre_commit=False)
    assert alone_a.ok, alone_a.summary()
    assert alone_b.ok, alone_b.summary()

    # a lands; b is still green on the old main, and its merge with the new one goes over.
    git(repo, "merge", "-q", "--ff-only", "a")
    together = merge_result.merge_result(repo, "main", "b", pre_commit=False)
    assert not together.ok
    assert together.conflicts == []
    summary = together.summary()
    assert "FAIL: page sizes" in summary
    assert "docs/studio/page.md" in summary and "over the 50 KB limit" in summary


def test_a_conflict_is_refused_and_names_the_file(repo: Path):
    branch(repo, "a", "The end.", "Branch a's ending.\n")
    branch(repo, "b", "The end.", "Branch b's ending.\n")
    git(repo, "merge", "-q", "--ff-only", "a")
    result = merge_result.merge_result(repo, "main", "b", pre_commit=False)
    assert not result.ok
    assert result.conflicts == [PAGE.as_posix()]
    assert "gds merge-main" in result.summary()


def test_the_command_exits_one_on_failure_writes_the_summary_and_leaves_no_worktree(repo: Path, tmp_path: Path):
    branch(repo, "a", "The start.", filler("branch a", 14))
    branch(repo, "b", "The end.", filler("branch b", 14))
    git(repo, "merge", "-q", "--ff-only", "a")
    report = tmp_path / "summary.md"
    head = git(repo, "rev-parse", "HEAD")
    code = merge_result.main(
        ["--repo", str(repo), "--base", "main", "--head", "b", "--summary", str(report), "--no-pre-commit"]
    )
    assert code == 1
    assert "FAIL: page sizes" in report.read_text(encoding="utf-8")
    # The checkout is as it was: same commit, clean, and the throwaway worktree is gone.
    assert git(repo, "rev-parse", "HEAD") == head
    assert git(repo, "status", "--porcelain") == ""
    assert len(git(repo, "worktree", "list").splitlines()) == 1
    assert merge_result.main(["--repo", str(repo), "--base", "main", "--head", "nowhere"]) == 2
