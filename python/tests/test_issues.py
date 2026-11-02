"""`gds issue`: the window of issues that may start, the start itself, the ledger. Every `gh` call is answered from
JSON recorded from Ryubara/deadnight (tests/fixtures), never from the network."""

from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path

import pytest

from gds_tools import issues
from gds_tools.issues import Issue, IssueError, PullRequest

FIXTURES = Path(__file__).parent / "fixtures"
REPO = "Ryubara/deadnight"


def recorded() -> tuple[list[Issue], list[PullRequest]]:
    raw_issues = json.loads((FIXTURES / "gh-issues.json").read_text(encoding="utf-8"))
    raw_prs = json.loads((FIXTURES / "gh-prs.json").read_text(encoding="utf-8"))
    return [Issue.from_json(i) for i in raw_issues], [PullRequest.from_json(REPO, p) for p in raw_prs]


def make(number: int, *labels: str, title: str = "") -> Issue:
    return Issue(number, title or f"issue {number}", frozenset(labels))


def numbers(items) -> list[int]:
    return [getattr(i, "issue", i).number for i in items]


class FakeGh:
    """Answers `gh issue list` and `gh pr list` from the recorded JSON and remembers every other call."""

    def __init__(self, issues_json: str | None = None, prs_json: str | None = None):
        self.issues = issues_json or (FIXTURES / "gh-issues.json").read_text(encoding="utf-8")
        self.prs = prs_json or (FIXTURES / "gh-prs.json").read_text(encoding="utf-8")
        self.calls: list[list[str]] = []

    def __call__(self, args: list[str]) -> str:
        if args[:2] == ["issue", "list"]:
            return self.issues
        if args[:2] == ["pr", "list"]:
            return self.prs
        self.calls.append(args)
        return ""


def test_the_recorded_window():
    issue_list, prs = recorded()
    window = issues.compute_window(REPO, issue_list, prs, 5)
    # P-critical #400 first, then the oldest ready ones by number; #171 is the sixth and stays behind
    assert numbers(window.allowed) == [400, 52, 57, 105, 156]
    assert numbers(window.later) == [171]
    # 285 and 459/487 by label, 54 and 477 only by an open pull request (no label), all out of the line
    assert numbers(window.in_progress) == [54, 285, 459, 477, 487]
    assert numbers(window.blocked) == [527]


def test_oldest_means_lowest_number_whatever_the_list_order():
    shuffled = [make(9), make(2), make(30), make(4), make(7)]
    assert numbers(issues.compute_window(REPO, shuffled, [], 3).allowed) == [2, 4, 7]


def test_priority_critical_goes_first_oldest_first_among_them():
    line = [make(1), make(2), make(8, "P-critical"), make(5, "P-critical"), make(3)]
    window = issues.compute_window(REPO, line, [], 4)
    assert numbers(window.allowed) == [5, 8, 1, 2]
    assert numbers(window.later) == [3]


def test_in_progress_blocked_and_waiting_leave_the_line():
    line = [
        make(1, "S-in-progress"),
        make(2, "S-pending-review"),
        make(3, "S-blocked"),
        make(4, "S-needs-info"),
        make(5),
        make(6, "S-ready-to-start"),
    ]
    window = issues.compute_window(REPO, line, [], 5)
    assert numbers(window.allowed) == [5, 6]
    assert numbers(window.in_progress) == [1, 2]
    assert numbers(window.blocked) == [3]
    assert numbers(window.waiting) == [4]


def test_an_issue_closed_by_an_open_pull_request_is_in_progress_without_a_label():
    pr = PullRequest.from_json(REPO, {"number": 40, "title": "t", "body": "Fixes #2 and closes #3", "labels": []})
    window = issues.compute_window(REPO, [make(1), make(2), make(3), make(4)], [pr], 5)
    assert numbers(window.allowed) == [1, 4]
    assert [(p.issue.number, p.labelled, p.pull_requests) for p in window.in_progress] == [
        (2, False, (40,)),
        (3, False, (40,)),
    ]


