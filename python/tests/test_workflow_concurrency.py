"""No workflow that runs on a push to the default branch can be cancelled there (docs/studio/ci.md#main-runs).

A run on `main` that the next merge cancels leaves a commit with no finished result, and two pull requests that are each
green and break together go unseen. `cancel-in-progress` may be true for a pull request only. A workflow that does want
the newest push to replace the one before says so in a `# cancels-on-main: <reason>` comment above its `concurrency`.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest
import yaml

KIT = Path(__file__).resolve().parents[2]
WORKFLOW_FOLDERS = [KIT / ".github" / "workflows", KIT / "templates" / "repo" / ".github" / "workflows"]
WORKFLOWS = sorted(path for folder in WORKFLOW_FOLDERS for path in folder.glob("*.yml"))
PULL_REQUEST_ONLY = re.compile(r"^\$\{\{\s*github\.event_name\s*==\s*'pull_request'\s*\}\}$")


def runs_on_main(workflow: dict) -> bool:
    # PyYAML reads the key `on` as the boolean True.
    triggers = workflow.get("on", workflow.get(True))
    if isinstance(triggers, str):
        triggers = [triggers]
    if isinstance(triggers, list):
        return "push" in triggers
    if not isinstance(triggers, dict) or "push" not in triggers:
        return False
    branches = (triggers["push"] or {}).get("branches")
    return branches is None or "main" in branches


def cancels_a_push(value) -> bool:
    """True unless `cancel-in-progress` is false, or is the pull-request-only expression (a push gives false)."""
    if value is False:
        return False
    return not (isinstance(value, str) and PULL_REQUEST_ONLY.match(value.strip()))


def concurrency_blocks(workflow: dict):
    yield "workflow", workflow.get("concurrency")
    for name, job in (workflow.get("jobs") or {}).items():
        yield f"job {name}", job.get("concurrency")


def test_the_workflows_are_found():
    assert sum(path.name == "ci.yml" for path in WORKFLOWS) == 2


@pytest.mark.parametrize("path", WORKFLOWS, ids=lambda p: str(p.relative_to(KIT)))
def test_a_run_on_main_is_never_cancelled(path: Path):
    text = path.read_text(encoding="utf-8")
    workflow = yaml.safe_load(text)
    if not runs_on_main(workflow):
        return
    if "# cancels-on-main:" in text:
        return
    for where, block in concurrency_blocks(workflow):
        if isinstance(block, dict) and cancels_a_push(block.get("cancel-in-progress", False)):
            pytest.fail(
                f"{path.relative_to(KIT)} ({where}) cancels a run on main: use "
                "`cancel-in-progress: ${{ github.event_name == 'pull_request' }}` with the commit in the group "
                "(docs/studio/ci.md#main-runs), or explain why in a `# cancels-on-main: <reason>` comment"
            )


def test_the_exemption_is_still_needed():
    # An exemption left behind after the workflow stopped cancelling would hide the next regression.
    for path in WORKFLOWS:
        text = path.read_text(encoding="utf-8")
        if "# cancels-on-main:" not in text:
            continue
        workflow = yaml.safe_load(text)
        assert runs_on_main(workflow), f"{path.relative_to(KIT)} says cancels-on-main but does not run on main"
        assert any(
            isinstance(block, dict) and cancels_a_push(block.get("cancel-in-progress", False))
            for _, block in concurrency_blocks(workflow)
        ), f"{path.relative_to(KIT)} says cancels-on-main but never cancels a push: remove the comment"


@pytest.mark.parametrize(
    ("value", "cancels"),
    [
        (True, True),
        (False, False),
        ("${{ github.event_name == 'pull_request' }}", False),
        ("${{ github.ref != 'refs/heads/main' }}", True),
    ],
)
def test_the_cancel_check_reads_each_form(value, cancels):
    assert cancels_a_push(value) is cancels
