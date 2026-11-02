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


def test_a_godot_with_real_audio_is_refused(tmp_path):
    reason = "agents never listen"
    pinned = '"C:/ws/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"'
    assert reason in denied(shell(f"{pinned} --headless --audio-driver WASAPI --path game", tmp_path))
    assert reason in denied(shell(f"{pinned} --headless --audio-driver=WASAPI --path game", tmp_path))
    assert reason in denied(shell("uv run --project python gds godot -- --audio-driver WASAPI --path game", tmp_path))
    assert reason in denied(shell("uv run --project python gds godot --with-audio -- --path game", tmp_path))
    assert reason in denied({**shell("& $godot --audio-driver WASAPI", tmp_path), "tool_name": "PowerShell"})
    # Dummy is the point; --headless, Movie Maker and gds godot use it without the flag; other commands are not Godot.
    assert denied(shell(f"{pinned} --headless --audio-driver Dummy --path game", tmp_path)) == ""
    assert denied(shell("uv run --project python gds godot -- --audio-driver Dummy --path game", tmp_path)) == ""
    assert denied(shell(f"{pinned} --headless --path game --import", tmp_path)) == ""
    assert denied(shell(f"{pinned} --headless --path game --export-release Web build/index.html", tmp_path)) == ""
    assert denied(shell("$(uv run --project python gds tool path godot) --version", tmp_path)) == ""
    assert denied(shell("uv run --project python gds godot --path game --write-movie x.png", tmp_path)) == ""
    assert denied(shell("uv run --project python gds tool path godot --audio-driver", tmp_path)) == ""
    assert denied(shell("echo --audio-driver WASAPI", tmp_path)) == ""


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


# --------------------------------------------------------------------------------------------------------------------
# Docs ship with the change (docs/hooks.md#docs)
# --------------------------------------------------------------------------------------------------------------------

GLOSSARY = """# Mistakes by area

## general

Anything else. (1)

| Mistake | Check | Source |
| --- | --- | --- |
| A rule lived in memory | Put it in a tool and a hook | [lesson](../lessons/x.md) |

## net

The network. (2)

| Mistake | Check | Source |
| --- | --- | --- |
| Gzip decoded twice behind a proxy | Decode once &#124; in one place, use `<a>` | [lesson](../lessons/y.md) |
| A length guard dropped valid packets | Send the largest packet in a test | [lesson](../lessons/z.md) |

## audio

Sound. (1)

| Mistake | Check | Source |
| --- | --- | --- |
| A click at every stroke | Fade the loop | [lesson](../lessons/w.md) |
"""


AREAS = """
[areas]
general = "Anything else."
net = "The network."
audio = "Sound."
"""

KIT_LESSONS = {  # file name: (areas, title, fix); the newest sorts last and is listed first
    "2026-10-01-memory.md": ("general", "A rule lived in memory", "Put it in a tool and a hook"),
    "2026-10-02-length.md": ("net", "A length guard dropped valid packets", "Send the largest packet in a test"),
    "2026-10-03-gzip.md": ("net", "Gzip decoded twice behind a proxy", "Decode once | in one place, use `<a>`"),
    "2026-10-04-click.md": ("audio", "A click at every stroke", "Fade the loop"),
}


@pytest.fixture()
def kit_workspace(workspace: Path) -> Path:
    """A workspace whose kit checkout has the lessons (the glossary is built from them, not a committed page)."""
    kit = workspace / "repos" / "gdstudio"
    (kit / "python" / "src" / "gds_tools").mkdir(parents=True)
    (kit / "python" / "src" / "gds_tools" / "lessons.py").write_text(
        (HOOKS.parents[1] / "python" / "src" / "gds_tools" / "lessons.py").read_text(encoding="utf-8"), encoding="utf-8"
    )
    (kit / "docs" / "lessons").mkdir(parents=True)
    (kit / "docs" / "research").mkdir(parents=True)
    (kit / "docs" / "lessons" / "areas.toml").write_text(AREAS, encoding="utf-8")
    for name, (area, title, fix) in KIT_LESSONS.items():
        text = f"---\nareas: [{area}]\n---\n# {title}\n\n- **Saw:** x.\n- **Fix:** {fix}\n"
        (kit / "docs" / "lessons" / name).write_text(text, encoding="utf-8")
    return workspace


