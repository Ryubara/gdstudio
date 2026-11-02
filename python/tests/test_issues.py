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
        "areas": [],
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


def test_start_records_the_areas_of_the_issues_labels(tmp_path):
    ledger = tmp_path / "l.json"
    seen = []

    def areas_for(labels):
        seen.append(labels)
        return ["general", "gameplay"]

    lines = issues.start(REPO, 156, "a", gh=FakeGh(), ledger=ledger, areas_for=areas_for)
    assert "A-gameplay" in seen[0]
    assert issues.load_ledger(ledger)["ryubara/deadnight#156"]["areas"] == ["general", "gameplay"]
    assert any(line.startswith("areas: general, gameplay") for line in lines)
    issues.start(REPO, 52, "a", gh=FakeGh(), ledger=ledger)  # no map: no areas, still a valid entry
    assert issues.load_ledger(ledger)["ryubara/deadnight#52"]["areas"] == []


# --------------------------------------------------------------------------------------------------------------------
# Blocks: the reason in the body, the unblocked list, `block` and `unblock`
# --------------------------------------------------------------------------------------------------------------------

BY_HAND = "Blocked (coordinator, 2026-11-02): waits on #227 (the bot issues need the zombie rig) before it can start."


def blocked(number: int, body: str, *extra: str) -> Issue:
    return Issue(number, f"issue {number}", frozenset({"S-blocked", *extra}), body=body)


def test_the_coordinators_hand_written_line_parses():
    block = issues.parse_block("## Problem\n\nSomething.\n\n" + BY_HAND + "\n")
    assert (block.who, block.date) == ("coordinator", "2026-11-02")
    assert block.waits_on == (("", 227),) and not block.maintainer
    assert block.reason.startswith("waits on #227 (the bot issues")


def test_the_maintainer_and_several_issues_and_other_repositories_parse():
    mine = issues.parse_block("Blocked (coordinator, 2026-11-02): waits on the maintainer: pick the engine, see #12.")
    assert mine.maintainer and mine.waits_on == ()
    several = issues.parse_block("Blocked (agent x, 2026-11-02): waits on #227 and #228 (not #12): bots")
    assert several.waits_on == (("", 227), ("", 228))  # the reference after the parenthesis is not a blocker
    other = issues.parse_block("Blocked (coordinator, 2026-11-02): waits on Ryubara/gdstudio#150: the check")
    assert other.waits_on == (("Ryubara/gdstudio", 150),)
    assert issues.parse_block("nothing here\nBlocked is a word") is None
    assert issues.parse_block("") is None


def test_the_last_block_line_counts():
    body = "Blocked (coordinator, 2026-11-01): waits on #1: old\n\nBlocked (coordinator, 2026-11-02): waits on #2: new"
    assert issues.parse_block(body).waits_on == (("", 2),)


def test_a_block_whose_issue_closed_is_unblocked_and_the_rest_stay():
    line = "Blocked (coordinator, 2026-11-02): waits on #227: bots"
    open_issues = [
        make(227),  # still open: the issues behind it stay blocked
        blocked(1, line),
        blocked(2, "Blocked (coordinator, 2026-11-02): waits on #300: it closed"),
        blocked(3, "Blocked (coordinator, 2026-11-02): waits on the maintainer: engine"),
        blocked(4, "no reason written"),
        blocked(5, "Blocked (coordinator, 2026-11-02): waits on Ryubara/gdstudio#1: another repository"),
        blocked(6, "Blocked (coordinator, 2026-11-02): waits on #90: a pull request"),
    ]
    prs = [PullRequest(90, "pr", frozenset(), frozenset())]
    window = issues.compute_window(REPO, open_issues, prs, 5)
    assert numbers(window.blocked) == [1, 2, 3, 4, 5, 6]
    assert numbers(window.unblocked) == [2]
    assert set(window.blocks) == {1, 2, 3, 5, 6}  # #4 gives no reason


def test_list_shows_the_reasons_and_the_unblocked_ones(tmp_path):
    rows = [
        {"number": 1, "title": "waits on a bot", "labels": [{"name": "S-blocked"}], "body": BY_HAND},
        {
            "number": 2,
            "title": "its blocker closed",
            "labels": [{"name": "S-blocked"}],
            "body": BY_HAND.replace("227", "9"),
        },
        {"number": 3, "title": "no reason", "labels": [{"name": "S-blocked"}], "body": ""},
        {"number": 227, "title": "bots", "labels": []},
    ]
    gh = FakeGh(issues_json=json.dumps(rows), prs_json="[]")
    text = "\n".join(issues.list_issues(REPO, gh=gh, ledger=tmp_path / "l.json"))
    blocked_part, _, unblocked_part = text.partition("Unblocked: label to remove")
    assert "#1" in blocked_part and "waits on #227 (the bot issues" in blocked_part
    assert "#3" in blocked_part and "no reason recorded" in blocked_part and "gds issue block" in blocked_part
    assert "#2" in unblocked_part and "gds issue unblock" in unblocked_part and "#2 " not in blocked_part


def test_fetch_asks_for_the_body():
    asked = []

    def gh(args):
        asked.append(args)
        return "[]"

    issues.fetch(REPO, gh)
    assert "number,title,labels,assignees,body" in asked[0]


