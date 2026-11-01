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
