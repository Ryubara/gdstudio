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


def test_start_labels_assigns_and_writes_the_ledger_and_posts_no_comment(tmp_path):
    gh, ledger = FakeGh(), tmp_path / "cache" / "issues-started.json"
    when = datetime(2026, 11, 2, 9, 30, tzinfo=UTC)
    lines = issues.start(REPO, 156, "godot-engineer-3", gh=gh, ledger=ledger, size=5, branch="profile-tick", now=when)
    edit, *rest = gh.calls
    assert rest == []
    assert edit[:5] == ["issue", "edit", "156", "-R", REPO]
    assert "--add-label" in edit and "S-in-progress" in edit and "@me" in edit
    assert edit[edit.index("--remove-label") + 1] == "S-needs-triage"  # it had that label, not S-ready-to-start
    assert "S-ready-to-start" not in edit
    assert "P-critical" not in edit
    entry = json.loads(ledger.read_text(encoding="utf-8"))["started"]["ryubara/deadnight#156"]
    assert entry == {
        "repo": REPO,
        "number": 156,
        "issue": "Ryubara/deadnight#156",
        "title": "gameplay: Profile the night server tick in the late rounds",
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


def test_start_prints_the_read_lines_of_the_brief(tmp_path):
    ledger = tmp_path / "ledger.json"
    seen = []

    def brief_for(issue):
        seen.append(issue.number)
        return ["Read: studio/hooks.md#docs", "Read: studio/starting-work.md#starting-an-agent"]

    lines = issues.start(REPO, 156, "a", gh=FakeGh(), ledger=ledger, brief_for=brief_for)
    assert seen == [156]
    assert lines[-3:] == [
        f"Issue: {REPO}#156",
        "Read: studio/hooks.md#docs",
        "Read: studio/starting-work.md#starting-an-agent",
    ]
    assert "areas" not in issues.load_ledger(ledger)["ryubara/deadnight#156"]


def test_a_brief_that_fails_leaves_a_placeholder_and_the_start_stands(tmp_path):
    ledger = tmp_path / "ledger.json"

    def broken(issue):
        raise RuntimeError("no network")

    lines = issues.start(REPO, 52, "a", gh=FakeGh(), ledger=ledger, brief_for=broken)
    assert lines[-1] == f"Read: <page>.md#<anchor> (run `gds brief {REPO}#52`)"
    assert "ryubara/deadnight#52" in issues.load_ledger(ledger)
    assert issues.start(REPO, 400, "a", gh=FakeGh(), ledger=ledger)[-1] == f"Issue: {REPO}#400"  # no brief asked


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
    gh = gh_for([raw(7, "S-ready-to-start", body="## Problem\n\nText.\n\nDepends on: #227."), raw(227)])
    lines = issues.block(REPO, 7, "#227", "needs the\nzombie rig", gh=gh, ledger=ledger, now=NOW)
    edit = gh.calls[0]
    assert edit[:5] == ["issue", "edit", "7", "-R", REPO]
    assert edit[edit.index("--body") + 1] == (
        "## Problem\n\nText.\n\nDepends on: #227.\n\n"
        "Blocked (coordinator, 2026-11-03): waits on #227: needs the zombie rig"
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
    gh = gh_for([raw(7, body="Depends on: #227"), raw(8, "S-in-progress"), raw(227)])
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
    gh = gh_for([raw(7, body="Depends on: #90 (the check)")], prs=prs)
    issues.block(REPO, 7, "#90", "needs the check", gh=gh, ledger=tmp_path / "l.json", now=NOW)
    assert "waits on #90" in gh.calls[0][gh.calls[0].index("--body") + 1]


def blocked_body(tmp_path, body: str, *, on: str = "#564", conflict=()) -> list[str]:
    """The `gh issue edit` call `block` makes for issue 7 with this body, or raises."""
    gh = gh_for([raw(7, "S-ready-to-start", body=body), raw(564, "S-in-progress"), raw(570)])
    issues.block(REPO, 7, on, "why", gh=gh, ledger=tmp_path / "l.json", now=NOW, conflict=conflict)
    return gh.calls[0]


def test_block_accepts_a_dependency_the_body_names(tmp_path):
    for body in [
        "Depends on: #564.",
        "**Depends on:** phases 1 to 3 and #564 (the bot brain)",
        "- Depends on: #570, #564",
        "Depends on: #560 to #570",  # a range names each number in it
        "Carried from #564 (PR #597, coordinator 2026-11-02): the shop soak missed a gate.",
        "Depends on: Ryubara/deadnight#564",
        "### Summary\n\nText.\n\n### Blocked by\n\nThe greybox (#564) until it merges.\n\n### Screenshots\n\nNone.",
        "### Blocked by\n\n#570 (the greybox), and the formula page's pull request (#564).\n",  # two, at the end
        "### Blocked by\n\n#560 to #570\n\n### Screenshots\n\nNone",  # a range names each number in it
        "Text.\n\nStarts after #564 merges (it adds `kit.py`). About 2 days.",
        "- **Starts after** #570 and #564 merge; independent of the rest.",
        "Starts after #564.",
    ]:
        edit = blocked_body(tmp_path, body)
        assert "waits on #564: why" in edit[edit.index("--body") + 1], body
        assert "S-blocked" in edit


def test_block_refuses_a_chain_with_no_dependency_and_points_at_the_rule(tmp_path):
    """Deadnight #229, #230 and #231 were chained behind #564 as 'the same bot brain; one agent in order'."""
    for body in [
        "",
        "Depends on: phases 1 to 3.",  # no issue named
        "Depends on: #570.",  # another issue
        "Depends on: #5640.",
        "See #564 for the bot brain.",  # mentioned, not a dependency
        "Carried from #570 (PR #564): the soak.",  # the pull request after it is not the issue it was carried from
        "Blocked (coordinator, 2026-11-02): waits on #564: the same bot brain; one agent in order.",
        "### Summary\n\nSee #564 for the bot brain.\n\n### Blocked by\n\nNone.",  # only the summary names it
        "### Summary\n\nSee #564.\n\n### Blocked by\n\n#570\n\n### Screenshots\n\nAfter #564 lands.",
        "### Blocked by\n\n#570\n\n### Fix list or steps\n\n1. Read #564.",  # a later section is not Blocked by
        "Starts after #570 merges (it adds #564's file).",  # after the parenthesis it is a mention
        "It starts after the greybox; see #564.",  # not a line that begins with Starts after
    ]:
        gh = gh_for([raw(7, "S-ready-to-start", body=body), raw(564, "S-in-progress")])
        with pytest.raises(IssueError, match=r"does not name #564 as a dependency") as caught:
            issues.block(REPO, 7, "#564", "the same bot brain", gh=gh, ledger=tmp_path / "l.json", now=NOW)
        assert "docs/studio/starting-work.md#parallel" in str(caught.value) and "--conflict" in str(caught.value), body
        assert gh.calls == [], body  # nothing was changed


def test_block_accepts_conflict_files_in_place_of_a_dependency(tmp_path):
    edit = blocked_body(tmp_path, "No dependency named.", conflict=("src/bots/brain.gd", "tests/bots/brain_test.gd"))
    body = edit[edit.index("--body") + 1]
    assert body.endswith("waits on #564: why (conflict in: src/bots/brain.gd, tests/bots/brain_test.gd)")
    block = issues.parse_block(body)
    assert block.conflicts == ("src/bots/brain.gd", "tests/bots/brain_test.gd") and block.waits_on == (("", 564),)
    assert block.kind(set(), REPO) == "conflict"


def test_block_conflict_still_needs_an_open_issue_and_a_file_named(tmp_path):
    gh = gh_for([raw(7), raw(564, "S-in-progress")])
    with pytest.raises(IssueError, match="not another open"):
        issues.block(REPO, 7, "#999", "x", gh=gh, ledger=tmp_path / "l.json", now=NOW, conflict=("a.gd",))
    with pytest.raises(IssueError, match="does not name #564"):  # a blank path names nothing
        issues.block(REPO, 7, "#564", "x", gh=gh, ledger=tmp_path / "l.json", now=NOW, conflict=("  ",))
    with pytest.raises(IssueError, match="maintainer has none"):
        issues.block(REPO, 7, "maintainer", "x", gh=gh, ledger=tmp_path / "l.json", now=NOW, conflict=("a.gd",))
    assert gh.calls == []


def test_block_on_the_maintainer_needs_no_dependency(tmp_path):
    gh = gh_for([raw(7, body="No dependency named.")])
    issues.block(REPO, 7, "maintainer", "a person must launch it", gh=gh, ledger=tmp_path / "l.json", now=NOW)
    assert "waits on the maintainer" in gh.calls[0][gh.calls[0].index("--body") + 1]


def test_dependencies_read_the_forms_deadnight_uses():
    body = (
        "From: bots-combat agent, 2026-11-02, deadnight #227\n\n"
        "Depends on: phases 1 to 5, the networked match (#53 to #56), and Ryubara/gdstudio#12.\n"
        "Builds on the core revive of #224.\n"
        "Carried from #228 (PR #597, coordinator): it missed a gate.\n"
        "Blocked (coordinator, 2026-11-02): waits on #564: the same bot brain.\n"
    )
    assert issues.dependencies(body) == {("", 53), ("", 54), ("", 55), ("", 56), ("Ryubara/gdstudio", 12), ("", 228)}
    assert issues.dependencies("") == set()


def test_dependencies_read_the_blocked_by_section_and_starts_after():
    """Deadnight #631 to #633 name theirs in the form's `### Blocked by` section or as `Starts after #N merges`."""
    body = (
        "### Summary\n\nSee #1 and #2.\n\n### Blocked by\n\n#631 (the greybox), and the formula page's pull request "
        "(#622).\n\n### Screenshots\n\nAfter #3.\n"
    )
    assert issues.dependencies(body) == {("", 631), ("", 622)}
    assert issues.dependencies("Starts after #630 merges (it adds `smallmap_kit.py`). About #9.") == {("", 630)}
    assert issues.dependencies("### Blocked by\n\nNone\n") == set()
    assert issues.dependencies("### Blocked by\r\n\r\n#631\r\n") == {("", 631)}  # the API may return CRLF


def test_list_shows_the_reason_class_beside_each_block(tmp_path):
    def row(number: int, title: str, body: str, *labels: str) -> dict:
        return {"number": number, "title": title, "labels": [{"name": n} for n in labels], "body": body}

    rows = [
        row(1, "dep", "Depends on: #227\n" + BY_HAND, "S-blocked"),
        row(5, "form", "### Blocked by\n\n#227 (the rig)\n\n" + BY_HAND, "S-blocked"),
        row(2, "chain", "Blocked (coordinator, 2026-11-02): waits on #227: same brain", "S-blocked"),
        row(3, "files", "Blocked (coordinator, 2026-11-03): waits on #227: edits (conflict in: a.gd)", "S-blocked"),
        row(4, "person", "Blocked (coordinator, 2026-11-02): waits on the maintainer: x", "S-blocked"),
        row(227, "open", "", "S-in-progress"),
    ]
    gh = FakeGh(issues_json=json.dumps(rows), prs_json="[]")
    text = "\n".join(issues.list_issues(REPO, gh=gh, ledger=tmp_path / "l.json"))
    by_number = {int(line.split()[0][1:]): line for line in text.splitlines() if line.startswith("  #")}
    assert "[dependency]" in by_number[1] and "[none named]" in by_number[2]
    assert "[conflict]" in by_number[3] and "[maintainer]" in by_number[4]
    assert "[dependency]" in by_number[5]  # named in the issue form's Blocked by section


def test_unblock_lifts_the_label_and_the_line_and_posts_no_comment(tmp_path):
    cache = tmp_path / issues.IDLE_CACHE
    cache.write_text("{}", encoding="utf-8")
    gh = gh_for([raw(7, "S-blocked", body="Text\n\n" + BY_HAND)])
    lines = issues.unblock(REPO, 7, gh=gh, ledger=tmp_path / "issues-started.json", now=NOW)
    edit = next(call for call in gh.calls if call[:2] == ["issue", "edit"])
    assert not any(issues.posts_a_comment(call) for call in gh.calls)
    assert edit[edit.index("--remove-label") + 1] == "S-blocked"
    assert edit[edit.index("--add-label") + 1] == "S-ready-to-start"
    assert edit[edit.index("--body") + 1] == "Text"
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


POSTING = [
    ["issue", "comment", "5", "--body", "hi"],
    ["pr", "comment", "5", "--body", "hi"],
    ["pr", "review", "5", "--approve"],
    ["discussion", "comment", "5"],
    ["issue", "close", "5", "--comment", "hi"],
    ["issue", "close", "5", "--comment=hi"],
    ["pr", "close", "5", "-c", "hi"],
    ["issue", "reopen", "5", "-c=hi"],
    ["api", "repos/o/r/issues/5/comments", "-f", "body=hi"],
    ["api", "-X", "POST", "repos/o/r/issues/5/comments"],
    ["api", "--method", "PATCH", "repos/o/r/issues/comments/9", "-f", "body=hi"],
    ["api", "repos/o/r/pulls/5/reviews", "-f", "event=COMMENT"],
    ["api", "graphql", "-f", "query=mutation { addComment(input:{}) { clientMutationId } }"],
]
NOT_POSTING = [
    ["issue", "edit", "5", "--add-label", "x", "--body", "a comment in the body"],
    ["issue", "list", "-R", REPO, "--json", "number"],
    ["issue", "close", "5", "--reason", "completed"],
    ["api", "repos/o/r/issues/5/comments"],
    ["api", "-X", "GET", "repos/o/r/issues/5/comments", "-f", "per_page=100"],
    ["api", "-X", "DELETE", "repos/o/r/issues/comments/9"],
    ["api", "repos/o/r/issues/5/labels", "-f", "labels[]=x"],
    ["api", "graphql", "-f", "query={ viewer { login } }"],
]


@pytest.mark.parametrize("args", POSTING)
def test_the_runner_refuses_what_would_post_under_the_maintainers_account(args, monkeypatch):
    monkeypatch.setattr(issues.subprocess, "run", lambda *a, **k: pytest.fail("gh ran"))
    with pytest.raises(IssueError, match="refused"):
        issues.run_gh(args)


@pytest.mark.parametrize("args", NOT_POSTING)
def test_the_runner_lets_everything_else_through(args):
    assert not issues.posts_a_comment(args)


def test_gds_has_one_way_to_run_gh():
    """A hook cannot see a `gh` run from Python: one more way past `run_gh` is a way past the rule (kit #752)."""
    source = Path(issues.__file__).parent
    runs = [p.name for p in source.glob("*.py") if '["gh",' in p.read_text(encoding="utf-8")]
    assert runs == ["issues.py"]


PAUSE = "by the maintainer on 2026-11-07, for kit work first"


def test_a_paused_repository_holds_every_issue_but_the_critical_ones():
    issue_list, prs = recorded()
    window = issues.compute_window(REPO, issue_list, prs, 5, paused=PAUSE)
    assert numbers(window.allowed) == [400]  # the P-critical one only
    assert numbers(window.held) == [52, 57, 105, 156, 171] and window.later == []
    assert PAUSE in window.why_not(52) and "P-critical" in window.why_not(52)


def test_start_refuses_an_issue_of_a_paused_repository_with_the_reason(tmp_path):
    gh, ledger = FakeGh(), tmp_path / "l.json"
    with pytest.raises(IssueError) as error:
        issues.start(REPO, 52, "a", gh=gh, ledger=ledger, paused=PAUSE)
    assert "paused repository" in str(error.value) and PAUSE in str(error.value)
    assert gh.calls == [] and not ledger.exists()


def test_start_takes_a_critical_issue_of_a_paused_repository(tmp_path):
    gh = FakeGh()
    issues.start(REPO, 400, "a", gh=gh, ledger=tmp_path / "l.json", paused=PAUSE)
    assert gh.calls[0][:3] == ["issue", "edit", "400"]


def test_list_of_a_paused_repository_says_so_and_offers_only_the_critical(tmp_path):
    lines = issues.list_issues(REPO, gh=FakeGh(), ledger=tmp_path / "l.json", paused=PAUSE)
    text = "\n".join(lines)
    assert f"PAUSED: {PAUSE}" in text and "Held by the pause (5): #52, #57, #105, #156, #171" in text
    offered = lines[lines.index("May start now:") + 1 :]
    offered = [line for line in offered[: offered.index("")] if line.startswith("  ")]
    assert len(offered) == 1 and offered[0].lstrip().startswith("#400")
    assert "PAUSED" not in "\n".join(issues.list_issues(REPO, gh=FakeGh(), ledger=tmp_path / "l.json"))


def test_paused_repositories_reads_workspace_toml(tmp_path):
    (tmp_path / "workspace.toml").write_text(
        'folders = ["repos"]\n'
        '[repos.kit]\nurl = "https://github.com/Ryubara/gdstudio.git"\n'
        '[repos.game]\nurl = "https://github.com/Ryubara/Deadnight.git"\npaused = "kit first, 2026-11-07"\n'
        '[repos.other]\nurl = "https://github.com/Ryubara/other"\npaused = true\n'
        '[repos.live]\nurl = "https://github.com/Ryubara/live"\npaused = ""\n',
        encoding="utf-8",
    )
    assert issues.paused_repositories(tmp_path) == {
        "ryubara/deadnight": "kit first, 2026-11-07",
        "ryubara/other": "paused",
    }
    assert issues.paused_reason(tmp_path, "Ryubara/Deadnight") == "kit first, 2026-11-07"
    assert issues.paused_reason(tmp_path, "Ryubara/live") == "" and issues.paused_repositories(tmp_path / "no") == {}


def test_the_kit_pauses_deadnight():
    kit = Path(__file__).resolve().parents[2]
    assert issues.paused_reason(kit, REPO) and not issues.paused_reason(kit, "Ryubara/gdstudio")
