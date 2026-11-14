"""Main green (docs/studio/ci.md#main-runs): the `main-green` check fails on every pull request but the fix forward
while a `CI failing on the default branch` issue is open, so auto-merge turned on earlier cannot land on a red main
(gdstudio #1302). The steps run here under bash against a fake `gh`; what GitHub does with the check is shown on real
pull requests."""

from __future__ import annotations

import base64
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

KIT = Path(__file__).resolve().parents[2]
WORKFLOWS = KIT / ".github" / "workflows"
_spec = importlib.util.spec_from_file_location("groundwork_main_green", KIT / ".github" / "scripts" / "groundwork.py")
groundwork = importlib.util.module_from_spec(_spec)
sys.modules["groundwork_main_green"] = groundwork
_spec.loader.exec_module(groundwork)
sys.path.insert(0, str(KIT / ".claude" / "hooks"))
from guards import red_default  # noqa: E402

CONVENTIONS = yaml.safe_load((KIT / ".github" / "conventions.yml").read_text(encoding="utf-8"))
CHECK = yaml.safe_load((WORKFLOWS / "main-green.yml").read_text(encoding="utf-8"))
SWEEP = yaml.safe_load((WORKFLOWS / "main-green-sweep.yml").read_text(encoding="utf-8"))
FAILURE = yaml.safe_load((WORKFLOWS / "ci-failure.yml").read_text(encoding="utf-8"))
STEP = CHECK["jobs"]["main-green"]["steps"][0]
SWEEP_STEP = SWEEP["jobs"]["sweep"]["steps"][0]
BASH = shutil.which("bash")
# Linux only: the steps run on ubuntu runners, and macOS's bash 3.2 has no `${var,,}`.
needs_bash = pytest.mark.skipif(sys.platform != "linux" or not BASH, reason="the steps run under Linux bash")


# --- the conventions and the ruleset ---


def required_checks(conv) -> list[dict]:
    rules = groundwork.ruleset_wanted(conv)["rules"]
    return next(r for r in rules if r["type"] == "required_status_checks")["parameters"]["required_status_checks"]


def test_the_ruleset_takes_main_green_from_github_actions_only():
    assert {"context": "main-green", "integration_id": 15368} in required_checks(CONVENTIONS)
    assert {"context": "hold", "integration_id": 15368} in required_checks(CONVENTIONS)  # the hold stays


def test_a_red_main_is_not_a_failure_for_pr_status():
    assert CONVENTIONS["merge"]["red_main"]["check"] not in CONVENTIONS["merge"]["required_checks"]


def test_a_game_without_red_main_keeps_its_ruleset():
    merge = {k: v for k, v in CONVENTIONS["merge"].items() if k != "red_main"}
    assert "main-green" not in {c["context"] for c in required_checks({"merge": merge})}


@pytest.mark.parametrize(
    ("red_main", "problem"),
    [
        ({"check": "main-green"}, "needs check and a numeric app_id"),
        ({"check": "build-ok", "app_id": 1}, "stays out of merge.required_checks"),
    ],
)
def test_validate_refuses_a_wrong_red_main(red_main, problem):
    conv = json.loads(json.dumps(CONVENTIONS))
    conv["merge"]["red_main"] = red_main
    assert any(problem in p for p in groundwork.validate(conv))


def test_every_copy_of_the_name_and_the_title_is_the_same():
    check = CONVENTIONS["merge"]["red_main"]["check"]
    assert check in CHECK["jobs"] and f"name={check}" in SWEEP_STEP["run"]
    title = red_default.RED_TITLE
    assert STEP["env"]["RED_TITLE"] == SWEEP_STEP["env"]["RED_TITLE"] == title
    assert f'title="{title}: $WORKFLOW"' in FAILURE["jobs"]["report"]["steps"][0]["run"]
    assert SWEEP["jobs"]["sweep"]["if"].count(f"'{title}'") == 2


def test_both_workflows_judge_a_body_with_the_same_text():
    def fixes_red(script: str) -> str:
        return re.search(r"^fixes_red\(\) \{\n.*?^\}\n", script, re.MULTILINE | re.DOTALL).group(0)

    assert fixes_red(STEP["run"]) == fixes_red(SWEEP_STEP["run"])


# --- the check: what keeps a required check honest (as hold.yml) ---


def test_it_runs_on_every_pull_request_and_when_the_body_changes():
    events = CHECK[True]["pull_request_target"]  # YAML reads the key `on` as a boolean
    assert {"opened", "reopened", "synchronize", "edited"} <= set(events["types"])
    assert set(CHECK[True]) == {"pull_request_target"}
    assert not {"paths", "paths-ignore", "branches", "branches-ignore"} & set(events)


