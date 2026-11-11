"""Issue order (docs/studio/hooks.md#issues): a task agent starts on a started issue, with `Read:` lines, and the
labels of progress are not set by hand."""

from __future__ import annotations

from hook_support import CONFIG, READ, agent_call, denied, dispatch, guards, patch, shell, start_in_ledger


def test_a_task_agent_needs_a_started_issue(workspace):
    reason = denied(agent_call(workspace, "godot-engineer", "Fix the crosshair.\nIssue: Ryubara/deadnight#523"))
    assert "was not started with `gds issue start`" in reason and "Ryubara/deadnight#523" in reason
    assert "gds issue start Ryubara/deadnight#523 --agent <name>" in reason
    none = denied(agent_call(workspace, "backend-engineer", "Build the lobby API."))
    assert "names none" in none and "`Issue: <owner/repo>#N`" in none and "`PR: <owner/repo>#N`" in none
    for kind in ("godot-engineer", "backend-engineer", "blender-artist", "claude"):
        assert denied(agent_call(workspace, kind, "no issue here")) != ""


def test_a_started_issue_lets_the_agent_start(workspace):
    start_in_ledger(workspace, "Ryubara/deadnight#523")
    for prompt in (
        "Issue: Ryubara/deadnight#523\nBuild the outline shader.",
        "Task text\n- Issue: `Ryubara/deadnight#523`",
        "issue: ryubara/DEADNIGHT#523 (lower case is fine)",
    ):
        assert denied(agent_call(workspace, "godot-engineer", prompt + READ)) == ""
    assert "was not started" in denied(agent_call(workspace, "godot-engineer", "Issue: Ryubara/deadnight#524"))
    assert "was not started" in denied(agent_call(workspace, "godot-engineer", "Issue: Ryubara/gdstudio#523"))


def test_the_issue_must_head_a_line_not_sit_in_the_middle_of_prose(workspace):
    start_in_ledger(workspace, "Ryubara/deadnight#523")
    assert "names none" in denied(agent_call(workspace, "godot-engineer", "See Issue: Ryubara/deadnight#523 maybe"))


def test_helpers_and_reviewers_need_no_issue(workspace):
    for kind in ("Explore", "Plan", "fork", "web-fetch", "claude-code-guide", "reviewer"):
        assert denied(agent_call(workspace, kind, "look at this")) == ""


def test_work_on_an_existing_pull_request_names_it(workspace, monkeypatch):
    states = {"7": "OPEN", "8": "MERGED", "9": "MISSING", "10": None}
    patch(monkeypatch, "pr_state", lambda repo, number: states[number])
    assert (
        denied(agent_call(workspace, "godot-engineer", "Resolve the conflicts.\nPR: Ryubara/deadnight#7" + READ)) == ""
    )
    assert denied(agent_call(workspace, "reviewer", "PR: Ryubara/deadnight#7")) == ""
    assert "not an open pull request" in denied(agent_call(workspace, "godot-engineer", "PR: Ryubara/deadnight#8"))
    assert "not an open pull request" in denied(agent_call(workspace, "godot-engineer", "PR: Ryubara/deadnight#9"))
    # gh cannot tell (offline): the guard lets the call through rather than lock the session out
    assert denied(agent_call(workspace, "godot-engineer", "PR: Ryubara/deadnight#10" + READ)) == ""


def test_a_pull_request_line_does_not_stand_in_for_an_unstarted_issue(workspace, monkeypatch):
    patch(monkeypatch, "pr_state", lambda repo, number: "OPEN")
    prompt = "PR: Ryubara/deadnight#7\nIssue: Ryubara/deadnight#523"
    assert "Ryubara/deadnight#523 was not started" in denied(agent_call(workspace, "godot-engineer", prompt))


def test_no_enforcement_outside_a_workspace_or_when_switched_off(tmp_path, workspace):
    assert denied(agent_call(tmp_path.parent, "godot-engineer", "no issue")) == ""
    off = {**CONFIG, "issues": {**CONFIG["issues"], "enforce": False}, "brief": {"enforce": False}}
    assert dispatch.answer(agent_call(workspace, "godot-engineer", "no issue"), off) is None
    issue_off = {**CONFIG, "issues": {**CONFIG["issues"], "enforce": False}}
    assert "names none" in denied_with(agent_call(workspace, "godot-engineer", "no issue"), issue_off)


def denied_with(payload: dict, config: dict) -> str:
    out = dispatch.answer(payload, config)
    return out["hookSpecificOutput"]["permissionDecisionReason"] if out else ""