def gh_for(issue_list: list[dict], prs: str = "[]") -> FakeGh:
    return FakeGh(issues_json=json.dumps(issue_list), prs_json=prs)


def raw(number: int, *labels: str, body: str = "") -> dict:
    return {"number": number, "title": f"issue {number}", "labels": [{"name": n} for n in labels], "body": body}


NOW = datetime(2026, 11, 3, 9, 0, tzinfo=UTC)


def test_block_writes_the_label_and_the_line(tmp_path):
    ledger = tmp_path / "issues-started.json"
    cache = tmp_path / issues.IDLE_CACHE
    cache.write_text("{}", encoding="utf-8")
    gh = gh_for([raw(7, "S-ready-to-start", body="## Problem\n\nText."), raw(227)])
    lines = issues.block(REPO, 7, "#227", "needs the\nzombie rig", gh=gh, ledger=ledger, now=NOW)
    edit = gh.calls[0]
    assert edit[:5] == ["issue", "edit", "7", "-R", REPO]
    assert edit[edit.index("--body") + 1] == (
        "## Problem\n\nText.\n\nBlocked (coordinator, 2026-11-03): waits on #227: needs the zombie rig"
    )
    assert edit[edit.index("--add-label") + 1] == "S-blocked"
    assert edit[edit.index("--remove-label") + 1] == "S-ready-to-start"
    assert "waits on #227" in lines[0]
    assert not cache.exists()  # the hook must look again
    block = issues.parse_block(edit[edit.index("--body") + 1])
    assert block.waits_on == (("", 227),)  # what block writes, parse_block reads


def test_block_on_the_maintainer_and_replacing_an_old_line(tmp_path):
    old = "Blocked (coordinator, 2026-11-01): waits on #5: old"
    gh = gh_for([raw(7, "S-blocked", body="Text\n\n" + old)])
    issues.block(REPO, 7, "maintainer", "which engine", gh=gh, ledger=tmp_path / "l.json", who="idle-check", now=NOW)
    body = gh.calls[0][gh.calls[0].index("--body") + 1]
    assert body == "Text\n\nBlocked (idle-check, 2026-11-03): waits on the maintainer: which engine"
    assert issues.parse_block(body).maintainer


def test_block_refuses_what_cannot_be_blocked(tmp_path):
    ledger = tmp_path / "l.json"
    gh = gh_for([raw(7), raw(8, "S-in-progress"), raw(227)])
    for number, on, why, text in [
        (7, "#7", "x", "not another open"),
        (7, "#999", "x", "not another open"),  # closed or never existed
        (7, "#227", "  ", "--why"),
        (8, "#227", "x", "release it"),
        (404, "#227", "x", "not an open issue"),
        (7, "nonsense", "x", "not an issue"),
    ]:
        with pytest.raises(IssueError, match=text):
            issues.block(REPO, number, on, why, gh=gh, ledger=ledger, now=NOW)
    assert gh.calls == []  # nothing was changed


def test_block_may_wait_on_an_open_pull_request(tmp_path):
    prs = json.dumps([{"number": 90, "title": "p", "body": "", "labels": [], "closingIssuesReferences": []}])
    gh = gh_for([raw(7)], prs=prs)
    issues.block(REPO, 7, "#90", "needs the check", gh=gh, ledger=tmp_path / "l.json", now=NOW)
    assert "waits on #90" in gh.calls[0][gh.calls[0].index("--body") + 1]


def test_unblock_lifts_the_label_and_the_line_and_keeps_the_reason(tmp_path):
    cache = tmp_path / issues.IDLE_CACHE
    cache.write_text("{}", encoding="utf-8")
    gh = gh_for([raw(7, "S-blocked", body="Text\n\n" + BY_HAND)])
    lines = issues.unblock(REPO, 7, gh=gh, ledger=tmp_path / "issues-started.json", now=NOW)
    edit, comment = gh.calls
    assert edit[edit.index("--remove-label") + 1] == "S-blocked"
    assert edit[edit.index("--add-label") + 1] == "S-ready-to-start"
    assert edit[edit.index("--body") + 1] == "Text"
    assert "Unblocked (2026-11-03)" in comment[-1] and "waits on #227" in comment[-1]
    assert "unblocked" in lines[0] and not cache.exists()
    with pytest.raises(IssueError, match="not S-blocked"):
        issues.unblock(REPO, 7, gh=gh_for([raw(7)]), ledger=tmp_path / "l.json")
    with pytest.raises(IssueError, match="not an open issue"):
        issues.unblock(REPO, 8, gh=gh_for([raw(7)]), ledger=tmp_path / "l.json")


def test_start_and_release_also_make_the_hook_look_again(tmp_path):
    ledger = tmp_path / "issues-started.json"
    cache = tmp_path / issues.IDLE_CACHE
    cache.write_text("{}", encoding="utf-8")
    issues.start(REPO, 400, "agent", gh=FakeGh(), ledger=ledger, now=NOW)
    assert not cache.exists()
    cache.write_text("{}", encoding="utf-8")
    issues.release(REPO, 400, gh=gh_for([raw(400, "S-in-progress")]), ledger=ledger)
    assert not cache.exists()
