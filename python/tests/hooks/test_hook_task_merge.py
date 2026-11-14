"""The task-agent merge guard (docs/studio/hooks.md#what-it-refuses, gdstudio #1466): a subagent's call (it carries
`agent_id`) never lands a pull request, since the coordinator lands them from its queue
(docs/studio/landing.md#landing). The main session, a session started as an agent (`agent_type` alone) and
`gh pr merge --disable-auto` pass."""

from __future__ import annotations

import pytest
from hook_support import denied, patch, shell

TASK_AGENT = {"agent_id": "a1b2", "agent_type": "godot-engineer"}
REFUSAL = "landing.md#landing"


@pytest.fixture(autouse=True)
def nothing_held(monkeypatch):
    """No pull request carries the hold, and the hold guard never asks GitHub."""
    patch(monkeypatch, "held", lambda target, repo, cwd: False)


def as_task_agent(command: str, cwd) -> dict:
    return {**shell(command, cwd), **TASK_AGENT}


@pytest.mark.parametrize(
    "command",
    [
        "gh pr merge 12 --squash",
        "gh pr merge 12 --squash --auto -R o/r",
        "gh pr merge --auto",
        "gh pr merge https://github.com/o/r/pull/12 --merge --delete-branch",
        "git push && gh pr merge 12 --squash",
        "gh api -X PUT repos/o/r/pulls/12/merge",
        "gh api --method put repos/o/r/pulls/12/merge -f merge_method=squash",
        "gh api repos/o/r/pulls/12/merge -f merge_method=squash",  # a field makes it a POST, as gh reads it
        "gh api graphql -f query='mutation { enablePullRequestAutoMerge(input: {}) { clientMutationId } }'",
    ],
)
def test_a_task_agents_merge_call_is_refused(command, tmp_path):
    reason = denied(as_task_agent(command, tmp_path))
    assert "task agent makes no merge call" in reason and REFUSAL in reason and "green head SHA" in reason


@pytest.mark.parametrize(
    "command",
    [
        "gh pr merge 12 --disable-auto",
        "gh pr merge --disable-auto -R o/r",
        "gh api repos/o/r/pulls/12/merge",  # a GET asks whether it merged
        "gh pr view 12 --json mergeStateStatus",
        "gh pr checks 12",
    ],
)
def test_a_task_agent_may_turn_auto_merge_off_and_read(command, tmp_path):
    assert REFUSAL not in denied(as_task_agent(command, tmp_path))


@pytest.mark.parametrize(
    "extra",
    [{}, {"agent_type": "godot-engineer"}],  # the main session; a session started with `--agent` carries no agent_id
)
def test_the_main_session_still_merges(extra, tmp_path):
    for command in (
        "gh pr merge 12 --squash",
        "gh pr merge 12 --squash --auto",
        "gh api -X PUT repos/o/r/pulls/12/merge",
    ):
        assert denied({**shell(command, tmp_path), **extra}) == ""