def test_a_task_agent_needs_read_lines_naming_sections_that_exist(workspace):
    """gdstudio #771: the coordinator runs `gds brief` and puts its `Read:` lines in the prompt; the guard refuses a
    prompt with none, and one naming a section the kit's docs do not have."""
    start_in_ledger(workspace, "Ryubara/deadnight#523")
    none = denied(agent_call(workspace, "godot-engineer", "Issue: Ryubara/deadnight#523\nBuild it."))
    assert "names none" in none and "gds brief Ryubara/deadnight#523" in none and "Read: <page>.md#<anchor>" in none
    words = denied(agent_call(workspace, "godot-engineer", "Issue: Ryubara/deadnight#523\nRead: the hooks page"))
    assert "names none" in words
    wrong = "Issue: Ryubara/deadnight#523\nRead: studio/hooks.md#docs, studio/hooks.md#nope\nRead: gone.md#x"
    reason = denied(agent_call(workspace, "godot-engineer", wrong))
    assert "do not exist" in reason and "studio/hooks.md#nope, gone.md#x" in reason and "#docs," not in reason
    for prompt in (
        "Issue: Ryubara/deadnight#523\nRead: docs/studio/hooks.md#docs",
        "Issue: Ryubara/deadnight#523\n- **Read:** [hooks](../studio/hooks.md#docs)",
        "Issue: Ryubara/deadnight#523\nRead:\n- studio/hooks.md#docs\n- studio/starting-work.md#starting-an-agent",
    ):
        assert denied(agent_call(workspace, "godot-engineer", prompt)) == "", prompt
    listed = "Issue: Ryubara/deadnight#523\nRead:\n- studio/hooks.md#docs\n- studio/hooks.md#nope"
    assert "studio/hooks.md#nope" in denied(agent_call(workspace, "godot-engineer", listed))


def test_read_lines_are_not_asked_of_helpers_the_reviewer_or_when_switched_off(workspace):
    for kind in ("Explore", "fork", "reviewer"):
        assert denied(agent_call(workspace, kind, "look")) == ""
    start_in_ledger(workspace, "Ryubara/deadnight#523")
    off = {**CONFIG, "brief": {"enforce": False}}
    assert dispatch.answer(agent_call(workspace, "godot-engineer", "Issue: Ryubara/deadnight#523"), off) is None


def test_read_lines_need_only_their_form_when_the_kit_cannot_be_loaded(workspace, monkeypatch):
    start_in_ledger(workspace, "Ryubara/deadnight#523")
    patch(monkeypatch, "lessons_module", lambda kit: None)
    assert denied(agent_call(workspace, "godot-engineer", "Issue: Ryubara/deadnight#523\nRead: x.md#y")) == ""
    assert "names none" in denied(agent_call(workspace, "godot-engineer", "Issue: Ryubara/deadnight#523"))


def test_refused_agent_types_get_one_reason_not_two(workspace):
    reason = denied(agent_call(workspace, "general-purpose", "x"))
    assert "no instructions" in reason and "names none" not in reason


def test_a_games_local_config_can_exempt_an_agent(workspace):
    local = {**CONFIG, "issues": {**CONFIG["issues"], "exempt": ["reviewer", "godot-engineer"]}}
    assert dispatch.answer(agent_call(workspace, "godot-engineer", "no issue"), local) is None


def test_ledger_keys_agree_between_hook_and_tool():
    from gds_tools import issues

    assert guards.ledger_key("Ryubara/Deadnight", "523") == issues.ledger_key("Ryubara/Deadnight", 523)


def test_the_label_of_progress_is_not_set_by_hand(tmp_path):
    by_hand = "`S-in-progress` is set only by `gds issue start"
    assert by_hand in denied(shell("gh issue edit 523 --add-label S-in-progress", tmp_path))
    assert by_hand in denied(shell("gh issue edit 523 -R Ryubara/deadnight --add-label=S-in-progress", tmp_path))
    assert by_hand in denied(shell('gh issue edit 523 --add-label "bug,S-in-progress"', tmp_path))
    assert by_hand in denied(shell("gh issue create --title x --body y --label S-in-progress", tmp_path))
    assert by_hand in denied(shell("gh issue create -l task -l S-in-progress", tmp_path))
    assert by_hand in denied(shell("cd x && gh issue edit 5 --add-label S-in-progress", tmp_path))
    assert by_hand in denied(shell("gh api repos/o/r/issues/5/labels -f 'labels[]=S-in-progress'", tmp_path))
    assert by_hand in denied(
        {**shell("& gh issue edit 5 --add-label S-in-progress", tmp_path), "tool_name": "PowerShell"}
    )


def test_a_pull_request_never_carries_the_progress_label(tmp_path):
    reason = "a pull request is in progress by existing"
    assert reason in denied(shell("gh pr edit 525 --add-label S-in-progress", tmp_path))
    assert reason in denied(shell("gh pr create --fill --label S-in-progress", tmp_path))


def test_only_the_maintainer_sets_p_critical(tmp_path):
    reason = "only the maintainer sets P-critical"
    assert reason in denied(shell("gh issue edit 400 --add-label P-critical", tmp_path))
    assert reason in denied(shell("gh issue create --label task,P-critical --title x", tmp_path))
    assert reason in denied(shell("gh pr edit 5 --add-label P-critical", tmp_path))


def test_other_label_work_is_allowed(tmp_path):
    assert denied(shell("gh issue edit 5 --add-label S-blocked", tmp_path)) == ""
    assert denied(shell("gh issue edit 5 --remove-label S-in-progress --add-label S-ready-to-start", tmp_path)) == ""
    assert denied(shell("gh issue create --label task --label A-hooks --title x", tmp_path)) == ""
    assert denied(shell("gh issue list --label S-in-progress", tmp_path)) == ""
    assert denied(shell("gh api 'repos/o/r/issues?labels=S-in-progress' --method GET", tmp_path)) == ""
    assert denied(shell("gh pr list --label P-critical", tmp_path)) == ""
    assert denied(shell("uv run --project python gds issue start Ryubara/deadnight#523 --agent a", tmp_path)) == ""
    assert denied(shell("echo 'gh issue edit 5 --add-label S-in-progress' > note.txt", tmp_path)) == ""