def started_with_areas(workspace: Path, ref: str, areas: list[str]) -> None:
    from gds_tools import issues

    repo, number = issues.parse_ref(ref)
    ledger = workspace / "cache" / "issues-started.json"
    started = issues.load_ledger(ledger)
    started[issues.ledger_key(repo, number)] = {"repo": repo, "number": number, "agent": "t", "areas": areas}
    issues.save_ledger(ledger, started)


def test_the_areas_checks_of_the_issue_reach_the_agent_at_start(kit_workspace):
    started_with_areas(kit_workspace, "Ryubara/deadnight#523", ["general", "net"])
    assert denied(agent_call(kit_workspace, "godot-engineer", "Issue: Ryubara/deadnight#523")) == ""
    text = context("SubagentStart", kit_workspace, agent_type="godot-engineer", agent_id="a1")
    assert "learning loop" in text  # the old text stays
    assert "[general]\n- A rule lived in memory: Put it in a tool and a hook" in text
    assert "[net]\n- Gzip decoded twice behind a proxy: Decode once | in one place, use `<a>`" in text
    assert "A click at every stroke" not in text  # the audio area is not this issue's
    # the note is used up: the next agent of that type gets the general area only
    again = context("SubagentStart", kit_workspace, agent_type="godot-engineer", agent_id="a2")
    assert "[general]" in again and "[net]" not in again


def test_notes_are_matched_by_agent_type_in_order(kit_workspace):
    started_with_areas(kit_workspace, "Ryubara/deadnight#1", ["general", "net"])
    started_with_areas(kit_workspace, "Ryubara/deadnight#2", ["general", "audio"])
    assert denied(agent_call(kit_workspace, "godot-engineer", "Issue: Ryubara/deadnight#1")) == ""
    assert denied(agent_call(kit_workspace, "blender-artist", "Issue: Ryubara/deadnight#2")) == ""
    blender = context("SubagentStart", kit_workspace, agent_type="blender-artist")
    godot = context("SubagentStart", kit_workspace, agent_type="godot-engineer")
    assert "[audio]" in blender and "[net]" not in blender
    assert "[net]" in godot and "[audio]" not in godot


def test_a_pull_request_agent_gets_the_general_area_only(kit_workspace, monkeypatch):
    monkeypatch.setattr(guards, "pr_state", lambda repo, number: "OPEN")
    assert denied(agent_call(kit_workspace, "godot-engineer", "PR: Ryubara/deadnight#7")) == ""
    text = context("SubagentStart", kit_workspace, agent_type="godot-engineer")
    assert "[general]" in text and "[net]" not in text


def test_no_lessons_module_means_no_area_text(kit_workspace):
    assert "[general]" in guards.area_checks(kit_workspace, ["general", "net"], CONFIG)
    (kit_workspace / "repos" / "gdstudio" / "python" / "src" / "gds_tools" / "lessons.py").unlink()
    assert guards.area_checks(kit_workspace, ["general", "net"], CONFIG) == ""


def test_the_glossary_is_built_from_the_lessons_not_read_from_a_file(kit_workspace):
    kit = kit_workspace / "repos" / "gdstudio"
    assert not (kit / "docs" / "research" / "mistakes-by-area.md").exists()
    new = kit / "docs" / "lessons" / "2026-10-09-new.md"
    new.write_text("---\nareas: [net]\n---\n# A brand new mistake\n\n- **Fix:** Check it\n", encoding="utf-8")
    assert "- A brand new mistake: Check it" in guards.area_checks(kit_workspace, ["net"], CONFIG)


def test_the_glossary_parser_of_the_hook_agrees_with_the_tools():
    from gds_tools import lessons

    for area in ("general", "net", "audio", "missing"):
        assert guards.glossary_items(GLOSSARY, area) == lessons.section(GLOSSARY, area)
    real = lessons.build(HOOKS.parents[1])
    assert guards.glossary_items(real, "net") == lessons.section(real, "net")
    assert len(lessons.section(real, "net")) > 5
    assert guards.build_glossary(HOOKS.parents[1]) == real  # the hook builds the same page


