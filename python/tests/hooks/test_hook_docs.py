"""Docs ship with the change (docs/studio/hooks.md#docs): kit branches are published, and a report names what it read
and the sections its mistakes updated."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from hook_support import (
    CONFIG,
    HOOKS,
    READ,
    READ_REPORT,
    REPORT,
    _kit_worktree,
    agent_call,
    context,
    denied,
    dispatch,
    guards,
    patch,
    start_in_ledger,
    stop_payload,
    subagent_stop_payload,
)


def test_subagent_start_tells_the_agent_to_read_its_prompts_sections_and_injects_none(workspace):
    """gdstudio #771: the prompt names the sections (`Read:`), so SubagentStart no longer guesses them from a note of
    the Agent guard; no note file is written."""
    start_in_ledger(workspace, "Ryubara/deadnight#523")
    assert denied(agent_call(workspace, "godot-engineer", "Issue: Ryubara/deadnight#523" + READ)) == ""
    assert not (workspace / "cache" / "subagent-pending.json").exists()
    text = context("SubagentStart", workspace, agent_type="godot-engineer", agent_id="a1")
    assert "learning loop" in text and "`Read:` lines" in text and "`Docs gaps:`" in text
    assert "Sections of the docs closest" not in text and "Mistakes already made in your areas" not in text
    assert not hasattr(guards, "note_agent_start") and not hasattr(guards, "area_checks")


def test_stop_holds_back_kit_branches_with_commits_and_no_pull_request(workspace, monkeypatch):
    tree = _kit_worktree(workspace, "docs-a", 2)
    _kit_worktree(workspace, "docs-b", 1)
    _kit_worktree(workspace, "docs-c", 0)  # nothing ahead: nothing to publish
    patch(monkeypatch, "kit_pr_heads", lambda repo: {"docs-b": ""})  # b has a pull request
    out = dispatch.answer(stop_payload(tree), CONFIG)
    assert out["decision"] == "block" and "docs-a" in out["reason"] and "docs-b" not in out["reason"]
    assert "docs-c" not in out["reason"] and "open its pull request now" in out["reason"]
    assert dispatch.answer(stop_payload(tree, stop_hook_active=True), CONFIG) is None  # held once only


def test_stop_lets_go_when_every_branch_has_a_pull_request_or_github_is_unreachable(workspace, monkeypatch):
    _kit_worktree(workspace, "docs-a", 1)
    patch(monkeypatch, "kit_pr_heads", lambda repo: {"docs-a": ""})
    assert dispatch.answer(stop_payload(workspace), CONFIG) is None
    patch(monkeypatch, "kit_pr_heads", lambda repo: None)  # cannot ask: a guard that cannot look lets go
    assert dispatch.answer(stop_payload(workspace), CONFIG) is None


def _session_transcript(path: Path, prompt: str, commands: tuple[str, ...] = ()) -> Path:
    """An agent's transcript: its prompt, then a Bash call for each command."""
    lines = [{"type": "user", "message": {"role": "user", "content": prompt}}]
    for command in commands:
        block = {"type": "tool_use", "name": "Bash", "input": {"command": command}}
        lines.append({"type": "assistant", "message": {"role": "assistant", "content": [block]}})
    path.write_text("\n".join(json.dumps(line) for line in lines), encoding="utf-8")
    return path


def _two_agents(workspace: Path, monkeypatch) -> tuple[Path, Path]:
    """Two agents' kit worktrees with unpublished commits, and no pull request for either."""
    mine = _kit_worktree(workspace, "docs-mine", 1)
    theirs = _kit_worktree(workspace, "docs-theirs", 2)
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    return mine, theirs


def test_a_stop_names_only_the_branch_of_the_worktree_it_works_in(workspace, monkeypatch):
    mine, theirs = _two_agents(workspace, monkeypatch)
    for tree, own, other in ((mine, "docs-mine", "docs-theirs"), (theirs, "docs-theirs", "docs-mine")):
        for payload in (stop_payload(tree), subagent_stop_payload(tree, "Done. Mistakes: none")):
            reason = dispatch.answer(payload, CONFIG)["reason"]
            assert own in reason and other not in reason, reason


