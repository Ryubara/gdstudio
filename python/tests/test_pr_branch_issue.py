"""`gds pr check-body` warns when the body's `Fixes #N` is not the issue `gds issue start` made the branch for (kit
#1472): the ledger names the branch of each started issue, so a wrong number is seen before the push."""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

from gds_tools import cli, pr

REPO = "Ryubara/gdstudio"
LEDGER = {
    "ryubara/gdstudio#1472": {"repo": REPO, "number": 1472, "branch": "tools-gaps"},
    "ryubara/gdstudio#1471": {"repo": REPO, "number": 1471, "branch": "brief-match"},
    "ryubara/deadnight#12": {"repo": "Ryubara/deadnight", "number": 12, "branch": "tools-gaps"},
}


def test_a_body_closing_the_branch_issue_has_no_warning():
    assert pr.branch_issue_warning("Fixes #1472\n", REPO, "tools-gaps", LEDGER) == ""
    assert pr.branch_issue_warning("Fixes Ryubara/gdstudio#1472\n", REPO, "tools-gaps", LEDGER) == ""


def test_a_body_closing_another_issue_is_warned():
    warning = pr.branch_issue_warning("Fixes #1471\n", REPO, "tools-gaps", LEDGER)
    assert "Ryubara/gdstudio#1472" in warning and "closes #1471" in warning


def test_a_body_closing_nothing_is_warned():
    assert "closes no issue" in pr.branch_issue_warning("Part of #1472\n", REPO, "tools-gaps", LEDGER)


def test_another_repository_with_the_same_branch_name_does_not_count():
    assert "closes #1472" in pr.branch_issue_warning("Fixes #1472\n", "Ryubara/deadnight", "tools-gaps", LEDGER)


@pytest.mark.parametrize("branch", ["", "not-started"])
def test_a_branch_the_ledger_does_not_know_has_no_warning(branch):
    assert pr.branch_issue_warning("Fixes #1\n", REPO, branch, LEDGER) == ""


def test_current_branch_reads_the_checkout(tmp_path: Path):
    subprocess.run(["git", "init", "-q", "-b", "tools-gaps", str(tmp_path)], check=True)
    assert pr.current_branch(tmp_path) == "tools-gaps"


def test_check_body_prints_the_warning(tmp_path: Path, monkeypatch, capsys):
    monkeypatch.setattr(cli, "_branch_issue_warning", lambda repo, body: "the branch x was started for y#1")
    monkeypatch.setattr(pr, "repo_root", lambda here: tmp_path)
    monkeypatch.setattr(cli.issues, "refuse_paused", lambda *a: None)
    monkeypatch.setattr(pr, "branch_changes", lambda repo: ([], "no base"))
    monkeypatch.setattr(pr, "check_body", lambda *a, **k: pr.BodyCheck(True, []))
    monkeypatch.setattr(pr, "check_docs", lambda *a, **k: pr.BodyCheck(True, []))
    monkeypatch.setattr(pr, "check_commits", lambda *a, **k: pr.BodyCheck(True, []))
    body = tmp_path / "body.md"
    body.write_text("Fixes #2\n", encoding="utf-8")
    assert cli.main(["pr", "check-body", str(body), "--repo", str(tmp_path)]) == 0  # a warning never refuses
    assert "warning: the branch x was started for y#1" in capsys.readouterr().err
