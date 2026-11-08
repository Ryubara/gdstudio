"""The hold on a pull request (docs/studio/hooks.md#hold): the guard, `gds pr hold`, the conventions, and the
properties of
`hold.yml` that keep a required check honest. What GitHub does with them is shown on real pull requests, not here."""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from gds_tools import pr, sync

yaml = pytest.importorskip("yaml")

KIT = Path(__file__).resolve().parents[2]
HOOKS = KIT / ".claude" / "hooks"
sys.path.insert(0, str(HOOKS))
_spec = importlib.util.spec_from_file_location("dispatch", HOOKS / "dispatch.py")
dispatch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dispatch)
guards = dispatch.guards
_spec = importlib.util.spec_from_file_location("groundwork_hold", KIT / ".github" / "scripts" / "groundwork.py")
groundwork = importlib.util.module_from_spec(_spec)
sys.modules["groundwork_hold"] = groundwork
_spec.loader.exec_module(groundwork)

CONVENTIONS = yaml.safe_load((KIT / ".github" / "conventions.yml").read_text(encoding="utf-8"))
WORKFLOW = yaml.safe_load((KIT / ".github" / "workflows" / "hold.yml").read_text(encoding="utf-8"))
SWEEP = yaml.safe_load((KIT / ".github" / "workflows" / "hold-sweep.yml").read_text(encoding="utf-8"))
ON = WORKFLOW[True]  # YAML reads the key `on` as a boolean


@pytest.fixture()
def looked(monkeypatch):
    """`held` with no network: pull request 7 carries the label, every other one does not. Records what it was asked."""
    asked: list[tuple] = []

    def fake(target, repo, cwd):
        asked.append((target, repo))
        return str(target) == "7"

    monkeypatch.setattr(guards, "held", fake)
    return asked


def refused(command: str, tmp_path: Path) -> str:
    return " ".join(reason for words in guards.segments(command) for reason in guards.check_hold(words, tmp_path))


# --- merging ---


@pytest.mark.parametrize(
    "command",
    [
        "gh pr merge 7 --squash",
        "gh pr merge 7 --squash --auto",
        "gh pr merge --auto --squash 7",
        "gh pr merge -R Ryubara/deadnight 7 --squash",
        "gh.exe pr merge 7",
        "gh api -X PUT repos/o/r/pulls/7/merge -f merge_method=squash",
        "gh api --method PUT /repos/o/r/pulls/7/merge",
        "gh api repos/o/r/pulls/7/merge -f merge_method=squash",
    ],
)
def test_a_merge_of_a_held_pull_request_is_refused(command, looked, tmp_path):
    assert "a maintainer holds it" in refused(command, tmp_path)


@pytest.mark.parametrize(
    "command",
    [
        "gh pr merge 8 --squash",
        "gh pr merge 8 --squash --auto",
        "gh pr merge 7 --disable-auto",  # turning auto-merge off is always allowed
        "gh api -X PUT repos/o/r/pulls/8/merge",
        "gh api repos/o/r/pulls/7/merge",  # a read: has it merged?
        "gh pr view 7",
    ],
)
def test_everything_else_passes(command, looked, tmp_path):
    assert refused(command, tmp_path) == ""


def test_the_repository_named_is_the_one_asked(looked, tmp_path):
    refused("gh pr merge --repo Ryubara/deadnight 12 --squash", tmp_path)
    refused("gh api -X PUT repos/Ryubara/deadnight/pulls/13/merge", tmp_path)
    assert looked == [("12", "Ryubara/deadnight"), ("13", "Ryubara/deadnight")]


def test_the_current_branchs_pull_request_is_looked_up(looked, tmp_path):
    refused("gh pr merge --squash --auto", tmp_path)
    assert looked == [("", None)]


def test_graphql_cannot_merge_past_the_hook(tmp_path):
    assert "GraphQL" in refused(
        "gh api graphql -f query='mutation { mergePullRequest(input: {}) { clientMutationId } }'", tmp_path
    )
    assert "GraphQL" in refused(
        "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { actor } }'", tmp_path
    )
    assert refused("gh api graphql -f query='query { viewer { login } }'", tmp_path) == ""


# --- taking the label off ---