def test_an_agent_owns_the_worktree_its_prompt_and_the_ledger_name(workspace, tmp_path_factory, monkeypatch):
    mine, theirs = _two_agents(workspace, monkeypatch)
    notes = tmp_path_factory.mktemp("transcripts")
    ledger = workspace / "cache" / "issues-started.json"
    ledger.parent.mkdir()
    started = {"ryubara/gdstudio#7": {"agent": "godot-engineer", "worktree": mine.as_posix()}}
    ledger.write_text(json.dumps({"started": started}), encoding="utf-8")
    for prompt in (f"Worktree: {mine.as_posix()}\nIssue: Ryubara/gdstudio#8", "Issue: Ryubara/gdstudio#7"):
        transcript = _session_transcript(notes / "agent.jsonl", prompt)
        payload = subagent_stop_payload(workspace, "Done. Mistakes: none", agent_transcript_path=str(transcript))
        reason = dispatch.answer(payload, CONFIG)["reason"]
        assert "docs-mine" in reason and "docs-theirs" not in reason, reason


def test_an_agent_owns_the_worktrees_it_committed_in_or_added(workspace, tmp_path_factory, monkeypatch):
    mine, theirs = _two_agents(workspace, monkeypatch)
    notes = tmp_path_factory.mktemp("transcripts")
    commands = (
        f"git -C {theirs.as_posix()} log --oneline",  # looked at, not committed in
        f'git -C "{mine.as_posix()}" commit -m "docs: Add a page"',
    )
    transcript = _session_transcript(notes / "agent.jsonl", "Fix #5.", commands)
    payload = subagent_stop_payload(workspace, "Done. Mistakes: none", agent_transcript_path=str(transcript))
    reason = dispatch.answer(payload, CONFIG)["reason"]
    assert "docs-mine" in reason and "docs-theirs" not in reason, reason


def test_a_session_that_owns_no_branch_is_not_held_for_other_agents_branches(workspace, tmp_path_factory, monkeypatch):
    _two_agents(workspace, monkeypatch)
    notes = tmp_path_factory.mktemp("transcripts")
    eval_run = _session_transcript(notes / "eval.jsonl", "This is an eval run. Work only in the eval folder.")
    payload = subagent_stop_payload(workspace, REPORT, agent_transcript_path=str(eval_run))
    assert dispatch.answer(payload, CONFIG) is None  # an eval run: its report is not replaced
    assert dispatch.answer(stop_payload(workspace), CONFIG) is None  # the coordinator between tasks