def test_no_if_can_turn_a_failure_into_a_skip():
    job = CHECK["jobs"]["main-green"]
    assert "if" not in job and all("if" not in step for step in job["steps"])


def test_it_runs_nothing_from_the_pull_request():
    assert len(CHECK["jobs"]["main-green"]["steps"]) == 1 and "uses" not in STEP


def test_it_reads_the_issues_and_the_body_when_it_runs():
    assert "set -euo pipefail" in STEP["run"] and "gh issue list --state open" in STEP["run"]
    assert "repos/$GH_REPO/pulls/$NUMBER" in STEP["run"] and "event.pull_request.body" not in STEP["run"]


def test_the_newest_event_wins():
    assert CHECK["concurrency"]["cancel-in-progress"] is True
    assert "pull_request.number" in CHECK["concurrency"]["group"]


# --- the sweep ---


def test_the_sweep_runs_when_a_red_issue_changes_and_by_hand():
    on = SWEEP[True]
    assert {"opened", "closed", "reopened", "edited", "deleted"} <= set(on["issues"]["types"])
    assert "workflow_dispatch" in on


def test_the_sweep_can_write_only_checks():
    perms = SWEEP["jobs"]["sweep"]["permissions"]
    assert perms["checks"] == "write" and {k for k, v in perms.items() if v == "write"} == {"checks"}
    assert all("uses" not in step for step in SWEEP["jobs"]["sweep"]["steps"])


def test_the_sweep_waits_for_checks_still_going():
    assert "gh run list --workflow main-green.yml" in SWEEP_STEP["run"]


def test_ci_failure_dispatches_the_sweep_after_filing_the_issue():
    """An issue filed with the workflow's GITHUB_TOKEN starts no `issues` workflow; a dispatch does."""
    script = FAILURE["jobs"]["report"]["steps"][0]["run"]
    assert script.index("gh issue create") < script.index("gh workflow run main-green-sweep.yml")
    assert FAILURE["permissions"]["actions"] == "write"


# --- the steps themselves, against a fake gh ---


def fake_gh(tmp_path: Path, red: list[int], bodies: dict[int, str], fail: bool = False) -> dict[str, str]:
    """A `gh` that prints what the real one would after `--jq`: the open red issues, a body, the open pull requests.
    Check runs written are appended to `posted`."""

    def write(name: str, text: str) -> None:  # bytes: Windows text mode would end each line with \r
        (tmp_path / name).write_bytes(text.encode("utf-8"))

    write("red", "".join(f"{n}\n" for n in red))
    rows = "".join(f"{n}\t{n:040x}\t{base64.b64encode(body.encode()).decode()}\n" for n, body in sorted(bodies.items()))
    write("prs", rows)
    for n, body in bodies.items():
        write(f"body{n}", body)
    script = f"""#!/bin/bash
{"echo 'API rate limit' >&2; exit 1" if fail else ""}
here={tmp_path.as_posix()!r}
case "$1 $2" in
  "issue list") cat "$here/red" ;;
  "run list") echo 0 ;;
  "pr list") cat "$here/prs" ;;
  "api repos/"*) n=${{2##*/}}; cat "$here/body$n" ;;
  "api --method") echo "$@" >> "$here/posted" ;;
  *) echo "unexpected gh $*" >&2; exit 2 ;;
esac
"""
    gh = tmp_path / "gh"
    gh.write_bytes(script.encode("utf-8"))
    gh.chmod(0o755)
    return {"PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}", "GH_REPO": "Ryubara/gdstudio"}


def run(step: dict, env: dict[str, str]) -> subprocess.CompletedProcess:
    env = {**step["env"], **env}
    env.pop("GH_TOKEN", None)
    return subprocess.run([BASH, "-c", step["run"]], env=env, capture_output=True, text=True, timeout=60)


@needs_bash
@pytest.mark.parametrize(
    ("red", "body", "code", "text"),
    [
        ([], "Adds a thing.", 0, "the default branch is green"),  # the issue closed: it merges
        ([1279], "Adds a thing.", 1, "The default branch is red (#1279)"),  # held while it is open
        ([1279], "Fixes #1279", 0, "its fix forward"),
        ([1279], "fixes: Ryubara/GDStudio#1279", 0, "its fix forward"),
        ([1279, 1280], "Summary\n\nCloses #1280 and more", 0, "its fix forward"),  # either fix lands
        ([1279], "Refs #1279, after #1279 lands", 1, "is red"),  # a mention is no fix
        ([1279], "Fixes other/repo#1279", 1, "is red"),
        ([1279], "Prefixes #1279", 1, "is red"),
        ([1279], "Fixes #12790", 1, "is red"),
    ],
)
def test_the_check_step(tmp_path, red, body, code, text):
    done = run(STEP, {**fake_gh(tmp_path, red, {7: body}), "NUMBER": "7"})
    assert done.returncode == code, done.stdout + done.stderr
    assert text in done.stdout