def test_closing_references_of_another_repository_do_not_count():
    reference = {"number": 2, "repository": {"name": "other", "owner": {"login": "Ryubara"}}}
    pr = PullRequest.from_json(
        REPO,
        {
            "number": 40,
            "title": "t",
            "body": "Fixes Ryubara/other#3",
            "labels": [],
            "closingIssuesReferences": [reference],
        },
    )
    assert pr.closes == frozenset()


def test_window_size_is_a_parameter():
    line = [make(n) for n in range(1, 11)]
    assert numbers(issues.compute_window(REPO, line, [], 2).allowed) == [1, 2]
    assert numbers(issues.compute_window(REPO, line, [], 10).allowed) == list(range(1, 11))


def test_refusal_lists_the_allowed_issues():
    issue_list, prs = recorded()
    window = issues.compute_window(REPO, issue_list, prs, 5)
    text = issues.refusal(REPO, 171, window)
    assert "number 6 in the line" in text and "first 5" in text
    assert "#400" in text and "[P-critical]" in text and "#156" in text and "#171  " not in text
    assert "already in progress" in issues.refusal(REPO, 54, window) and "pull request #514" in issues.refusal(
        REPO, 54, window
    )
    assert "S-blocked" in issues.refusal(REPO, 527, window)
    assert "not an open issue" in issues.refusal(REPO, 9999, window)


def test_parse_ref():
    assert issues.parse_ref("Ryubara/deadnight#523") == (REPO, 523)
    assert issues.parse_ref("#7", REPO) == (REPO, 7)
    assert issues.parse_ref("7", REPO) == (REPO, 7)
    with pytest.raises(IssueError):
        issues.parse_ref("#7")
    with pytest.raises(IssueError):
        issues.parse_ref("not an issue")


def test_start_refuses_outside_the_window_and_changes_nothing(tmp_path):
    gh, ledger = FakeGh(), tmp_path / "cache" / "issues-started.json"
    with pytest.raises(IssueError) as error:
        issues.start(REPO, 171, "godot-1", gh=gh, ledger=ledger, size=5)
    assert "#400" in str(error.value)
    assert gh.calls == [] and not ledger.exists()


def test_start_labels_assigns_comments_and_writes_the_ledger(tmp_path):
    gh, ledger = FakeGh(), tmp_path / "cache" / "issues-started.json"
    when = datetime(2026, 11, 2, 9, 30, tzinfo=UTC)
    lines = issues.start(REPO, 156, "godot-engineer-3", gh=gh, ledger=ledger, size=5, branch="profile-tick", now=when)
    edit, comment = gh.calls
    assert edit[:5] == ["issue", "edit", "156", "-R", REPO]
    assert "--add-label" in edit and "S-in-progress" in edit and "@me" in edit
    assert edit[edit.index("--remove-label") + 1] == "S-needs-triage"  # it had that label, not S-ready-to-start
    assert "S-ready-to-start" not in edit
    assert "P-critical" not in edit
    assert comment[:2] == ["issue", "comment"] and "Started by agent godot-engineer-3" in comment
    entry = json.loads(ledger.read_text(encoding="utf-8"))["started"]["ryubara/deadnight#156"]
    assert entry == {
        "repo": REPO,
        "number": 156,
        "issue": "Ryubara/deadnight#156",
        "agent": "godot-engineer-3",
        "time": "2026-11-02T09:30:00Z",
        "branch": "profile-tick",
    }
    assert lines[-1] == "Issue: Ryubara/deadnight#156"


def test_start_takes_a_critical_issue_even_when_the_line_is_long(tmp_path):
    gh = FakeGh()
    issues.start(REPO, 400, "a", gh=gh, ledger=tmp_path / "l.json", size=1)
    assert gh.calls[0][2] == "400" and "S-ready-to-start" in gh.calls[0]  # it carried S-ready-to-start