def test_the_injected_text_is_limited(kit_workspace):
    small = {**CONFIG, "docs": {**CONFIG["docs"], "inject_limit": 1, "inject_chars": 100000}}
    text = guards.area_checks(kit_workspace, ["net"], small)
    assert "Gzip" in text and "length guard" not in text
    tiny = {**CONFIG, "docs": {**CONFIG["docs"], "inject_chars": 40}}
    assert "(cut; the full list is in the glossary)" in guards.area_checks(kit_workspace, ["general", "net"], tiny)


def _kit_worktree(workspace: Path, name: str, commits: int) -> Path:
    tree = workspace / "worktrees" / "gdstudio" / name
    tree.mkdir(parents=True)

    def run(*a):
        subprocess.run(["git", "-C", str(tree), *a], check=True, capture_output=True)

    run("init", "-b", "main")
    run("-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", "base")
    run("update-ref", "refs/remotes/origin/main", "HEAD")
    run("switch", "-q", "-c", name)
    for n in range(commits):
        run("-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "-m", f"c{n}")
    return tree


def stop_payload(workspace: Path, **extra) -> dict:
    return {"hook_event_name": "Stop", "cwd": str(workspace), **extra}


def test_stop_holds_back_kit_branches_with_commits_and_no_pull_request(workspace, monkeypatch):
    _kit_worktree(workspace, "docs-a", 2)
    _kit_worktree(workspace, "docs-b", 1)
    _kit_worktree(workspace, "docs-c", 0)  # nothing ahead: nothing to publish
    monkeypatch.setattr(guards, "kit_pr_heads", lambda repo: {"docs-b"})  # b has a pull request
    out = dispatch.answer(stop_payload(workspace), CONFIG)
    assert out["decision"] == "block" and "docs-a" in out["reason"] and "docs-b" not in out["reason"]
    assert "docs-c" not in out["reason"] and "open its pull request now" in out["reason"]
    assert dispatch.answer(stop_payload(workspace, stop_hook_active=True), CONFIG) is None  # held once only


def test_stop_lets_go_when_every_branch_has_a_pull_request_or_github_is_unreachable(workspace, monkeypatch):
    _kit_worktree(workspace, "docs-a", 1)
    monkeypatch.setattr(guards, "kit_pr_heads", lambda repo: {"docs-a"})
    assert dispatch.answer(stop_payload(workspace), CONFIG) is None
    monkeypatch.setattr(guards, "kit_pr_heads", lambda repo: None)  # cannot ask: a guard that cannot look lets go
    assert dispatch.answer(stop_payload(workspace), CONFIG) is None


def subagent_stop_payload(workspace: Path, report: str, **extra) -> dict:
    return {
        "hook_event_name": "SubagentStop",
        "cwd": str(workspace),
        "agent_type": "godot-engineer",
        "last_assistant_message": report,
        **extra,
    }


MISTAKES_REPORT = (
    "PR opened.\n\n## Mistakes\n\n- I trusted the cached import and the web build hung.\n\n## Next\n\nnothing"
)


def test_an_agent_may_not_finish_with_mistakes_and_no_lesson(workspace, monkeypatch):
    monkeypatch.setattr(guards, "kit_pr_heads", lambda repo: set())
    out = dispatch.answer(subagent_stop_payload(workspace, MISTAKES_REPORT), CONFIG)
    assert out["decision"] == "block" and "Mistakes section but names no lesson file" in out["reason"]
    assert "Mistakes: none" in out["reason"]
    held = subagent_stop_payload(workspace, MISTAKES_REPORT, stop_hook_active=True)
    assert dispatch.answer(held, CONFIG) is None


def test_a_named_lesson_file_that_exists_satisfies_the_report(workspace, monkeypatch):
    monkeypatch.setattr(guards, "kit_pr_heads", lambda repo: set())
    name = "2026-11-02-a-cached-import-hung-the-web-build.md"
    report = MISTAKES_REPORT + f"\n\nLesson: docs/lessons/{name} (kit PR #120)"
    assert "names no lesson file" in dispatch.answer(subagent_stop_payload(workspace, report), CONFIG)["reason"]
    tree = _kit_worktree(workspace, "lesson-branch", 0)  # the file written on a kit branch counts
    (tree / "docs" / "lessons").mkdir(parents=True)
    (tree / "docs" / "lessons" / name).write_text("# x\n", encoding="utf-8")
    assert dispatch.answer(subagent_stop_payload(workspace, report), CONFIG) is None


def test_mistakes_none_and_empty_sections_pass(workspace):
    for report in (
        "Done.\n\n## Mistakes\n\nnone\n",
        "Done.\n\nMistakes: none\n",
        "Done.\n\n**Mistakes:** None.\n\n**Next:** x",
        "Done.\n\n## Mistakes\n\n## Next\nx",
        "Done. PR #5. Nothing went wrong.",
    ):
        assert guards.mistakes_text(report) == "", report
        assert dispatch.answer(subagent_stop_payload(workspace, report), CONFIG) is None
    assert "cached import" in guards.mistakes_text(MISTAKES_REPORT)
    assert guards.mistakes_text("Mistakes: I broke the build").startswith("I broke")
    assert guards.mistakes_text("Done.\n**Mistakes**\nthe cause was a guess\n**Next**\nx") == "the cause was a guess"


def test_helpers_and_the_reviewer_may_finish_with_mistakes(workspace):
    for kind in ("Explore", "reviewer", "web-fetch"):
        assert dispatch.answer(subagent_stop_payload(workspace, MISTAKES_REPORT, agent_type=kind), CONFIG) is None


def test_an_agent_with_unpublished_kit_docs_may_not_finish(workspace, monkeypatch):
    _kit_worktree(workspace, "docs-a", 1)
    monkeypatch.setattr(guards, "kit_pr_heads", lambda repo: set())
    out = dispatch.answer(subagent_stop_payload(workspace, "Done. Mistakes: none"), CONFIG)
    assert out["decision"] == "block" and "docs-a" in out["reason"]


def test_the_report_falls_back_to_the_transcript(workspace, tmp_path, monkeypatch):
    monkeypatch.setattr(guards, "kit_pr_heads", lambda repo: set())
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


# --------------------------------------------------------------------------------------------------------------------
# Agent stalls (docs/hooks.md#stall)
# --------------------------------------------------------------------------------------------------------------------

STALLED = "I ran the unit tests and they pass.\n\nNow the autopilot."
REPORT = "Done.\n\nPR: https://github.com/Ryubara/deadnight/pull/412 (auto-merge off)\n\nMistakes: none"


def write_transcript(path: Path, last: str) -> Path:
    """A subagent transcript the way Claude Code writes it: one JSON entry per line, the prompt first."""
    lines = [
        {"type": "user", "message": {"role": "user", "content": "Issue: Ryubara/deadnight#226"}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": "Bash"}]}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": last}]}},
    ]
    path.write_text("\n".join(json.dumps(line) for line in lines), encoding="utf-8")
    return path