@pytest.mark.parametrize(
    "command",
    [
        "gh pr edit 7 --remove-label S-hold",
        "gh pr edit 7 --remove-label=S-hold",
        "gh pr edit 7 --remove-label docs,S-hold",
        "gh issue edit 7 --remove-label S-hold",
        "gh label delete S-hold --yes",
        "gh label edit S-hold --name not-a-hold",
        "gh api -X DELETE repos/o/r/issues/8/labels/S-hold",
        "gh api --method DELETE repos/o/r/issues/8/labels/S%2Dhold",
        "gh api -X DELETE repos/o/r/labels/S-hold",
        "gh api -X PATCH repos/o/r/labels/S-hold -f new_name=x",
        "gh api -X DELETE repos/o/r/issues/7/labels",
        "gh api -X PUT repos/o/r/issues/7/labels -f 'labels[]=docs'",
        "gh api -X PATCH repos/o/r/issues/7 -f 'labels[]=docs'",
        "gh api graphql -f query='mutation { removeLabelsFromLabelable(input: {}) { clientMutationId } }'",
        "gh api graphql -f query='mutation { clearLabelsFromLabelable(input: {}) { clientMutationId } }'",
        "gh api graphql -f query='mutation { deleteLabel(input: {}) { clientMutationId } }'",
    ],
)
def test_a_session_cannot_take_the_label_off(command, looked, tmp_path):
    assert refused(command, tmp_path) != ""


@pytest.mark.parametrize(
    "command",
    [
        "gh pr edit 7 --add-label S-hold",  # anyone may set a hold
        "gh pr edit 7 --remove-label docs",
        "gh pr create --label S-hold --title t --body-file b",
        "gh api -X DELETE repos/o/r/issues/7/labels/docs",
        "gh api -X POST repos/o/r/issues/7/labels -f 'labels[]=S-hold'",
        "gh api -X DELETE repos/o/r/issues/8/labels",  # not held
        "gh api -X PATCH repos/o/r/issues/7 -f title=x",  # no labels in it
        "gh api repos/o/r/labels/S-hold",
        "gh label list",
    ],
)
def test_the_rest_of_label_work_passes(command, looked, tmp_path):
    assert refused(command, tmp_path) == ""


def test_the_refusal_reaches_a_session(looked, tmp_path):
    payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": str(tmp_path)}
    payload["tool_input"] = {"command": "gh pr merge 7 --squash --auto"}
    out = dispatch.answer(payload, dispatch.load_config(None))
    assert "a maintainer holds it" in out["hookSpecificOutput"]["permissionDecisionReason"]


@pytest.mark.parametrize(
    ("returncode", "stdout", "want"),
    [(0, "docs\nS-hold\n", True), (0, "docs\n", False), (0, "", False), (1, "", None)],
)
def test_held_reads_the_labels(monkeypatch, tmp_path, returncode, stdout, want):
    seen = {}

    def run(command, **kwargs):
        seen["command"] = command
        return subprocess.CompletedProcess(command, returncode, stdout, "")

    monkeypatch.setattr(guards.subprocess, "run", run)
    assert guards.held("7", "o/r", tmp_path) is want
    assert seen["command"][:6] == ["gh", "pr", "view", "7", "-R", "o/r"]


def test_a_guard_that_cannot_ask_lets_the_call_through(monkeypatch, tmp_path):
    def run(command, **kwargs):
        raise OSError("no gh")

    monkeypatch.setattr(guards.subprocess, "run", run)
    assert guards.held("7", None, tmp_path) is None
    assert refused("gh pr merge 7 --squash", tmp_path) == ""


# --- gds pr hold ---


class FakeGitHub:
    """`gh` for `pr.hold`: answers from a script of pull request states and check conclusions, in order."""

    def __init__(self, states=("OPEN",), conclusions=("failure",), labels=(), auto=False):
        self.states, self.conclusions = list(states), list(conclusions)
        self.labels, self.auto, self.edits = list(labels), auto, []

    def __call__(self, args: list[str]) -> str:
        if args[:2] == ["pr", "view"]:
            state = self.states.pop(0) if len(self.states) > 1 else self.states[0]
            return json.dumps(
                {
                    "state": state,
                    "headRefOid": "a" * 40,
                    "labels": [{"name": name} for name in self.labels],
                    "autoMergeRequest": {"mergeMethod": "SQUASH"} if self.auto else None,
                }
            )
        if args[:2] == ["pr", "edit"]:
            self.edits.append(args)
            self.labels.append(args[-1])
            return ""
        assert args[0] == "api" and "check_name=hold" in args[1]
        return self.conclusions.pop(0) if len(self.conclusions) > 1 else self.conclusions[0]


