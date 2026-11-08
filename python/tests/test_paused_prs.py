"""A paused repository's pull requests are left alone: `gds merge-main`, `gds pr hold` and `gds pr check-body` refuse
one with the pause's reason, and pass for a repository that is not paused (docs/studio/starting-work.md#paused)."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from gds_tools import cli, issues, pr, worktrees

PAUSE = "by the maintainer on 2026-11-07, for kit work first"
BODY = Path(__file__).parent / "fixtures" / "pr_bodies" / "good.txt"


def git(*args: str, cwd: Path) -> None:
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True)


def checkout(path: Path, url: str) -> Path:
    path.mkdir(parents=True)
    git("init", "-q", "-b", "work", cwd=path)
    git("remote", "add", "origin", url, cwd=path)
    return path


@pytest.fixture()
def kit(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """A kit whose workspace.toml pauses Ryubara/deadnight and not Ryubara/live, used by every gds command here."""
    folder = tmp_path / "kit"
    folder.mkdir()
    (folder / "workspace.toml").write_text(
        '[repos.deadnight]\nurl = "https://github.com/Ryubara/deadnight.git"\n'
        f'paused = "{PAUSE}"\n'
        '[repos.live]\nurl = "https://github.com/Ryubara/live.git"\n',
        encoding="utf-8",
    )
    monkeypatch.setattr(cli.workspace, "kit_checkout", lambda: folder)
    return folder


@pytest.fixture()
def calls(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    """The work the commands would do, recorded instead of done."""
    done: list[str] = []
    monkeypatch.setattr(worktrees, "merge_main", lambda path, **_: done.append(f"merge {path.name}") or ["merged"])
    monkeypatch.setattr(pr, "hold", lambda repo, number, **_: done.append(f"hold {repo}#{number}") or ["held"])
    return done


def refusal(argv: list[str], capsys: pytest.CaptureFixture[str]) -> str:
    assert cli.main(argv) == 2
    return capsys.readouterr().err


def test_repo_of_url_reads_https_and_ssh():
    assert issues.repo_of_url("https://github.com/Ryubara/deadnight.git\n") == "Ryubara/deadnight"
    assert issues.repo_of_url("git@github.com:Ryubara/live.git") == "Ryubara/live"
    assert issues.repo_of_url("https://example.com/a/b") == ""


def test_checkout_repo_reads_origin(tmp_path):
    assert issues.checkout_repo(checkout(tmp_path / "g", "git@github.com:Ryubara/deadnight.git")) == "Ryubara/deadnight"
    (tmp_path / "plain").mkdir()
    assert issues.checkout_repo(tmp_path / "plain") == ""


def test_refuse_paused_names_the_reason(kit):
    with pytest.raises(issues.IssueError) as error:
        issues.refuse_paused(kit, "Ryubara/Deadnight", "gds merge-main")
    assert PAUSE in str(error.value) and "gds merge-main refused" in str(error.value)
    issues.refuse_paused(kit, "Ryubara/live", "gds merge-main")
    issues.refuse_paused(kit, "", "gds merge-main")


def test_merge_main_refuses_a_worktree_of_a_paused_repository(kit, calls, tmp_path, capsys, no_real_services):
    tree = checkout(tmp_path / "deadnight-work", "https://github.com/Ryubara/deadnight.git")
    err = refusal(["merge-main", "--path", str(tree)], capsys)
    assert "Ryubara/deadnight is paused" in err and PAUSE in err and calls == []


def test_merge_main_runs_in_a_repository_that_is_not_paused(kit, calls, tmp_path, no_real_services):
    tree = checkout(tmp_path / "live-work", "https://github.com/Ryubara/live.git")
    assert cli.main(["merge-main", "--path", str(tree)]) == 0 and calls == ["merge live-work"]


def test_pr_hold_refuses_a_pull_request_of_a_paused_repository(kit, calls, capsys, no_real_services):
    err = refusal(["pr", "hold", "Ryubara/deadnight#1371"], capsys)
    assert "gds pr hold Ryubara/deadnight#1371 refused" in err and PAUSE in err and calls == []


def test_pr_hold_runs_in_a_repository_that_is_not_paused(kit, calls, no_real_services):
    assert cli.main(["pr", "hold", "Ryubara/live#7"]) == 0 and calls == ["hold Ryubara/live#7"]


def test_pr_check_body_refuses_a_checkout_of_a_paused_repository(kit, tmp_path, capsys, monkeypatch):
    monkeypatch.setattr(pr, "check_body", lambda *a, **k: pytest.fail("the body was checked"))
    tree = checkout(tmp_path / "deadnight-work", "https://github.com/Ryubara/deadnight.git")
    err = refusal(["pr", "check-body", str(BODY), "--repo", str(tree)], capsys)
    assert "gds pr check-body refused" in err and PAUSE in err


def test_pr_check_body_runs_in_a_repository_that_is_not_paused(kit, tmp_path, monkeypatch):
    seen: list[Path] = []
    monkeypatch.setattr(pr, "check_body", lambda repo, *a, **k: seen.append(repo) or pr.BodyCheck(True, []))
    monkeypatch.setattr(pr, "check_docs", lambda *a, **k: pr.BodyCheck(True, []))
    tree = checkout(tmp_path / "live-work", "https://github.com/Ryubara/live.git")
    assert cli.main(["pr", "check-body", str(BODY), "--repo", str(tree)]) == 0 and len(seen) == 1