def stall_answer(workspace: Path, report: str, **extra):
    return dispatch.answer(subagent_stop_payload(workspace, report, **{"agent_id": "a1", **extra}), CONFIG)


def test_a_transcript_ending_on_an_announced_step_is_refused(workspace, tmp_path, monkeypatch):
    monkeypatch.setattr(guards, "kit_pr_heads", lambda repo: set())
    payload = {"hook_event_name": "SubagentStop", "cwd": str(workspace), "agent_type": "godot-engineer"}
    transcript = write_transcript(tmp_path / "agent.jsonl", STALLED)
    out = dispatch.answer({**payload, "agent_id": "a1", "agent_transcript_path": str(transcript)}, CONFIG)
    assert out["decision"] == "block"
    assert "Now the autopilot." in out["reason"] and "Blocked:" in out["reason"] and "Refusal 1 of 2" in out["reason"]


def test_the_message_of_the_hook_input_is_judged_too(workspace):
    for kind in ("godot-engineer", "backend-engineer", "blender-artist"):
        out = stall_answer(workspace, STALLED, agent_type=kind, agent_id=kind)
        assert out["decision"] == "block", kind


def test_a_report_with_a_pull_request_passes(workspace, tmp_path):
    assert stall_answer(workspace, REPORT) is None
    transcript = write_transcript(tmp_path / "agent.jsonl", REPORT)
    payload = {"hook_event_name": "SubagentStop", "cwd": str(workspace), "agent_type": "backend-engineer"}
    assert dispatch.answer({**payload, "agent_transcript_path": str(transcript)}, CONFIG) is None
    assert stall_answer(workspace, "Opened PR #148 and left auto-merge off.") is None