def test_hold_sets_the_label_and_waits_for_the_red_check():
    naps: list[float] = []
    fake = FakeGitHub(conclusions=("success", "", "failure"))
    lines = pr.hold("o/r", 7, gh=fake, sleep=naps.append)
    assert fake.edits == [["pr", "edit", "7", "-R", "o/r", "--add-label", "S-hold"]]
    assert len(naps) == 2 and "is held" in lines[0]


def test_hold_says_what_taking_the_label_off_will_do():
    lines = pr.hold("o/r", 7, gh=FakeGitHub(auto=True), sleep=lambda _: None)
    assert "merges the moment the label comes off" in lines[1]


def test_hold_on_a_held_pull_request_changes_nothing():
    fake = FakeGitHub(labels=["S-hold"])
    pr.hold("o/r", 7, gh=fake, sleep=lambda _: None)
    assert fake.edits == []


def test_hold_refuses_a_pull_request_that_is_not_open():
    with pytest.raises(pr.PrCheckError, match="merged: there is nothing left"):
        pr.hold("o/r", 7, gh=FakeGitHub(states=("MERGED",)), sleep=lambda _: None)


def test_hold_says_so_when_it_lost_the_race():
    fake = FakeGitHub(states=("OPEN", "MERGED"), conclusions=("success",))
    with pytest.raises(pr.PrCheckError, match="went through before the hold"):
        pr.hold("o/r", 7, gh=fake, sleep=lambda _: None)


def test_hold_does_not_claim_a_hold_the_check_does_not_show():
    now = [0.0]

    def nap(seconds):
        now[0] += seconds

    fake = FakeGitHub(conclusions=("success",))
    with pytest.raises(pr.PrCheckError, match="it is not held yet"):
        pr.hold("o/r", 7, gh=fake, sleep=nap, clock=lambda: now[0], timeout=10)


# --- the conventions and the ruleset ---


def test_every_copy_of_the_label_is_the_same():
    hold = CONVENTIONS["merge"]["hold"]
    step = WORKFLOW["jobs"]["hold"]["steps"][0]
    assert hold["label"] == guards.HOLD == pr.HOLD_LABEL == step["env"]["HOLD_LABEL"]
    assert hold["check"] == pr.HOLD_CHECK and hold["check"] in WORKFLOW["jobs"]
    assert hold["label"] in {item["name"] for item in CONVENTIONS["labels"]["list"]}


def test_a_hold_is_not_a_failure_for_pr_status():
    assert CONVENTIONS["merge"]["hold"]["check"] not in CONVENTIONS["merge"]["required_checks"]


def required_checks(conv) -> list[dict]:
    rules = groundwork.ruleset_wanted(conv)["rules"]
    return next(r for r in rules if r["type"] == "required_status_checks")["parameters"]["required_status_checks"]


def test_the_ruleset_takes_the_hold_from_github_actions_only():
    assert {"context": "hold", "integration_id": 15368} in required_checks(CONVENTIONS)


def test_a_ruleset_without_the_pin_is_drift():
    wanted = groundwork.ruleset_wanted(CONVENTIONS)
    unpinned = json.loads(json.dumps(wanted))
    for rule in unpinned["rules"]:
        for check in rule.get("parameters", {}).get("required_status_checks", []):
            check.pop("integration_id", None)
    assert groundwork.normalise_ruleset(wanted) != groundwork.normalise_ruleset(unpinned)


def test_a_game_with_no_hold_yet_keeps_its_ruleset():
    merge = {k: v for k, v in CONVENTIONS["merge"].items() if k != "hold"}
    assert required_checks({"merge": merge}) == [{"context": c} for c in merge["required_checks"]]


@pytest.mark.parametrize(
    ("hold", "problem"),
    [
        ({"label": "S-hold"}, "needs label, check"),
        ({"label": "nope", "check": "hold", "app_id": 1}, "labels.list lacks"),
        ({"label": "S-hold", "check": "build-ok", "app_id": 1}, "stays out of merge.required_checks"),
    ],
)
def test_validate_refuses_a_wrong_hold(hold, problem):
    conv = json.loads(json.dumps(CONVENTIONS))
    conv["merge"]["hold"] = hold
    assert any(problem in p for p in groundwork.validate(conv))


# --- the workflow: what keeps a required check honest ---


