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


def pull_request(repo: Path, number: int, name: str) -> dict:
    """Publish branch `name` as pull request `number` (`refs/pull/<n>/head`, as GitHub keeps it) and list it."""
    sha = git(repo, "rev-parse", name)
    git(repo, "update-ref", f"refs/pull/{number}/head", sha)
    return {"number": number, "sha": sha}


def test_the_sweep_answers_each_pull_request_and_one_conflict_stops_none(repo: Path, tmp_path: Path):
    # The fault of gdstudio #1512: the sweep was a bash loop under `bash -e`, so #1447's conflict ended the job and
    # every pull request, those whose merge printed success included, was marked failed.
    git(repo, "remote", "add", "origin", str(repo))  # GitHub's refs/pull/<n>/head, fetched as the sweep does
    branch(repo, "landed", "The end.", "The ending that landed.\n")
    branch(repo, "clean-one", "The start.", "A clean change.\n")
    branch(repo, "conflict", "The end.", "Another ending.\n")
    branch(repo, "over", "The start.", filler("over", 23))
    branch(repo, "clean-two", "The start.", "Another clean change.\n")
    branch(repo, "pushed", "The start.", "A change pushed again after the list was read.\n")
    git(repo, "merge", "-q", "--ff-only", "landed")
    prs = [
        pull_request(repo, 1, "clean-one"),
        pull_request(repo, 2, "conflict"),
        pull_request(repo, 3, "over"),
        pull_request(repo, 4, "clean-two"),
        {**pull_request(repo, 5, "pushed"), "sha": git(repo, "rev-parse", "clean-one")},
        {"number": 6, "sha": "0" * 40},  # no refs/pull/6/head: closed, or the fetch failed
    ]
    listed = tmp_path / "prs.json"
    listed.write_text(merge_result.json.dumps(prs), encoding="utf-8")
    out = tmp_path / "results.json"

    code = merge_result.main(
        ["--repo", str(repo), "--base", "main", "--sweep", str(listed), "--results", str(out), "--no-pre-commit"]
    )

    assert code == 0
    results = {row["number"]: row for row in merge_result.json.loads(out.read_text(encoding="utf-8"))}
    assert [results[n]["conclusion"] for n in range(1, 7)] == [
        "success",
        "failure",
        "failure",
        "success",
        "skip",
        "failure",
    ]
    assert all(results[n]["sha"] == prs[n - 1]["sha"] for n in results)
    assert "pass: page sizes" in results[1]["summary"] and "pass: page sizes" in results[4]["summary"]
    assert "The merge conflicts" in results[2]["summary"] and f"`{PAGE.as_posix()}`" in results[2]["summary"]
    assert "FAIL: page sizes" in results[3]["summary"] and "over the 50 KB limit" in results[3]["summary"]
    assert "could not fetch #6" in results[6]["summary"]
    assert git(repo, "status", "--porcelain") == ""
    assert len(git(repo, "worktree", "list").splitlines()) == 1


@pytest.mark.parametrize(
    "rows",
    [
        {"number": 1},
        [{"number": "1", "sha": "a" * 40}],
        [{"number": 1, "sha": "main"}],
        [{"number": True, "sha": "a" * 40}],
    ],
)
def test_the_sweep_refuses_a_malformed_list(repo: Path, tmp_path: Path, rows):
    listed = tmp_path / "prs.json"
    listed.write_text(merge_result.json.dumps(rows), encoding="utf-8")
    out = tmp_path / "results.json"
    assert merge_result.main(["--repo", str(repo), "--sweep", str(listed), "--results", str(out)]) == 2
    assert not out.exists()
