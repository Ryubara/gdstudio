"""The Claude Code hook dispatcher (.claude/hooks): each guard's refusals and passes, the protocol of its answers, and
that it lets a call through when it breaks. Git-backed checks use throwaway repositories."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

HOOKS = Path(__file__).resolve().parents[2] / ".claude" / "hooks"
sys.path.insert(0, str(HOOKS))
_spec = importlib.util.spec_from_file_location("dispatch", HOOKS / "dispatch.py")
dispatch = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(dispatch)
guards = dispatch.guards
CONFIG = dispatch.load_config(None)


def shell(command: str, cwd: Path) -> dict:
    return {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd)}


def denied(payload: dict) -> str:
    out = dispatch.answer(payload, CONFIG)
    return out["hookSpecificOutput"]["permissionDecisionReason"] if out else ""


@pytest.fixture()
def repo(tmp_path: Path) -> Path:
    path = tmp_path / "repos" / "game"
    path.mkdir(parents=True)
    run = lambda *a: subprocess.run(["git", "-C", str(path), *a], check=True, capture_output=True)  # noqa: E731
    run("init", "-b", "main")
    run("-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", "init")
    return path


def test_general_purpose_and_untyped_agents_refused(tmp_path):
    for inp in ({"subagent_type": "general-purpose"}, {}):
        reason = denied(
            {"hook_event_name": "PreToolUse", "tool_name": "Agent", "tool_input": inp, "cwd": str(tmp_path)}
        )
        assert "no instructions" in reason and "Explore" in reason
    ok = {"hook_event_name": "PreToolUse", "tool_name": "Agent", "tool_input": {"subagent_type": "Explore"}}
    assert dispatch.answer(ok, CONFIG) is None


def test_commit_and_push_on_main_refused_but_branch_allowed(repo):
    assert "takes no commits" in denied(shell("git commit -m x", repo))
    assert "takes no pushes" in denied(shell("git push", repo))
    assert "takes no pushes" in denied(shell("git push origin HEAD:main", repo))
    subprocess.run(["git", "-C", str(repo), "switch", "-q", "-c", "feature"], check=True)
    assert denied(shell("git commit -m x", repo)) == ""
    assert denied(shell("git push -u origin feature", repo)) == ""
    assert "takes no pushes" in denied(shell("git push origin feature:main", repo))


def test_force_and_no_verify_refused(repo):
    subprocess.run(["git", "-C", str(repo), "switch", "-q", "-c", "feature"], check=True)
    assert "force-pushing" in denied(shell("git push --force origin feature", repo))
    assert "force-pushing" in denied(shell("git push origin +feature", repo))
    assert "--no-verify" in denied(shell("git commit --no-verify -m x", repo))


def test_cd_and_git_dash_c_follow_the_folder(repo, tmp_path):
    assert "takes no commits" in denied(shell(f"cd {repo} && git commit -m x", tmp_path))
    assert "takes no commits" in denied(shell(f"git -C {repo} commit -m x", tmp_path))


def test_pinned_tools_only(tmp_path):
    assert "pinned" in denied(shell("godot --headless --path game", tmp_path))
    assert "Steam" in denied(shell('"F:/SteamLibrary/steamapps/common/Godot Engine/godot.exe" -e', tmp_path))
    assert denied(shell('"C:/ws/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe" --headless', tmp_path)) == ""
    assert denied(shell("uv run --project python gds tool path godot", tmp_path)) == ""
    assert denied(shell('"$B/blender.exe" -b --version', tmp_path)) == ""


def test_a_windowed_godot_goes_through_gds(tmp_path):
    reason = "takes the keyboard focus"
    pinned = '"C:/ws/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"'
    assert reason in denied(shell(f"{pinned} --path game --write-movie x.png", tmp_path))
    assert reason in denied(shell('"$GODOT" --path game -- --bench', tmp_path))
    assert reason in denied(shell("$(uv run --project python gds tool path godot) --path game --import", tmp_path))
    assert reason in denied({**shell("& $godot --path game", tmp_path), "tool_name": "PowerShell"})
    assert denied(shell(f"{pinned} --headless --path game --import", tmp_path)) == ""
    assert denied(shell('"$GODOT" --headless --path game -s res://t.gd', tmp_path)) == ""
    assert denied(shell("$(uv run --project python gds tool path godot) --version", tmp_path)) == ""
    assert denied(shell("uv run --project python gds godot --path game --write-movie x.png", tmp_path)) == ""
    assert denied(shell("uv run --project python gds capture frames --project game --name a", tmp_path)) == ""
    assert denied(shell("uv run --project python gds tool path godot", tmp_path)) == ""


def test_a_browser_probe_goes_through_gds_quiet(tmp_path):
    reason = "clips the real cursor"
    probe = "uv run --with playwright==1.64.1 python tools/web_smoke/hip_fire.py build/web build/hip-fire --gpu"
    assert reason in denied(shell(probe, tmp_path))
    assert reason in denied(shell("cd ../deadnight && python tools\\web_smoke\\pointer_lock.py build/web", tmp_path))
    assert reason in denied(shell("uv run --with playwright python scratch/lock.py", tmp_path))
    assert reason in denied(shell("npx playwright test", tmp_path))
    assert reason in denied(
        {**shell("& python tools/web_smoke/touch_look.py b o", tmp_path), "tool_name": "PowerShell"}
    )
    kit = "uv run --project ../gdstudio/python gds quiet"
    assert denied(shell(f"{kit} -- {probe}", tmp_path)) == ""
    assert denied(shell(f"{kit} --timeout 600 -- npx playwright test", tmp_path)) == ""
    assert denied(shell("uv run --with playwright python -m playwright install chromium", tmp_path)) == ""
    assert denied(shell("npx playwright install", tmp_path)) == ""
    assert denied(shell("uv pip install playwright", tmp_path)) == ""
    assert denied(shell("git add tools/web_smoke/hip_fire.py && cat tools/web_smoke/smoke.py", tmp_path)) == ""
    assert denied(shell("uv run --project python pytest", tmp_path)) == ""
    assert denied(shell("ruff check tools/web_smoke/hip_fire.py", tmp_path)) == ""


def test_shared_tools_never_killed_by_name(tmp_path):
    reason = "killing by name"
    assert reason in denied(shell("taskkill /F /IM Godot_v4.7.2-stable_win64_console.exe", tmp_path))
    assert reason in denied(shell("pkill -f godot", tmp_path))
    assert reason in denied(shell("killall blender", tmp_path))
    ps = {**shell("Stop-Process -Name Godot_v4.7.2-stable_win64_console -Force", tmp_path), "tool_name": "PowerShell"}
    assert reason in denied(ps)
    assert denied(shell("taskkill /F /PID 4242", tmp_path)) == ""
    assert denied(shell("kill 4242", tmp_path)) == ""
    assert denied({**shell("Stop-Process -Id 4242", tmp_path), "tool_name": "PowerShell"}) == ""
    assert denied(shell("taskkill /IM notepad.exe", tmp_path)) == ""


def test_secrets_never_printed(tmp_path):
    assert "secret" in denied(shell("echo $POLY_PIZZA_API_KEY", tmp_path))
    assert "environment" in denied(shell("env", tmp_path))
    assert "env:" in denied({**shell("Get-ChildItem env:", tmp_path), "tool_name": "PowerShell"})
    assert (
        denied(shell('curl -H "x-auth-token: $POLY_PIZZA_API_KEY" https://api.poly.pizza/v1.1/model/x', tmp_path)) == ""
    )


def test_protected_and_generated_files(tmp_path):
    def edit(p):
        return {
            "hook_event_name": "PreToolUse",
            "tool_name": "Edit",
            "tool_input": {"file_path": str(p)},
            "cwd": str(tmp_path),
        }

    assert "protected" in denied(edit(tmp_path / ".env"))
    assert "protected" in denied(edit(tmp_path / "game" / ".godot" / "x.cfg"))
    assert "conventions.yml" in denied(edit(tmp_path / ".github" / "pull_request_template.md"))
    assert denied(edit(tmp_path / "game" / "main.gd")) == ""


def test_glob_regex():
    assert guards.matches("game/ui/menu.tscn", ["game/**/*.tscn"])
    assert guards.matches("a/b/.env", ["**/.env"]) and guards.matches(".env", ["**/.env"])
    assert not guards.matches("game/main.gd", ["game/**/*.tscn"])


def test_stop_gate_needs_a_newer_capture(repo, tmp_path):
    (tmp_path / ".gdstudio-workspace").write_text("")
    (repo / "game" / "ui").mkdir(parents=True)
    (repo / "game" / "project.godot").write_text("")
    subprocess.run(["git", "-C", str(repo), "switch", "-q", "-c", "menu"], check=True)
    (repo / "game" / "ui" / "menu.tscn").write_text("x")
    stop = {"hook_event_name": "Stop", "cwd": str(repo)}
    out = dispatch.answer(stop, CONFIG)
    assert out and out["decision"] == "block" and "menu.tscn" in out["reason"]
    assert dispatch.answer({**stop, "stop_hook_active": True}, CONFIG) is None
    shots = tmp_path / "scratch" / "game" / "menu"
    shots.mkdir(parents=True)
    (shots / "menu.png").write_bytes(b"png")
    assert dispatch.answer(stop, CONFIG) is None


def test_session_start_names_the_branch_folder(repo, tmp_path):
    (tmp_path / ".gdstudio-workspace").write_text("")
    out = dispatch.answer({"hook_event_name": "SessionStart", "cwd": str(repo)}, CONFIG)
    assert "branch main" in out["hookSpecificOutput"]["additionalContext"]


def test_broken_input_lets_the_call_through(monkeypatch, capsys):
    monkeypatch.setattr(sys, "stdin", type("S", (), {"buffer": type("B", (), {"read": lambda self: b"{not json"})()})())
    assert dispatch.main() == 0
    assert "call allowed" in capsys.readouterr().err


def test_answer_is_json_protocol(tmp_path):
    out = dispatch.answer(shell("env", tmp_path), CONFIG)
    assert json.loads(json.dumps(out))["hookSpecificOutput"]["permissionDecision"] == "deny"


def test_heredoc_and_herestring_bodies_are_data(tmp_path):
    body = "python - <<'EOF'\nblender = find()\ngodot --headless\nEOF\necho done"
    assert denied(shell(body, tmp_path)) == ""
    assert "pinned" in denied(shell("cat <<EOF\ntext\nEOF\ngodot -e", tmp_path))
    ps = {**shell("$m = @'\nblender = 1\n'@\n$m | git commit -F -", tmp_path), "tool_name": "PowerShell"}
    assert "pinned" not in denied(ps)


def test_quoted_pipes_do_not_split_commands(tmp_path):
    assert denied(shell('git log | grep -E "gdunit|godot |done"', tmp_path)) == ""
    assert "pinned" in denied(shell('echo "a|b" && godot -e', tmp_path))


# --- The learning loop (docs/hooks.md#learning) ----------------------------------------------------------------------


@pytest.fixture()
def workspace(tmp_path: Path) -> Path:
    (tmp_path / ".gdstudio-workspace").write_text("")
    return tmp_path


def queue_of(workspace: Path) -> Path:
    folder = workspace / "scratch" / "kit-lessons-queue"
    folder.mkdir(parents=True, exist_ok=True)
    return folder


def context(event: str, cwd: Path, **extra) -> str:
    out = dispatch.answer({"hook_event_name": event, "cwd": str(cwd), **extra}, CONFIG)
    if not out:
        return ""
    assert out["hookSpecificOutput"]["hookEventName"] == event
    return out["hookSpecificOutput"]["additionalContext"]


def test_every_prompt_gets_the_short_reminder(workspace):
    text = context("UserPromptSubmit", workspace, prompt="that is wrong")
    assert "corrects an agent" in text and "maintainer-corrections.md" in text
    assert (workspace / "scratch" / "kit-lessons-queue").as_posix() in text  # the queue, from the workspace
    assert len(text.splitlines()) <= 3 and len(text) < 900  # it is paid for on every prompt
    assert context("UserPromptSubmit", Path(__file__).anchor, prompt="x") == ""  # outside any workspace: silent


def test_reminder_text_comes_from_the_config(workspace):
    config = {"lessons": {"prompt": "custom {queue} {corrections}"}}
    out = dispatch.answer({"hook_event_name": "UserPromptSubmit", "cwd": str(workspace)}, config)
    assert out["hookSpecificOutput"]["additionalContext"].startswith("custom ")
    assert dispatch.answer({"hook_event_name": "UserPromptSubmit", "cwd": str(workspace)}, {}) is None


def test_session_start_points_at_the_corrections_and_lessons(repo, workspace):
    text = context("SessionStart", repo)
    assert "docs/research/maintainer-corrections.md" in text and "docs/lessons/index.md" in text


def test_starting_agents_are_told_to_read_and_to_report_the_row(workspace):
    text = context("SubagentStart", workspace, agent_type="godot-engineer", agent_id="a1")
    assert "maintainer-corrections.md" in text and "final report" in text and "do not edit that table" in text
    for helper in ("Explore", "Plan", "claude-code-guide"):
        assert context("SubagentStart", workspace, agent_type=helper) == ""


def test_stop_holds_a_session_with_an_unpublished_row_once(workspace):
    queue = queue_of(workspace)
    stop = {"hook_event_name": "Stop", "cwd": str(workspace)}
    assert dispatch.answer(stop, CONFIG) is None  # an empty queue
    (queue / "kill-lag-spike.md").write_text("# A lag spike\n\nCause found: the particle pool.\n")
    (queue / "mouse-look.md").write_text("# Mouse look\n\nWaiting on: #334 (a leak check)\n")
    (queue / "published").mkdir()
    (queue / "published" / "done.md").write_text("# Already published\n")
    out = dispatch.answer(stop, CONFIG)
    assert out["decision"] == "block"
    assert "kill-lag-spike.md" in out["reason"] and "mouse-look.md" not in out["reason"]
    assert "done.md" not in out["reason"] and queue.as_posix() in out["reason"]
    assert dispatch.answer({**stop, "stop_hook_active": True}, CONFIG) is None  # held once, never a loop


def test_stop_lets_waiting_rows_and_other_folders_be(workspace, tmp_path_factory):
    queue = queue_of(workspace)
    (queue / "a.md").write_text("# A\nwaiting on: #12\n")
    (queue / "README.md").write_text("# How the queue works\n")
    stop = {"hook_event_name": "Stop", "cwd": str(workspace)}
    assert dispatch.answer(stop, CONFIG) is None
    assert dispatch.answer({**stop, "cwd": str(tmp_path_factory.mktemp("elsewhere"))}, CONFIG) is None


def test_stop_reports_proof_and_queue_together(repo, workspace):
    (repo / "game" / "ui").mkdir(parents=True)
    (repo / "game" / "project.godot").write_text("")
    subprocess.run(["git", "-C", str(repo), "switch", "-q", "-c", "menu"], check=True)
    (repo / "game" / "ui" / "menu.tscn").write_text("x")
    (queue_of(workspace) / "row.md").write_text("# A row\n")
    reason = dispatch.answer({"hook_event_name": "Stop", "cwd": str(repo)}, CONFIG)["reason"]
    assert "menu.tscn" in reason and "row.md" in reason


def test_dispatch_end_to_end_through_stdin(workspace):
    """The real process, as Claude Code starts it: JSON in, the protocol's JSON out, exit code 0."""
    queue_of(workspace)
    (queue_of(workspace) / "row.md").write_text("# A row\n")
    script = HOOKS / "dispatch.py"
    for payload, key in (
        ({"hook_event_name": "UserPromptSubmit", "prompt": "no, that is wrong"}, "additionalContext"),
        ({"hook_event_name": "SubagentStart", "agent_type": "godot-engineer"}, "additionalContext"),
        ({"hook_event_name": "Stop", "stop_hook_active": False}, "reason"),
    ):
        run = subprocess.run(
            [sys.executable, str(script)],
            input=json.dumps({**payload, "cwd": str(workspace)}),
            capture_output=True,
            text=True,
            env={"PATH": "", "CLAUDE_PROJECT_DIR": str(workspace)},
            timeout=60,
        )
        assert run.returncode == 0 and run.stderr == ""
        assert key in run.stdout