def test_start_refuses_an_issue_already_started_and_a_window_override_widens_it(tmp_path):
    ledger = tmp_path / "l.json"
    with pytest.raises(IssueError, match="already in progress"):
        issues.start(REPO, 285, "a", gh=FakeGh(), ledger=ledger)
    gh = FakeGh()
    issues.start(REPO, 171, "a", gh=gh, ledger=ledger, size=6)  # the sixth in line is allowed with N = 6
    assert gh.calls[0][2] == "171"


def test_start_prunes_ledger_entries_of_closed_issues(tmp_path):
    ledger = tmp_path / "l.json"
    issues.save_ledger(
        ledger,
        {
            "ryubara/deadnight#9999": {"repo": REPO, "number": 9999, "agent": "old"},
            "ryubara/other#1": {"repo": "Ryubara/other", "number": 1, "agent": "kept"},
        },
    )
    issues.start(REPO, 52, "a", gh=FakeGh(), ledger=ledger)
    assert sorted(issues.load_ledger(ledger)) == ["ryubara/deadnight#52", "ryubara/other#1"]


def test_release_puts_the_issue_back_and_clears_the_ledger(tmp_path):
    ledger, gh = tmp_path / "l.json", FakeGh()
    issues.start(REPO, 52, "a", gh=FakeGh(), ledger=ledger)
    lines = issues.release(REPO, 52, gh=gh, ledger=ledger, agent="a")
    assert "S-ready-to-start" in gh.calls[0] and "--remove-label" in gh.calls[0]
    assert issues.load_ledger(ledger) == {}
    assert "back in the line" in lines[0]


def test_release_warns_when_a_pull_request_still_closes_it(tmp_path):
    lines = issues.release(REPO, 54, gh=FakeGh(), ledger=tmp_path / "l.json")
    assert "#514" in lines[-1]


def test_done_clears_one_entry(tmp_path):
    ledger = tmp_path / "l.json"
    issues.start(REPO, 52, "a", gh=FakeGh(), ledger=ledger)
    assert "cleared" in issues.done(REPO, 52, ledger=ledger)[0]
    assert "was not in the ledger" in issues.done(REPO, 52, ledger=ledger)[0]


def test_list_shows_owners_pull_requests_and_the_ownerless(tmp_path):
    ledger = tmp_path / "l.json"
    issues.save_ledger(
        ledger,
        {"ryubara/deadnight#487": {"repo": REPO, "number": 487, "agent": "godot-9", "time": "2026-11-02T07:00:00Z"}},
    )
    text = "\n".join(issues.list_issues(REPO, gh=FakeGh(), ledger=ledger, size=5))
    assert "May start now:" in text and "#400" in text and "[P-critical]" in text
    assert "Behind the window (1): #171" in text
    assert "agent godot-9 since 2026-11-02T07:00:00Z" in text and "PR #513" in text
    assert "#54" in text and "PR #514" in text  # in progress by its pull request alone
    assert "NO OWNER" in text and "#285" in text  # the label with nobody behind it
    assert "Blocked:" in text and "#527" in text
    assert "Pull requests carrying S-in-progress" in text and "#513" in text


def test_settings_default_kit_and_game_override(tmp_path):
    kit, game = tmp_path / "kit", tmp_path / "game"
    (kit / ".claude" / "hooks").mkdir(parents=True)
    (game / ".claude").mkdir(parents=True)
    assert issues.load_settings(None, None).window == 5
    (kit / ".claude" / "hooks" / "hooks.toml").write_text("[issues]\nwindow = 4\n", encoding="utf-8")
    assert issues.load_settings(kit, game).window == 4
    (game / ".claude" / "hooks.local.toml").write_text("[issues]\nwindow = 8\n", encoding="utf-8")
    assert issues.load_settings(kit, game).window == 8
    (game / ".claude" / "hooks.local.toml").write_text("[issues]\nwindow = 0\n", encoding="utf-8")
    with pytest.raises(IssueError):
        issues.load_settings(kit, game)


def test_the_kits_own_settings_load():
    kit = Path(__file__).resolve().parents[2]
    assert issues.load_settings(kit).window == 5