def test_a_blocked_line_passes(workspace):
    for text in (
        "Blocked: the Railway token is expired; the maintainer has to log in.",
        "Tried three times.\n\n**Blocked** - no Discord application exists yet.",
        "- Blocker: the pinned Godot has no export template.",
        "I stopped because the issue asks for a licence decision.",
    ):
        assert stall_answer(workspace, text) is None, text


def test_a_blocked_word_inside_an_announced_step_is_not_a_report(workspace):
    out = stall_answer(workspace, "The unblocked path works. Now the export check.")
    assert out and out["decision"] == "block"


def test_a_reviewer_and_the_helpers_are_never_held(workspace):
    for kind in ("reviewer", "Explore", "Plan", "web-fetch", "claude", "fork"):
        assert stall_answer(workspace, STALLED, agent_type=kind, agent_id=kind) is None, kind


def test_an_agent_with_a_running_background_task_is_waiting_not_stalled(workspace):
    assert stall_answer(workspace, "Started the web build; waiting for it.", background_tasks=[{"id": "b1"}]) is None
    assert stall_answer(workspace, "Started the web build; waiting for it.", background_tasks=[])["decision"] == "block"


def test_the_hook_cannot_hold_an_agent_forever(workspace):
    answers = [stall_answer(workspace, STALLED, stop_hook_active=i > 0) for i in range(4)]
    assert [bool(a) for a in answers] == [True, True, False, False]  # max_refusals = 2, even with stop_hook_active
    assert "Refusal 2 of 2" in answers[1]["reason"]
    other = stall_answer(workspace, STALLED, agent_id="a2")  # another agent run has its own count
    assert other["decision"] == "block"


def test_the_limit_is_a_setting(workspace):
    config = {**CONFIG, "stop_check": {**CONFIG["stop_check"], "max_refusals": 1}}
    payload = subagent_stop_payload(workspace, STALLED, agent_id="a1")
    assert dispatch.answer(payload, config)["decision"] == "block"
    assert dispatch.answer(payload, config) is None


def test_nothing_to_judge_or_no_workspace_lets_the_end_through(workspace, tmp_path_factory):
    assert stall_answer(workspace, "") is None  # no message and no transcript: a guard that cannot look lets go
    elsewhere = tmp_path_factory.mktemp("elsewhere")
    payload = subagent_stop_payload(elsewhere, STALLED, agent_id="a1")
    assert dispatch.answer(payload, CONFIG) is None  # not a GDStudio workspace


def test_a_stall_and_unpublished_docs_come_back_together(workspace, monkeypatch):
    _kit_worktree(workspace, "docs-b", 1)
    monkeypatch.setattr(guards, "kit_pr_heads", lambda repo: set())
    reason = stall_answer(workspace, STALLED)["reason"]
    assert "without a report" in reason and "docs-b" in reason
    again = stall_answer(
        workspace, STALLED, stop_hook_active=True
    )  # the docs gate lets go once held; the stall gate counts
    assert "without a report" in again["reason"] and "docs-b" not in again["reason"]


def test_the_stall_gate_through_the_real_process(workspace):
    """As Claude Code starts it: a stalled end gets the block JSON with exit code 0, a report gets no output."""
    script = HOOKS / "dispatch.py"
    for report, blocked in (("Now the gap mode run and look at frames of both.", True), (REPORT, False)):
        payload = subagent_stop_payload(workspace, report, agent_id="proc", stop_hook_active=False)
        run = subprocess.run(
            [sys.executable, str(script)],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            env={"PATH": "", "CLAUDE_PROJECT_DIR": str(workspace)},
            timeout=60,
        )
        assert run.returncode == 0 and run.stderr == ""
        assert (json.loads(run.stdout)["decision"] == "block") if blocked else run.stdout == ""