def test_it_runs_on_every_pull_request_and_on_label_events():
    events = ON["pull_request_target"]
    assert {"opened", "reopened", "synchronize", "labeled", "unlabeled"} <= set(events["types"])
    assert set(ON) == {"pull_request_target"}
    assert not {"paths", "paths-ignore", "branches", "branches-ignore"} & set(events)


def test_no_if_can_turn_a_failure_into_a_skip():
    job = WORKFLOW["jobs"]["hold"]
    assert "if" not in job and all("if" not in step for step in job["steps"])


def test_it_runs_nothing_from_the_pull_request():
    steps = WORKFLOW["jobs"]["hold"]["steps"]
    assert len(steps) == 1 and "uses" not in steps[0]


def test_it_reads_the_label_when_it_runs():
    script = WORKFLOW["jobs"]["hold"]["steps"][0]["run"]
    assert "set -euo pipefail" in script and "issues/$NUMBER/labels" in script
    assert "event.label" not in script and "event.pull_request.labels" not in script


def test_a_pull_request_moved_onto_the_default_branch_gets_a_run():
    assert "edited" in ON["pull_request_target"]["types"]


def test_there_is_no_merge_queue_for_it_to_miss():
    assert "merge_group" not in ON
    assert "merge_queue" not in {rule["type"] for rule in groundwork.ruleset_wanted(CONVENTIONS)["rules"]}


def test_the_newest_event_wins():
    assert WORKFLOW["concurrency"]["cancel-in-progress"] is True
    assert "pull_request.number" in WORKFLOW["concurrency"]["group"]


@pytest.mark.skipif(sys.platform == "win32" or not shutil.which("bash"), reason="the step runs under Linux bash")
@pytest.mark.parametrize(
    ("gh_script", "code", "text"),
    [
        ("echo docs; echo S-hold", 1, "carries S-hold"),
        ("echo docs; echo not-S-hold-at-all", 0, "carries no S-hold"),
        ("true", 0, "carries no S-hold"),  # no labels at all
        ("echo 'API rate limit' >&2; exit 1", 1, ""),  # a hold nobody could read stays a hold
    ],
)
def test_the_step_itself(tmp_path, gh_script, code, text):
    fake = tmp_path / "gh"
    fake.write_text(f"#!/bin/sh\n{gh_script}\n", encoding="utf-8")
    fake.chmod(0o755)
    step = WORKFLOW["jobs"]["hold"]["steps"][0]
    env = {
        "PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}",
        "GH_REPO": "o/r",
        "NUMBER": "7",
        "HOLD_LABEL": "S-hold",
    }
    done = subprocess.run(["bash", "-c", step["run"]], env=env, capture_output=True, text=True, timeout=30)
    assert done.returncode == code
    assert text in done.stdout


# --- the sweep ---


def test_the_sweep_runs_only_by_hand_and_can_write_only_checks():
    assert set(SWEEP[True]) == {"workflow_dispatch"}
    assert SWEEP["jobs"]["sweep"]["permissions"] == {"contents": "read", "checks": "write", "pull-requests": "read"}


def test_the_sweep_reports_the_check_the_ruleset_requires():
    step = SWEEP["jobs"]["sweep"]["steps"][0]
    assert f"name={CONVENTIONS['merge']['hold']['check']}" in step["run"]
    assert step["env"]["HOLD_LABEL"] == CONVENTIONS["merge"]["hold"]["label"]
    assert "conclusion=failure" in step["run"]  # a held pull request stays held
    assert "already has a hold check" in step["run"]  # and a commit with an answer keeps it


def test_a_game_gets_both_workflows():
    assert {".github/workflows/hold.yml", ".github/workflows/hold-sweep.yml"} <= set(sync.SCRIPTS)


def test_no_workflow_sets_the_label():
    """A label set with a workflow's GITHUB_TOKEN starts no workflow, so `hold` would stay green while held."""
    folders = (KIT / ".github" / "workflows", KIT / ".github" / "scripts")
    for path in (path for folder in folders for path in folder.iterdir() if path.is_file()):
        text = path.read_text(encoding="utf-8")
        if path.name in ("hold.yml", "hold-sweep.yml"):
            assert "add-label" not in text and "--method POST" not in text.replace(
                'POST "repos/$GH_REPO/check-runs"', ""
            )
        else:
            assert guards.HOLD not in text, path.name