# --- local mains follow origin (docs/hooks.md#mains) ---------------------------------------------------------------


def _git(path: Path, *args: str) -> str:
    out = subprocess.run(
        ["git", "-C", str(path), "-c", "user.email=t@t", "-c", "user.name=t", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return out.stdout.strip()


@pytest.fixture()
def mains(workspace: Path, tmp_path_factory) -> tuple[Path, Path]:
    """An origin with one commit, and `<workspace>/repos/game` cloned from it on main."""
    origin = tmp_path_factory.mktemp("origin") / "game"
    origin.mkdir()
    _git(origin, "init", "-q", "-b", "main")
    (origin / "a.txt").write_text("1\n")
    _git(origin, "add", "-A")
    _git(origin, "commit", "-q", "-m", "one")
    (workspace / "repos").mkdir()
    subprocess.run(["git", "clone", "-q", str(origin), str(workspace / "repos" / "game")], check=True)
    return origin, workspace / "repos" / "game"


def _advance(origin: Path, text: str) -> str:
    (origin / "a.txt").write_text(text)
    _git(origin, "commit", "-q", "-am", text.strip())
    return _git(origin, "rev-parse", "HEAD")


def test_merge_commands_are_recognised():
    yes = ["gh pr merge 5 --squash", "gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=squash"]
    no = ["gh pr view 5", "gh api repos/o/r/pulls/12", "git merge main"]
    assert all(any(guards.is_merge(w) for w in guards.segments(c)) for c in yes)
    assert not any(any(guards.is_merge(w) for w in guards.segments(c)) for c in no)


def test_a_merge_command_pulls_the_local_main(mains, workspace):
    origin, local = mains
    head = _advance(origin, "2\n")
    payload = {"tool_name": "Bash", "tool_input": {"command": "gh pr merge 7 --squash"}, "cwd": str(workspace)}
    text = context("PostToolUse", workspace, **{k: v for k, v in payload.items() if k != "cwd"})
    assert _git(local, "rev-parse", "HEAD") == head
    assert "game: main pulled" in text
    other = {"tool_name": "Bash", "tool_input": {"command": "gh pr view 7"}}
    _advance(origin, "3\n")
    assert context("PostToolUse", workspace, **other) == ""
    assert _git(local, "rev-parse", "HEAD") == head


def test_local_changes_in_the_way_are_named_not_discarded(mains, workspace):
    origin, local = mains
    _advance(origin, "2\n")
    (local / "a.txt").write_text("mine\n")
    notes = guards.pull_mains(workspace, CONFIG, force=True)
    assert (local / "a.txt").read_text() == "mine\n"
    assert notes and "not pulled" in notes[0] and "ask before discarding" in notes[0]


def test_a_branch_checkout_is_left_alone_and_stop_is_throttled(mains, workspace):
    origin, local = mains
    _git(local, "switch", "-q", "-c", "feature")
    before = _git(local, "rev-parse", "HEAD")
    _advance(origin, "2\n")
    assert guards.pull_mains(workspace, CONFIG, force=True) == []
    assert _git(local, "rev-parse", "HEAD") == before
    _git(local, "switch", "-q", "main")
    assert guards.pull_mains(workspace, CONFIG) == []  # stamped by the forced pull a moment ago
    assert _git(local, "rev-parse", "HEAD") == before
    assert guards.pull_mains(workspace, CONFIG, force=True)


def test_session_start_pulls_the_local_main(mains, workspace):
    origin, local = mains
    head = _advance(origin, "2\n")
    assert "game: main pulled" in context("SessionStart", workspace)
    assert _git(local, "rev-parse", "HEAD") == head


# --------------------------------------------------------------------------------------------------------------------
# Issue order (docs/hooks.md#issues)
# --------------------------------------------------------------------------------------------------------------------


def agent_call(workspace: Path, kind: str | None, prompt: str = "") -> dict:
    inp = {"prompt": prompt, **({"subagent_type": kind} if kind else {})}
    return {"hook_event_name": "PreToolUse", "tool_name": "Agent", "tool_input": inp, "cwd": str(workspace)}


def start_in_ledger(workspace: Path, *refs: str) -> None:
    """Write the ledger the way `gds issue start` does (through its own code, so the two keys cannot drift apart)."""
    from gds_tools import issues

    ledger = workspace / "cache" / "issues-started.json"
    started = issues.load_ledger(ledger)
    for ref in refs:
        repo, number = issues.parse_ref(ref)
        started[issues.ledger_key(repo, number)] = {"repo": repo, "number": number, "agent": "t"}
    issues.save_ledger(ledger, started)


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
        assert denied(agent_call(workspace, "godot-engineer", prompt)) == ""
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
    monkeypatch.setattr(guards, "pr_state", lambda repo, number: states[number])
    assert denied(agent_call(workspace, "godot-engineer", "Resolve the conflicts.\nPR: Ryubara/deadnight#7")) == ""
    assert denied(agent_call(workspace, "reviewer", "PR: Ryubara/deadnight#7")) == ""
    assert "not an open pull request" in denied(agent_call(workspace, "godot-engineer", "PR: Ryubara/deadnight#8"))
    assert "not an open pull request" in denied(agent_call(workspace, "godot-engineer", "PR: Ryubara/deadnight#9"))
    # gh cannot tell (offline): the guard lets the call through rather than lock the session out
    assert denied(agent_call(workspace, "godot-engineer", "PR: Ryubara/deadnight#10")) == ""


def test_a_pull_request_line_does_not_stand_in_for_an_unstarted_issue(workspace, monkeypatch):
    monkeypatch.setattr(guards, "pr_state", lambda repo, number: "OPEN")
    prompt = "PR: Ryubara/deadnight#7\nIssue: Ryubara/deadnight#523"
    assert "Ryubara/deadnight#523 was not started" in denied(agent_call(workspace, "godot-engineer", prompt))


def test_no_enforcement_outside_a_workspace_or_when_switched_off(tmp_path, workspace):
    assert denied(agent_call(tmp_path.parent, "godot-engineer", "no issue")) == ""
    off = {**CONFIG, "issues": {**CONFIG["issues"], "enforce": False}}
    assert dispatch.answer(agent_call(workspace, "godot-engineer", "no issue"), off) is None


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