@needs_bash
def test_a_red_main_nobody_could_read_stays_red(tmp_path):
    done = run(STEP, {**fake_gh(tmp_path, [1279], {7: "x"}, fail=True), "NUMBER": "7"})
    assert done.returncode != 0


@needs_bash
def test_the_sweep_holds_every_pull_request_but_the_fix_then_frees_them(tmp_path):
    bodies = {7: "Adds a thing.", 8: "Fixes #1279"}
    env = {**fake_gh(tmp_path, [1279], bodies), "BASE": "main"}
    done = run(SWEEP_STEP, env)
    assert done.returncode == 0, done.stdout + done.stderr
    posted = (tmp_path / "posted").read_text(encoding="utf-8").splitlines()
    assert f"head_sha={7:040x}" in posted[0] and "conclusion=failure" in posted[0] and "name=main-green" in posted[0]
    assert f"head_sha={8:040x}" in posted[1] and "conclusion=success" in posted[1]

    (tmp_path / "posted").unlink()
    done = run(SWEEP_STEP, {**fake_gh(tmp_path, [], bodies), "BASE": "main"})  # the issue closed
    assert done.returncode == 0, done.stdout + done.stderr
    posted = (tmp_path / "posted").read_text(encoding="utf-8").splitlines()
    assert len(posted) == 2 and all("conclusion=success" in line for line in posted)


# --- ci-failure's clear: a green run on main's head closes its red issue (kit #1472) ---

CLEAR = FAILURE["jobs"]["clear"]
CLEAR_STEP = CLEAR["steps"][0]


def test_clear_runs_on_a_green_push_run_of_the_default_branch_only():
    condition = " ".join(CLEAR["if"].split())
    assert "conclusion == 'success'" in condition and "event == 'push'" in condition
    assert "head_branch == github.event.repository.default_branch" in condition
    assert f'title="{red_default.RED_TITLE}: $WORKFLOW"' in CLEAR_STEP["run"]


def test_clear_closes_then_dispatches_the_sweep():
    """A close made with the workflow's GITHUB_TOKEN starts no `issues` workflow either."""
    script = CLEAR_STEP["run"]
    assert script.index("gh issue close") < script.index("gh workflow run main-green-sweep.yml")


def fake_clear_gh(tmp_path: Path, issue: str, head: str) -> dict[str, str]:
    """A `gh` that knows one open red issue (or none) and the default branch's head; calls go to `calls`."""
    script = f"""#!/bin/bash
here={tmp_path.as_posix()!r}
echo "$*" >> "$here/calls"
case "$1 $2" in
  "issue list") echo {issue!r} ;;
  "api repos/"*) echo {head!r} ;;
  "issue close"|"workflow run") ;;
  *) echo "unexpected gh $*" >&2; exit 2 ;;
esac
"""
    gh = tmp_path / "gh"
    gh.write_bytes(script.encode("utf-8"))
    gh.chmod(0o755)
    return {
        "PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}",
        "GH_REPO": "Ryubara/gdstudio",
        "WORKFLOW": "ci",
        "RUN_URL": "https://example.invalid/run/1",
        "SHA": "a" * 40,
        "BASE": "main",
    }


@needs_bash
@pytest.mark.parametrize(
    ("issue", "head", "closed"),
    [
        ("1279", "a" * 40, True),  # the head is green: the issue closes and the sweep runs
        ("1279", "b" * 40, False),  # main moved on: the newer commit's own run decides
        ("", "a" * 40, False),  # no red issue for this workflow
    ],
)
def test_the_clear_step(tmp_path, issue, head, closed):
    env = fake_clear_gh(tmp_path, issue, head)
    done = subprocess.run([BASH, "-c", CLEAR_STEP["run"]], env=env, capture_output=True, text=True, timeout=60)
    assert done.returncode == 0, done.stdout + done.stderr
    calls = (tmp_path / "calls").read_text(encoding="utf-8")
    assert ("issue close 1279 --reason completed" in calls) is closed
    assert ("workflow run main-green-sweep.yml --ref main" in calls) is closed