def _squash_merged_worktree(workspace: Path, name: str) -> tuple[Path, str]:
    """A kit branch with two commits whose pull request squash-merged: origin/main holds one commit with the same
    changes and a different hash. Returns the worktree and the merged tip."""
    tree = workspace / "worktrees" / "gdstudio" / name
    tree.mkdir(parents=True)

    def run(*a):
        return subprocess.run(
            ["git", "-C", str(tree), "-c", "user.email=t@t", "-c", "user.name=t", *a],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def commit(file: str, message: str):
        (tree / file).write_text(file, encoding="utf-8")
        run("add", file)
        run("commit", "-m", message)

    run("init", "-b", "main")
    commit("base.md", "base")
    run("switch", "-q", "-c", name)
    commit("a.md", "a")
    commit("b.md", "b")
    tip = run("rev-parse", "HEAD")
    run("switch", "-q", "main")
    run("merge", "--squash", name)
    run("commit", "-m", "squash of a and b")
    run("update-ref", "refs/remotes/origin/main", "HEAD")
    run("switch", "-q", name)
    return tree, tip


def test_stop_names_a_commit_pushed_to_a_branch_after_its_pull_request_merged(workspace, monkeypatch):
    tree, tip = _squash_merged_worktree(workspace, "docs-late")
    patch(monkeypatch, "kit_pr_heads", lambda repo: {"docs-late": tip})
    assert dispatch.answer(stop_payload(tree), CONFIG) is None  # only its squashed commits: nothing is lost
    (tree / "late.md").write_text("a second lesson", encoding="utf-8")
    for args in (["add", "late.md"], ["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-m", "late"]):
        subprocess.run(["git", "-C", str(tree), *args], check=True, capture_output=True)
    out = dispatch.answer(stop_payload(tree), CONFIG)
    assert out["decision"] == "block" and "docs-late" in out["reason"] and tip[:9] in out["reason"]
    assert "after their pull request merged" in out["reason"] and "cherry-pick" in out["reason"]
    assert "no pull request" not in out["reason"]
    assert dispatch.answer(stop_payload(tree, stop_hook_active=True), CONFIG) is None
    patch(monkeypatch, "kit_pr_heads", lambda repo: {"docs-late": ""})  # an open pull request covers it
    assert dispatch.answer(stop_payload(tree), CONFIG) is None
    patch(monkeypatch, "kit_pr_heads", lambda repo: None)  # cannot ask: let go
    assert dispatch.answer(stop_payload(tree), CONFIG) is None


def test_a_late_commit_already_on_main_by_patch_id_is_not_named(workspace, monkeypatch):
    tree, tip = _squash_merged_worktree(workspace, "docs-moved")

    def run(*a):
        subprocess.run(
            ["git", "-C", str(tree), "-c", "user.email=t@t", "-c", "user.name=t", *a], check=True, capture_output=True
        )

    (tree / "late.md").write_text("late", encoding="utf-8")
    run("add", "late.md")
    run("commit", "-m", "late")
    run("switch", "-q", "main")
    run("cherry-pick", "docs-moved")  # the same change landed on main through a new pull request
    run("update-ref", "refs/remotes/origin/main", "HEAD")
    run("switch", "-q", "docs-moved")
    patch(monkeypatch, "kit_pr_heads", lambda repo: {"docs-moved": tip})
    assert dispatch.answer(stop_payload(tree), CONFIG) is None


def test_a_late_commit_squashed_with_others_into_main_is_not_named(workspace, monkeypatch):
    tree, tip = _squash_merged_worktree(workspace, "docs-rescued")

    def run(*a):
        subprocess.run(
            ["git", "-C", str(tree), "-c", "user.email=t@t", "-c", "user.name=t", *a], check=True, capture_output=True
        )

    (tree / "late.md").write_text("late", encoding="utf-8")
    run("add", "late.md")
    run("commit", "-m", "late")
    run("switch", "-q", "main")  # a new pull request squashed the late file with another lesson: a new patch id
    (tree / "late.md").write_text("late", encoding="utf-8")
    (tree / "other.md").write_text("another lesson", encoding="utf-8")
    run("add", "late.md", "other.md")
    run("commit", "-m", "squash of late and other")
    run("update-ref", "refs/remotes/origin/main", "HEAD")
    run("switch", "-q", "docs-rescued")
    cherry = subprocess.run(
        ["git", "-C", str(tree), "cherry", "origin/main", "HEAD", tip], capture_output=True, text=True
    ).stdout
    assert cherry.startswith("+ ")  # by patch id alone it would still look stranded
    patch(monkeypatch, "kit_pr_heads", lambda repo: {"docs-rescued": tip})
    assert dispatch.answer(stop_payload(tree), CONFIG) is None


def test_the_pr_heads_map_keeps_the_latest_merged_tip_and_lets_an_open_pull_request_cover(monkeypatch):
    prs = [
        {"headRefName": "a", "state": "MERGED", "headRefOid": "old", "mergedAt": "2026-11-01T00:00:00Z"},
        {"headRefName": "a", "state": "MERGED", "headRefOid": "new", "mergedAt": "2026-11-02T00:00:00Z"},
        {"headRefName": "b", "state": "MERGED", "headRefOid": "x", "mergedAt": "2026-11-01T00:00:00Z"},
        {"headRefName": "b", "state": "OPEN", "headRefOid": "y", "mergedAt": None},
        {"headRefName": "c", "state": "CLOSED", "headRefOid": "z", "mergedAt": None},
    ]
    done = subprocess.CompletedProcess([], 0, stdout=json.dumps(prs), stderr="")
    monkeypatch.setattr(guards.subprocess, "run", lambda *a, **k: done)
    assert guards.kit_pr_heads("o/r") == {"a": "new", "b": ""}


MISTAKES_REPORT = (
    "PR opened.\n\n## Mistakes\n\n- I trusted the cached import and the web build hung.\n\n## Next\n\nnothing"
)


def test_a_report_of_finished_work_names_what_was_read_and_the_gaps(workspace, monkeypatch):
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    bare = "Done: https://github.com/Ryubara/deadnight/pull/412\n\nMistakes: none"
    out = dispatch.answer(subagent_stop_payload(workspace, bare), CONFIG)
    assert out["decision"] == "block" and "`Read: <page>.md#<anchor>, ...`" in out["reason"]
    assert "`Docs gaps: none`" in out["reason"]
    only_read = bare + "\n\nRead: studio/hooks.md#docs"
    reason = dispatch.answer(subagent_stop_payload(workspace, only_read), CONFIG)["reason"]
    assert "Docs gaps:" in reason and "`Read: <page>.md#<anchor>, ...`" not in reason
    gaps = bare + "\n\n**Read:** studio/hooks.md#docs\n**Docs gaps:** studio/hooks.md#docs: says nothing of briefs"
    assert dispatch.answer(subagent_stop_payload(workspace, gaps), CONFIG) is None
    assert dispatch.answer(subagent_stop_payload(workspace, bare, stop_hook_active=True), CONFIG) is None  # once
    blocked = "Blocked: the Railway token expired."
    assert dispatch.answer(subagent_stop_payload(workspace, blocked), CONFIG) is None  # not finished work
    for kind in ("reviewer", "Explore"):
        assert dispatch.answer(subagent_stop_payload(workspace, bare, agent_type=kind), CONFIG) is None
    off = {**CONFIG, "brief": {"report": False}}
    assert dispatch.answer(subagent_stop_payload(workspace, bare), off) is None


def test_an_agent_may_not_finish_with_mistakes_and_no_section(workspace, monkeypatch):
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    out = dispatch.answer(subagent_stop_payload(workspace, MISTAKES_REPORT), CONFIG)
    assert out["decision"] == "block" and "names no topic section that your kit branch updates" in out["reason"]
    assert "Mistakes: none" in out["reason"] and "gds learn" in out["reason"]
    held = subagent_stop_payload(workspace, MISTAKES_REPORT, stop_hook_active=True)
    assert dispatch.answer(held, CONFIG) is None


def _page_on_branch(workspace: Path, page: str, text: str) -> Path:
    """A kit worktree whose branch changes `page` against its origin/main."""
    tree = _kit_worktree(workspace, "rule-branch", 0)
    path = tree / "docs" / page
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("# Page\n\n## Imports {#imports}\n\nold\n", encoding="utf-8")
    git = ["git", "-C", str(tree), "-c", "user.email=t@t", "-c", "user.name=t"]
    subprocess.run([*git, "add", "-A"], check=True, capture_output=True)
    subprocess.run([*git, "commit", "-m", "base"], check=True, capture_output=True)
    subprocess.run([*git, "update-ref", "refs/remotes/origin/main", "HEAD"], check=True, capture_output=True)
    path.write_text(text, encoding="utf-8")
    return tree


def test_a_named_section_the_branch_edits_satisfies_the_report(workspace, monkeypatch):
    """The rule was written into the section (gdstudio #769): the report names it as page.md#anchor, a kit worktree has
    that anchor, and its branch changes the page against origin/main. An old lesson file no longer counts."""
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    report = MISTAKES_REPORT + "\n\nRule: docs/engines/godot/web-export.md#imports (kit PR #120)" + READ_REPORT
    assert "names no topic section" in dispatch.answer(subagent_stop_payload(workspace, report), CONFIG)["reason"]
    rule = "\n- **Approach:** x. **Watch out for:** y. **Seen:** Deadnight #1, 2026-11-07.\n"
    _page_on_branch(workspace, "engines/godot/web-export.md", "# Page\n\n## Imports {#imports}\n\nold\n" + rule)
    assert dispatch.answer(subagent_stop_payload(workspace, report), CONFIG) is None
    wrong = MISTAKES_REPORT + "\n\nRule: docs/engines/godot/web-export.md#nope"
    assert "names no topic section" in dispatch.answer(subagent_stop_payload(workspace, wrong), CONFIG)["reason"]
    read_only = MISTAKES_REPORT + "\n\nRead:\n- engines/godot/web-export.md#imports\nDocs gaps: none"
    assert "names no topic section" in dispatch.answer(subagent_stop_payload(workspace, read_only), CONFIG)["reason"]
    old = MISTAKES_REPORT + "\n\nLesson: docs/lessons/2026-11-02-a.md and maintainer-corrections.md#log"
    assert guards.sections_named(workspace, old) == []


def test_a_section_the_branch_does_not_change_does_not_count(workspace):
    tree = _page_on_branch(workspace, "studio/x.md", "# Page\n\n## Imports {#imports}\n\nold\n")  # unchanged
    assert guards.sections_named(workspace, "Mistakes: see studio/x.md#imports") == []
    (tree / "docs" / "studio" / "x.md").write_text("# Page\n\n## Imports {#imports}\n\nnew\n", encoding="utf-8")
    assert guards.sections_named(workspace, "Mistakes: see studio/x.md#imports") == ["studio/x.md#imports"]


def test_mistakes_none_and_empty_sections_pass(workspace):
    for report in (
        "Done.\n\n## Mistakes\n\nnone\n",
        "Done.\n\nMistakes: none\n",
        "Done.\n\n**Mistakes:** None.\n\n**Next:** x",
        "Done.\n\n## Mistakes\n\n## Next\nx",
        "Done. PR #5. Nothing went wrong.",
    ):
        assert guards.mistakes_text(report) == "", report
        assert dispatch.answer(subagent_stop_payload(workspace, report + READ_REPORT), CONFIG) is None
    assert "cached import" in guards.mistakes_text(MISTAKES_REPORT)
    assert guards.mistakes_text("## Mistakes\nnone\nRead: studio/hooks.md#docs\nDocs gaps: none") == ""
    assert guards.mistakes_text("Mistakes: I broke the build").startswith("I broke")
    assert guards.mistakes_text("Done.\n**Mistakes**\nthe cause was a guess\n**Next**\nx") == "the cause was a guess"


def test_helpers_and_the_reviewer_may_finish_with_mistakes(workspace):
    for kind in ("Explore", "reviewer", "web-fetch"):
        assert dispatch.answer(subagent_stop_payload(workspace, MISTAKES_REPORT, agent_type=kind), CONFIG) is None


def test_an_agent_with_unpublished_kit_docs_may_not_finish(workspace, monkeypatch):
    tree = _kit_worktree(workspace, "docs-a", 1)
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    out = dispatch.answer(subagent_stop_payload(tree, "Done. Mistakes: none"), CONFIG)
    assert out["decision"] == "block" and "docs-a" in out["reason"]


def test_the_report_falls_back_to_the_transcript(workspace, tmp_path, monkeypatch):
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    transcript = tmp_path / "agent.jsonl"
    lines = [
        {"message": {"role": "user", "content": "go"}},
        {"message": {"role": "assistant", "content": [{"type": "text", "text": MISTAKES_REPORT}]}},
    ]
    transcript.write_text("\n".join(json.dumps(line) for line in lines), encoding="utf-8")
    payload = {"hook_event_name": "SubagentStop", "cwd": str(workspace), "agent_type": "godot-engineer"}
    out = dispatch.answer({**payload, "agent_transcript_path": str(transcript)}, CONFIG)
    assert out["decision"] == "block"


def test_the_subagent_stop_hook_is_registered_for_the_kit_and_for_games():
    root = HOOKS.parents[1]
    files = {
        root / ".claude" / "settings.json": "dispatch.py",
        root / "templates/game/.claude/settings.json": "launch.py",
    }
    for path, launcher in files.items():
        hooks = json.loads(path.read_text(encoding="utf-8"))["hooks"]
        assert launcher in hooks["SubagentStop"][0]["hooks"][0]["command"]
