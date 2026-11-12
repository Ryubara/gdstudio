"""`.github/scripts/pr_status.py`: the S-conflict and S-ci-failing labels, from sample GitHub payloads.

The decisions are pure functions of GitHub's answers; the flow (poll until `mergeable` is computed, add and remove
labels, create a label that is missing) runs against a fake client that records the calls instead of `gh`.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github" / "scripts" / "pr_status.py"
SHA = "a" * 40

spec = importlib.util.spec_from_file_location("pr_status", SCRIPT)
assert spec and spec.loader
ps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ps)

REQUIRED = ["title", "body", "docs", "commits", "conventions", "build-ok"]
DEFINITIONS = {
    "S-conflict": {"name": "S-conflict", "color": "b60205", "description": "conflicts"},
    "S-ci-failing": {"name": "S-ci-failing", "color": "e11d21", "description": "failing"},
}


def run(name: str, conclusion: str | None) -> dict[str, Any]:
    return {"name": name, "status": "completed" if conclusion else "in_progress", "conclusion": conclusion}


# --- conflict ---------------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("payload", "expected"),
    [
        ({"mergeable": False, "mergeable_state": "dirty"}, True),  # #313 in deadnight: conflicting with main
        ({"mergeable": True, "mergeable_state": "clean"}, False),
        ({"mergeable": True, "mergeable_state": "blocked"}, False),  # blocked by a red check is not a conflict
        ({"mergeable": True, "mergeable_state": "behind"}, False),
        ({"mergeable": None, "mergeable_state": "unknown"}, None),  # not computed yet
        ({}, None),
    ],
)
def test_has_conflict(payload, expected):
    assert ps.has_conflict(payload) is expected


# --- failing ----------------------------------------------------------------------------------------------------


def test_a_failed_required_check_fails():
    runs = [run("godot", "failure"), run("build-ok", "failure"), run("title", "success")]
    assert ps.failing_checks(runs, REQUIRED) == ["build-ok"]  # godot is not required: build-ok carries it


def test_a_check_that_passed_after_the_description_was_edited_is_not_failing():
    # gdstudio #1265: `commits` failed twice on the head (the Model line lacked a model), the description was edited
    # and it passed; `filter=latest` gave all three runs, one a check suite, and the label stayed on.
    failed_first = run("commits", "failure") | {"id": 1, "started_at": "2026-11-11T21:37:40Z"}
    failed_again = run("commits", "failure") | {"id": 2, "started_at": "2026-11-11T21:38:06Z"}
    passed = run("commits", "success") | {"id": 3, "started_at": "2026-11-11T22:07:26Z"}
    assert ps.failing_checks([passed, failed_first, failed_again], REQUIRED) == []
    assert ps.failing_checks([failed_first, passed, failed_again], REQUIRED) == []
    # The newest run failing is a failure, whatever passed before it.
    passed_first = run("commits", "success") | {"id": 1, "started_at": "2026-11-11T21:37:40Z"}
    assert ps.failing_checks([failed_again, passed_first], REQUIRED) == ["commits"]


def test_a_failed_check_that_is_not_required_does_not_count():
    assert ps.failing_checks([run("web", "failure"), run("build-ok", "success")], REQUIRED) == []


@pytest.mark.parametrize("conclusion", ["success", "skipped", "neutral", "cancelled", None])
def test_other_conclusions_are_not_failures(conclusion):
    assert ps.failing_checks([run("build-ok", conclusion)], REQUIRED) == []


@pytest.mark.parametrize("conclusion", ["failure", "timed_out", "startup_failure"])
def test_every_failed_conclusion_counts(conclusion):
    assert ps.failing_checks([run("docs", conclusion)], REQUIRED) == ["docs"]


def test_without_a_required_list_every_check_counts():
    assert ps.failing_checks([run("web", "failure")], []) == ["web"]


# --- label changes ----------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("current", "conflict", "failing", "add", "remove"),
    [
        (set(), True, False, ["S-conflict"], []),
        (set(), False, True, ["S-ci-failing"], []),
        (set(), True, True, ["S-conflict", "S-ci-failing"], []),
        ({"S-conflict"}, True, False, [], []),  # already right: nothing to do
        ({"S-conflict"}, False, False, [], ["S-conflict"]),  # cleared as soon as the condition clears
        ({"S-ci-failing"}, False, False, [], ["S-ci-failing"]),
        ({"S-conflict", "S-ci-failing"}, False, True, [], ["S-conflict"]),
        ({"S-conflict"}, None, False, [], []),  # unknown mergeability leaves the label as it is
        (set(), None, False, [], []),
        ({"S-ready-to-start", "bug"}, False, False, [], []),  # other labels are never touched
    ],
)
def test_label_changes(current, conflict, failing, add, remove):
    assert ps.label_changes(current, conflict, failing) == (add, remove)


# --- the flow ---------------------------------------------------------------------------------------------------


class FakeClient:
    """Answers `pulls/N` from a queue (the last answer repeats), and records every write."""

    def __init__(self, pulls: dict[int, list[dict[str, Any]]], runs: dict[str, list[dict[str, Any]]], labels=None):
        self.pulls = pulls
        self.runs = runs
        self.existing = set(labels or [])
        self.calls: list[tuple] = []
        self.gets: list[int] = []

    def get(self, path: str, paginate: bool = False):
        number = int(path.split("/")[1])
        self.gets.append(number)
        queue = self.pulls[number]
        return queue.pop(0) if len(queue) > 1 else queue[0]

    def get_or_none(self, path: str):
        return {"name": path} if path.split("/")[1] in self.existing else None

    def check_runs(self, sha: str):
        return self.runs.get(sha, [])

    def post(self, path: str, **fields: str):
        self.calls.append(("post", path, fields))

    def delete(self, path: str):
        self.calls.append(("delete", path))


def pr(number: int, mergeable: bool | None, labels: list[str] = (), state="open", sha=SHA) -> dict[str, Any]:
    return {
        "number": number,
        "state": state,
        "mergeable": mergeable,
        "head": {"sha": sha},
        "labels": [{"name": name} for name in labels],
    }


def sync(client: FakeClient, number: int, attempts: int = 5, dry_run: bool = False) -> str:
    return ps.sync_pr(
        client,
        number,
        REQUIRED,
        DEFINITIONS,
        set(),
        attempts=attempts,
        sleep=lambda _: None,
        dry_run=dry_run,
    )


def test_a_conflicting_pull_request_gets_the_label_and_a_missing_label_is_created():
    client = FakeClient({313: [pr(313, False)]}, {})
    assert "added S-conflict" in sync(client, 313)
    assert client.calls == [
        ("post", "labels", {"name": "S-conflict", "color": "b60205", "description": "conflicts"}),
        ("post", "issues/313/labels", {"labels[]": "S-conflict"}),
    ]


def test_an_existing_label_is_not_created_again():
    client = FakeClient({313: [pr(313, False)]}, {}, labels=["S-conflict"])
    sync(client, 313)
    assert client.calls == [("post", "issues/313/labels", {"labels[]": "S-conflict"})]


def test_a_failing_required_check_on_the_head_commit_gets_the_label():
    client = FakeClient(
        {346: [pr(346, True)]}, {SHA: [run("godot", "failure"), run("build-ok", "failure")]}, ["S-ci-failing"]
    )
    line = sync(client, 346)
    assert "added S-ci-failing" in line and "build-ok" in line
    assert client.calls == [("post", "issues/346/labels", {"labels[]": "S-ci-failing"})]


def test_labels_are_removed_when_the_conditions_clear():
    client = FakeClient({7: [pr(7, True, ["S-conflict", "S-ci-failing", "bug"])]}, {SHA: [run("build-ok", "success")]})
    sync(client, 7)
    assert client.calls == [("delete", "issues/7/labels/S-conflict"), ("delete", "issues/7/labels/S-ci-failing")]


def test_it_polls_until_mergeable_is_computed():
    client = FakeClient({9: [pr(9, None), pr(9, None), pr(9, False)]}, {}, ["S-conflict"])
    assert "added S-conflict" in sync(client, 9)
    assert client.gets == [9, 9, 9]


def test_the_polling_is_bounded_and_an_unknown_answer_changes_nothing():
    client = FakeClient({9: [pr(9, None, ["S-conflict"])]}, {})
    line = sync(client, 9, attempts=4)
    assert client.gets == [9, 9, 9, 9]
    assert "::warning::" in line and "no change" in line
    assert client.calls == []


def test_a_closed_pull_request_is_skipped():
    client = FakeClient({5: [pr(5, False, state="closed")]}, {})
    assert "skipped" in sync(client, 5)
    assert client.calls == []


def test_dry_run_changes_nothing():
    client = FakeClient({313: [pr(313, False)]}, {})
    assert "added S-conflict" in sync(client, 313, dry_run=True)
    assert client.calls == []


# --- which pull requests, and the conventions ---------------------------------------------------------------------


def test_open_numbers_by_sha_keeps_only_open_pull_requests_with_that_head():
    class Listing:
        def get(self, path: str, paginate: bool = False):
            return [
                {"number": 1, "state": "open", "head": {"sha": SHA}},
                {"number": 2, "state": "closed", "head": {"sha": SHA}},
                {"number": 3, "state": "open", "head": {"sha": "b" * 40}},  # a newer push moved this one on
            ]

    assert ps.open_numbers(Listing(), SHA) == [1]
    assert ps.open_numbers(Listing(), None) == [1, 2, 3]


def test_the_kit_conventions_define_both_labels_and_the_required_checks():
    required, definitions = ps.load_conventions(ROOT / ".github" / "conventions.yml")
    assert "build-ok" in required
    assert set(definitions) == {"S-conflict", "S-ci-failing"}
    for definition in definitions.values():
        assert len(definition["description"]) <= 100  # GitHub's limit
        assert definition["name"].startswith("S-")


def test_conventions_without_the_labels_are_unusable(tmp_path):
    conventions = tmp_path / "conventions.yml"
    conventions.write_text("merge: {required_checks: [build-ok]}\nlabels: {list: []}\n", encoding="utf-8")
    with pytest.raises(ps.Unusable, match="S-conflict"):
        ps.load_conventions(conventions)


def test_a_bad_sha_or_repository_is_refused(capsys):
    assert ps.main(["--sha", "not-a-sha"]) == 2
    with pytest.raises(ps.Unusable):
        ps.Client("not a repo; rm -rf")
