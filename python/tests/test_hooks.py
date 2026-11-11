"""The Claude Code hook dispatcher (.claude/hooks): each guard's refusals and passes, the protocol of its answers, and
that it lets a call through when it breaks. Git-backed checks use throwaway repositories."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest
from hook_support import CONFIG, HOOKS, dispatch, guards, patch

REAL_IDLE_ISSUES = guards.idle_issues


@pytest.fixture(autouse=True)
def no_github_at_stop(monkeypatch):
    """The coordinator's Stop check asks GitHub; no test reaches it unless it says so (the `idle` fixture)."""
    patch(monkeypatch, "idle_issues", lambda workspace, config, gh=None: [])


REAL_START_SWEEP = guards.start_sweep


@pytest.fixture(autouse=True)
def no_sweep(monkeypatch):
    """No test starts the real `gds worktree sweep` (it would remove worktrees of this machine); the `sweeps` fixture
    records the starts instead."""
    patch(monkeypatch, "start_sweep", lambda workspace, config, force=False: False)


REAL_START_DISK_GUARD = guards.start_disk_guard
FREE = {"gb": 500.0}  # the disk every test sees, unless it sets another


@pytest.fixture(autouse=True)
def roomy_disk(monkeypatch):
    """No test starts the real `gds disk guard`, and every test sees a disk with room, whatever this machine has."""
    FREE["gb"] = 500.0
    patch(monkeypatch, "start_disk_guard", lambda workspace, config, force=False: False)
    patch(monkeypatch, "free_bytes", lambda path: int(FREE["gb"] * guards.GB))


@pytest.fixture(autouse=True)
def heads_hold_main(monkeypatch):
    """No test asks GitHub whether a pull request is behind its base: every head holds the tip (python/tests/
    test_merge_guard.py has the merge guard's own tests)."""
    guards.take_warnings()
    patch(monkeypatch, "behind", lambda target, repo, cwd: ({"behind_by": 0}, ""))


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


def test_a_variable_assignment_is_not_the_program(tmp_path):
    reason = "takes the keyboard focus"
    find = "$(uv run --project python gds tool path godot)"
    assert denied(shell(f'GODOT="{find}" && "$GODOT" --headless --path game', tmp_path)) == ""
    assert denied(shell(f'GODOT={find} && "$GODOT" --headless --path game', tmp_path)) == ""
    assert reason in denied(shell(f'GODOT="{find}" && "$GODOT" --path game', tmp_path))
    assert reason in denied(shell(f'GODOT="{find}" "$GODOT" --path game', tmp_path))
    assert denied(shell(f'GODOT="{find}"', tmp_path)) == ""


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


# --- The learning loop (docs/studio/hooks.md#learning) ----------------------------------------------------------------


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
    assert "docs/studio/rules.md" in text and "gds learn" in text and "never a lesson page" in text
    assert (workspace / "scratch" / "kit-lessons-queue").as_posix() in text  # the queue, from the workspace
    assert len(text.splitlines()) <= 3 and len(text) < 900  # it is paid for on every prompt
    assert context("UserPromptSubmit", Path(__file__).anchor, prompt="x") == ""  # outside any workspace: silent


def test_reminder_text_comes_from_the_config(workspace):
    config = {"lessons": {"prompt": "custom {queue} {corrections}"}}
    out = dispatch.answer({"hook_event_name": "UserPromptSubmit", "cwd": str(workspace)}, config)
    assert out["hookSpecificOutput"]["additionalContext"].startswith("custom ")
    assert dispatch.answer({"hook_event_name": "UserPromptSubmit", "cwd": str(workspace)}, {}) is None


def test_session_start_points_at_gds_learn_and_the_rules(repo, workspace):
    text = context("SessionStart", repo)
    assert "docs/studio/maintainer-corrections.md" in text and "docs/studio/rules.md" in text
    assert "gds learn" in text and "docs/lessons/index.md" not in text


def test_starting_agents_are_told_to_read_and_to_report_the_log_line(workspace):
    text = context("SubagentStart", workspace, agent_type="godot-engineer", agent_id="a1")
    assert "maintainer-corrections.md" in text and "final report" in text and "do not edit that page" in text
    assert "page.md#anchor" in text and "docs/studio/rules.md" in text
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


# --- local mains follow origin (docs/studio/hooks.md#mains) -----------------------------------------------------------


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


# --- finished worktrees are swept in the background (docs/studio/hooks.md#sweep) --------------------------------------


@pytest.fixture()
def sweeps(monkeypatch, workspace):
    """The real `start_sweep` with the process start recorded: (command, keyword arguments) per start."""
    started: list[tuple[list[str], dict]] = []

    class FakePopen:
        def __init__(self, command, **kwargs):
            started.append((command, kwargs))

    patch(monkeypatch, "start_sweep", REAL_START_SWEEP)
    monkeypatch.setattr(guards.subprocess, "Popen", FakePopen)
    monkeypatch.setattr(guards.shutil, "which", lambda name: "/bin/uv")
    return started


def test_the_sweep_starts_in_the_background_and_logs_to_scratch(sweeps, workspace):
    assert guards.start_sweep(workspace, CONFIG) is True
    command, kwargs = sweeps[0]
    assert command[:3] == ["/bin/uv", "run", "--project"] and command[-3:] == ["gds", "worktree", "sweep"]
    assert kwargs["stdin"] is subprocess.DEVNULL and kwargs["cwd"] == str(workspace)
    assert (workspace / "scratch" / "worktree-sweep.log").exists()  # opened for the child's output
    assert guards.start_sweep(workspace, CONFIG) is False  # stamped a moment ago: throttled
    assert guards.start_sweep(workspace, CONFIG, force=True) is True
    assert len(sweeps) == 2


def test_the_sweep_can_be_turned_off(sweeps, workspace):
    config = {**CONFIG, "sweep": {**CONFIG["sweep"], "enabled": False}}
    assert guards.start_sweep(workspace, config, force=True) is False and sweeps == []


def test_a_long_log_is_moved_aside(sweeps, workspace):
    log = workspace / "scratch" / "worktree-sweep.log"
    log.parent.mkdir()
    log.write_text("x" * 2_000_000)
    guards.start_sweep(workspace, CONFIG, force=True)
    assert log.with_suffix(".old.log").stat().st_size == 2_000_000 and log.stat().st_size == 0


def test_session_start_merge_and_stop_start_the_sweep(monkeypatch, workspace):
    calls = []
    patch(monkeypatch, "start_sweep", lambda ws, config, force=False: calls.append(force))
    context("SessionStart", workspace)
    context("PostToolUse", workspace, tool_name="Bash", tool_input={"command": "gh pr merge 7 --squash"})
    context("PostToolUse", workspace, tool_name="Bash", tool_input={"command": "gh pr view 7"})
    guards.stop({"cwd": str(workspace)}, CONFIG)
    assert calls == [False, True, False]  # session start, the merge (forced), Stop; viewing a pull request starts none


# --------------------------------------------------------------------------------------------------------------------
# Issue order (docs/studio/hooks.md#issues)
# --------------------------------------------------------------------------------------------------------------------


READ = "\nRead: studio/hooks.md#docs, studio/starting-work.md#starting-an-agent"


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


# --------------------------------------------------------------------------------------------------------------------
# Docs ship with the change (docs/studio/hooks.md#docs)
# --------------------------------------------------------------------------------------------------------------------


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
READ_REPORT = "\n\nRead: studio/hooks.md#docs, studio/starting-work.md#starting-an-agent\nDocs gaps: none"


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


# --- gh pr create|edit --attach: the images must sit inside Screenshots ---------------------------------------------

GOOD_BODY = """## Summary

- ran

## Screenshots

- **Before:** ![before](./before.png)
- **After:** ![after](./after.png)

## AI use

- **Commits written by:** an AI
"""


def body_file(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "body.md"
    path.write_text(text, encoding="utf-8")
    return path


ATTACH = "--attach {d}/before.png --attach {d}/after.png"


def test_attach_with_references_inside_screenshots_is_allowed(tmp_path):
    body_file(tmp_path, GOOD_BODY)
    flags = ATTACH.format(d=tmp_path)
    assert denied(shell(f"gh pr create --title x --body-file body.md {flags}", tmp_path)) == ""
    assert denied(shell(f"gh pr edit 7 -F {tmp_path}/body.md {flags}", tmp_path)) == ""
    assert (
        denied(shell(f"gh pr edit 7 --body-file={tmp_path}/body.md --attach '{tmp_path}/before.png#Before'", tmp_path))
        == ""
    )


def test_a_new_thing_may_say_before_none_and_attach_only_the_after(tmp_path):
    body_file(tmp_path, GOOD_BODY.replace("![before](./before.png)", "none (new screen)"))
    assert denied(shell(f"gh pr create --body-file body.md --attach {tmp_path}/after.png", tmp_path)) == ""


def test_attach_without_a_reference_names_the_missing_files_and_the_line_to_write(tmp_path):
    body_file(tmp_path, GOOD_BODY.replace("![after](./after.png)", "after.png"))
    reason = denied(shell(f"gh pr create --body-file body.md {ATTACH.format(d=tmp_path)}", tmp_path))
    assert "after.png" in reason and "before.png" not in reason.split("no reference for")[1].split(".")[0]
    assert "`![after](./after.png)`" in reason and "After: line" in reason and "after `## AI use`" in reason
    assert "Read the body back" in reason


def test_a_reference_outside_screenshots_does_not_count(tmp_path):
    outside = GOOD_BODY.replace("![after](./after.png)", "nothing") + "\n![after](./after.png)\n"
    body_file(tmp_path, outside)
    reason = denied(shell(f"gh pr create --body-file body.md {ATTACH.format(d=tmp_path)}", tmp_path))
    assert "no reference for after.png" in reason


def test_a_reference_in_the_template_comment_does_not_count(tmp_path):
    body_file(tmp_path, "## Screenshots\n\n<!-- write ![after](./after.png) here -->\n\n- **After:** ...\n")
    assert "no reference for after.png" in denied(
        shell(f"gh pr edit 3 --body-file body.md --attach {tmp_path}/after.png", tmp_path)
    )


def test_the_before_image_must_sit_between_before_and_after(tmp_path):
    swapped = GOOD_BODY.replace(
        "- **Before:** ![before](./before.png)\n- **After:** ![after](./after.png)",
        "- **Before:**\n- **After:** ![before](./before.png) ![after](./after.png)",
    )
    body_file(tmp_path, swapped)
    reason = denied(shell(f"gh pr create --body-file body.md {ATTACH.format(d=tmp_path)}", tmp_path))
    assert "Before: line" in reason and "between it and the After: line" in reason


def test_an_after_line_without_an_image_below_it_is_refused(tmp_path):
    body_file(tmp_path, GOOD_BODY.replace("![after](./after.png)", ""))
    reason = denied(shell(f"gh pr create --body-file body.md --attach {tmp_path}/before.png", tmp_path))
    assert "no image comes after the After: line" in reason


def test_attach_without_a_readable_body_file_is_refused(tmp_path):
    for command in (
        f"gh pr create --title x --attach {tmp_path}/after.png",
        f"gh pr edit 4 --attach {tmp_path}/after.png",
        f"gh pr create --body-file missing.md --attach {tmp_path}/after.png",
        f"gh pr create --body-file - --attach {tmp_path}/after.png",
        f'gh pr create --body "$(cat body.md)" --attach {tmp_path}/after.png',
    ):
        reason = denied(shell(command, tmp_path))
        assert "after `## AI use`" in reason and "--body-file" in reason, command


def test_a_literal_body_is_read_too(tmp_path):
    ok = "gh pr create --body '## Screenshots\n\n- **After:** ![a](./after.png)\n' --attach after.png"
    assert denied(shell(ok, tmp_path)) == ""
    bad = "gh pr create --body '## Screenshots\n\nsee after.png\n' --attach after.png"
    assert "no reference for after.png" in denied(shell(bad, tmp_path))


def test_other_gh_commands_and_no_attach_are_not_checked(tmp_path):
    assert denied(shell("gh pr create --title x --body-file missing.md", tmp_path)) == ""
    assert denied(shell("gh pr edit 3 --title y", tmp_path)) == ""
    assert denied(shell(f"gh issue create --title x --body y --attach {tmp_path}/a.png", tmp_path)) == ""
    assert denied(shell("gh pr view 3 --json body", tmp_path)) == ""


def test_the_attach_check_follows_cd_and_can_be_turned_off(tmp_path):
    sub = tmp_path / "sub"
    sub.mkdir()
    (sub / "body.md").write_text(GOOD_BODY, encoding="utf-8")
    flags = ATTACH.format(d=sub)  # the images are in the folder the `cd` moves to: `gh` finds `./before.png` there
    assert denied(shell(f"cd sub && gh pr create --body-file body.md {flags}", tmp_path)) == ""
    assert "does not exist yet" in denied(shell(f"gh pr create --body-file body.md {flags}", tmp_path))
    off = {**CONFIG, "attach": {"enforce": False}}
    assert dispatch.answer(shell(f"gh pr create --attach {tmp_path}/after.png", tmp_path), off) is None


# --- a pull request that reached GitHub with local image references (kit #242) --------------------------------------

PR_URL = "https://github.com/Ryubara/deadnight/pull/637"


def after(command: str, output: str, tool: str = "Bash") -> dict:
    return {
        "hook_event_name": "PostToolUse",
        "tool_name": tool,
        "tool_input": {"command": command},
        "tool_response": {"stdout": output, "stderr": ""},
        "cwd": ".",
    }


def test_local_image_references_are_told_from_uploads():
    body = "![a](./a.png) ![b](https://github.com/user-attachments/assets/1) <!-- ![c](./c.png) --> ![d](../x/d.JPG)"
    assert guards.local_images(body) == ["![a](./a.png)", "![d](../x/d.JPG)"]
    assert guards.local_images("see [the docs](./docs/x.md) and ![u](https://example.com/u.png)") == []


def test_a_pull_request_opened_with_local_images_is_named_at_once(monkeypatch):
    """The path the guard before the command cannot see: the body that reached GitHub is read back."""
    patch(monkeypatch, "local_images_in", lambda url: ["![before](./before.png)"])
    commands = [
        "gh pr create --repo Ryubara/deadnight --body-file b.md --attach a.png 2>&1 | tail -5",
        "gh pr edit 637 --body-file b.md",
        "python open_pr.py",  # a script that runs gh itself: only its output says a pull request was made
    ]
    for command in commands:
        out = dispatch.answer(after(command, f"\n{PR_URL}\n"), CONFIG)
        text = out["hookSpecificOutput"]["additionalContext"]
        assert PR_URL in text and "![before](./before.png)" in text and "pr edit N --body-file" in text, command
    powershell = dispatch.answer(after("gh pr create --attach a.png", PR_URL, tool="PowerShell"), CONFIG)
    assert "local image references" in powershell["hookSpecificOutput"]["additionalContext"]


def test_a_clean_description_or_an_unrelated_command_says_nothing(monkeypatch):
    asked = []
    patch(monkeypatch, "local_images_in", lambda url: asked.append(url) or [])
    assert dispatch.answer(after("gh pr create --attach a.png", PR_URL), CONFIG) is None
    assert asked == [PR_URL]
    patch(monkeypatch, "local_images_in", lambda url: ["![x](./x.png)"])
    assert dispatch.answer(after("gh pr view 637", PR_URL), CONFIG) is None  # a read prints the address too
    assert dispatch.answer(after("gh pr create --attach a.png", "no address printed"), CONFIG) is None
    off = {**CONFIG, "attach": {"readback": False}}
    assert dispatch.answer(after("gh pr create --attach a.png", PR_URL), off) is None


# --------------------------------------------------------------------------------------------------------------------
# Agent stalls (docs/studio/hooks.md#stall)
# --------------------------------------------------------------------------------------------------------------------

STALLED = "I ran the unit tests and they pass.\n\nNow the autopilot."
REPORT = (
    "Done.\n\nPR: https://github.com/Ryubara/deadnight/pull/412 (auto-merge off)\n\nMistakes: none\n\n"
    "Read: studio/hooks.md#stall\nDocs gaps: none"
)


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
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    payload = {"hook_event_name": "SubagentStop", "cwd": str(workspace), "agent_type": "godot-engineer"}
    transcript = write_transcript(tmp_path / "agent.jsonl", STALLED)
    out = dispatch.answer({**payload, "agent_id": "a1", "agent_transcript_path": str(transcript)}, CONFIG)
    assert out["decision"] == "block"
    assert "Now the autopilot." in out["reason"] and "Blocked:" in out["reason"] and "Refusal 1 of 2" in out["reason"]


def test_the_message_of_the_hook_input_is_judged_too(workspace):
    for kind in ("godot-engineer", "backend-engineer", "blender-artist"):
        out = stall_answer(workspace, STALLED, agent_type=kind, agent_id=kind)
        assert out["decision"] == "block", kind


def test_a_level_designer_ending_without_a_report_is_refused(workspace):
    out = stall_answer(workspace, STALLED, agent_type="level-designer", agent_id="ld1")
    assert out["decision"] == "block"
    assert "Now the autopilot." in out["reason"]
    assert stall_answer(workspace, REPORT, agent_type="level-designer", agent_id="ld2") is None


def test_a_report_with_a_pull_request_passes(workspace, tmp_path):
    assert stall_answer(workspace, REPORT) is None
    transcript = write_transcript(tmp_path / "agent.jsonl", REPORT)
    payload = {"hook_event_name": "SubagentStop", "cwd": str(workspace), "agent_type": "backend-engineer"}
    assert dispatch.answer({**payload, "agent_transcript_path": str(transcript)}, CONFIG) is None
    assert stall_answer(workspace, "Opened PR #148 and left auto-merge off." + READ_REPORT) is None


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
    answers = [stall_answer(workspace, STALLED, stop_hook_active=i > 0) for i in range(3)]
    assert [bool(a) for a in answers] == [True, True, False]  # max_refusals = 2, even with stop_hook_active
    assert "Refusal 2 of 2" in answers[1]["reason"]
    other = stall_answer(workspace, STALLED, agent_id="a2")  # another agent run has its own count
    assert other["decision"] == "block"


def test_a_resumed_agent_that_stalls_again_is_refused_again(workspace):
    """Kit #156: the count is spent by the first stall; the allowed end must reset it, or the second stall goes free."""
    first = [stall_answer(workspace, STALLED) for _ in range(3)]
    assert [bool(a) for a in first] == [True, True, False]  # two refusals, then the end is allowed
    # the agent is resumed (SendMessage) and stalls again the same day, with the same agent_id
    second = [stall_answer(workspace, STALLED) for _ in range(3)]
    assert [bool(a) for a in second] == [True, True, False]
    assert "Refusal 1 of 2" in second[0]["reason"]


def test_a_report_resets_the_count_of_the_agent(workspace):
    assert stall_answer(workspace, STALLED)["decision"] == "block"
    assert stall_answer(workspace, REPORT) is None  # the end let through as a report
    again = [stall_answer(workspace, STALLED) for _ in range(3)]  # resumed, stalls again
    assert [bool(a) for a in again] == [True, True, False]
    assert "Refusal 1 of 2" in again[0]["reason"]


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
    tree = _kit_worktree(workspace, "docs-b", 1)
    patch(monkeypatch, "kit_pr_heads", lambda repo: {})
    reason = stall_answer(workspace, STALLED, cwd=str(tree))["reason"]
    assert "without a report" in reason and "docs-b" in reason
    again = stall_answer(
        workspace, STALLED, cwd=str(tree), stop_hook_active=True
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


# --------------------------------------------------------------------------------------------------------------------
# Idle issues: the coordinator's Stop (docs/studio/hooks.md#idle)
# --------------------------------------------------------------------------------------------------------------------

DEADNIGHT = "Ryubara/deadnight"
IDLE = [(DEADNIGHT, 52, "Add the bot rig", "start"), (DEADNIGHT, 57, "Add the bot loop", "start")]


@pytest.fixture()
def idle(monkeypatch):
    """The issues the idle check finds; a test sets `idle.found`. The other tests never reach GitHub."""

    class Found:
        found: list = []
        asked = 0

    state = Found()

    def look(workspace, config, gh=None):
        state.asked += 1
        return list(state.found)

    patch(monkeypatch, "idle_issues", look)
    return state


def test_a_coordinator_with_idle_issues_is_refused_and_told_both_ways_out(workspace, idle):
    idle.found = IDLE + [(DEADNIGHT, 60, "Remove the old rig", "unblock")]
    out = dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG)
    reason = out["reason"]
    assert out["decision"] == "block"
    assert f"{DEADNIGHT}#52" in reason and f"{DEADNIGHT}#57" in reason and "Add the bot rig" in reason
    assert f"{DEADNIGHT}#60" in reason and "what they waited on has closed" in reason
    assert "gds issue start <repo>#N --agent <name>" in reason
    assert 'gds issue block <repo>#N --on <#N|maintainer> --why "<text>"' in reason
    assert "gds issue unblock <repo>#N" in reason
    assert "`Depends on:`" in reason and "--conflict <path>..." in reason  # a block needs a dependency or files
    assert "Refusal 1 of 2" in reason


def test_nothing_idle_lets_the_coordinator_stop(workspace, idle):
    idle.found = []  # every startable issue has an agent, or was blocked with a reason
    assert dispatch.answer(stop_payload(workspace), CONFIG) is None


def test_a_task_agents_stop_and_an_agent_session_are_never_judged(workspace, idle):
    idle.found = IDLE
    out = dispatch.answer(subagent_stop_payload(workspace, "PR #5 opened.\n\nMistakes: none" + READ_REPORT), CONFIG)
    assert out is None and idle.asked == 0  # SubagentStop does not even look
    assert dispatch.answer(stop_payload(workspace, agent_type="godot-engineer"), CONFIG) is None
    assert idle.asked == 0


def test_the_check_is_off_outside_a_workspace_and_when_disabled(tmp_path_factory, workspace, idle):
    idle.found = IDLE
    bare = tmp_path_factory.mktemp("not-a-workspace")
    assert dispatch.answer({"hook_event_name": "Stop", "cwd": str(bare)}, CONFIG) is None
    off = {**CONFIG, "idle": {**CONFIG["idle"], "enforce": False}}
    assert dispatch.answer(stop_payload(workspace), off) is None


def test_it_refuses_at_most_max_refusals_in_a_row_then_starts_again_when_nothing_is_idle(workspace, idle):
    idle.found = IDLE
    reasons = [dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG) for _ in range(3)]
    assert "Refusal 1 of 2" in reasons[0]["reason"] and "Refusal 2 of 2" in reasons[1]["reason"]
    assert reasons[2] is None  # the coordinator ignored it twice: it is let go, never held forever
    # stop_hook_active (the session is already held by a Stop hook) does not turn the check off or make it loop
    assert dispatch.answer(stop_payload(workspace, session_id="s1", stop_hook_active=True), CONFIG) is None
    other = dispatch.answer(stop_payload(workspace, session_id="s2", stop_hook_active=True), CONFIG)
    assert other["decision"] == "block"  # another session has its own count; the flag only skips the other gates
    idle.found = []  # the coordinator started them, so the next Stop passes and the count is forgotten
    assert dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG) is None
    idle.found = IDLE
    assert "Refusal 1 of 2" in dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG)["reason"]


def test_a_refusal_count_lapses_after_an_hour(workspace, idle, monkeypatch):
    idle.found = IDLE
    for _ in range(2):
        assert dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG)
    assert dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG) is None
    now = guards.time.time()
    monkeypatch.setattr(guards.time, "time", lambda: now + 3700)
    assert "Refusal 1 of 2" in dispatch.answer(stop_payload(workspace, session_id="s1"), CONFIG)["reason"]


def test_idle_reasons_come_with_the_other_stop_gates(workspace, idle):
    idle.found = IDLE
    (queue_of(workspace) / "row.md").write_text("a row", encoding="utf-8")
    reason = dispatch.answer(stop_payload(workspace), CONFIG)["reason"]
    assert "Corrections are queued" in reason and "may start now and no agent has them" in reason


# The real look at GitHub, with `gh` replaced by recorded answers.

WINDOW_ISSUES = [
    {"number": 52, "title": "ready", "labels": [{"name": "S-ready-to-start"}], "assignees": [], "body": ""},
    {"number": 53, "title": "agent has it", "labels": [{"name": "S-in-progress"}], "assignees": [], "body": ""},
    {
        "number": 54,
        "title": "blocked on a closed issue",
        "labels": [{"name": "S-blocked"}],
        "assignees": [],
        "body": "Blocked (coordinator, 2026-11-02): waits on #200: the rig",
    },
    {
        "number": 55,
        "title": "blocked on an open one",
        "labels": [{"name": "S-blocked"}],
        "assignees": [],
        "body": "Blocked (coordinator, 2026-11-02): waits on #52: the rig",
    },
]


def fake_gh(issues_json: list | None = None, calls: list | None = None):
    def gh(args: list[str]) -> str:
        if calls is not None:
            calls.append(args)
        return (
            json.dumps(WINDOW_ISSUES if issues_json is None else issues_json) if args[:2] == ["issue", "list"] else "[]"
        )

    return gh


PAUSES: dict[str, str] = {}  # what the hook's issues module reads as paused (the real workspace.toml pauses deadnight)


@pytest.fixture()
def one_repository(monkeypatch):
    patch(monkeypatch, "workspace_repositories", lambda kit: [(DEADNIGHT, "deadnight")])
    PAUSES.clear()
    monkeypatch.setattr(guards.issues_module(guards.KIT), "paused_repositories", lambda kit: dict(PAUSES))


def test_idle_issues_finds_the_window_and_the_unblocked(workspace, one_repository):
    found = REAL_IDLE_ISSUES(workspace, CONFIG, gh=fake_gh())
    assert found == [(DEADNIGHT, 52, "ready", "start"), (DEADNIGHT, 54, "blocked on a closed issue", "unblock")]


def test_all_started_or_blocked_means_nothing_idle(workspace, one_repository):
    rows = [r for r in WINDOW_ISSUES if r["number"] in (53, 55)]
    rows.append({"number": 52, "title": "now started", "labels": [{"name": "S-in-progress"}], "assignees": []})
    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=fake_gh(rows)) == []


def test_idle_issues_fails_open_when_github_cannot_answer(workspace, one_repository):
    def broken(args):
        raise RuntimeError("offline")

    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=broken) == []

    def garbage(args):
        return "not json"

    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=garbage) == []


def test_a_paused_repository_offers_nothing_but_its_critical_issues(workspace, one_repository):
    PAUSES[DEADNIGHT.lower()] = "by the maintainer on 2026-11-07, for kit work first"
    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=fake_gh()) == []  # neither #52 (ready) nor #54 (unblocked)
    rows = [*WINDOW_ISSUES, {"number": 60, "title": "urgent", "labels": [{"name": "P-critical"}], "assignees": []}]
    assert REAL_IDLE_ISSUES(workspace, CONFIG, gh=fake_gh(rows)) == [(DEADNIGHT, 60, "urgent", "start")]


def test_the_stop_hook_reads_the_pause_of_the_kits_workspace_toml():
    paused = guards.issues_module(guards.KIT).paused_repositories(guards.KIT)
    assert paused.get("ryubara/deadnight") and "ryubara/gdstudio" not in paused


def test_every_repository_of_workspace_toml_is_looked_at():
    names = [repo for repo, _ in guards.workspace_repositories(guards.KIT)]
    assert "Ryubara/gdstudio" in names and "Ryubara/deadnight" in names


def test_the_gh_reads_are_cached_for_a_minute(tmp_path, monkeypatch):
    calls = []

    def run(command, **kwargs):
        calls.append(command)
        return subprocess.CompletedProcess(command, 0, stdout="[]", stderr="")

    monkeypatch.setattr(guards.subprocess, "run", run)
    path = tmp_path / "cache" / "idle-check.json"
    first = guards.IdleCache(path, 60, 40)
    first(["issue", "list", "-R", DEADNIGHT])
    first(["issue", "list", "-R", DEADNIGHT])
    first.save()
    assert len(calls) == 1
    second = guards.IdleCache(path, 60, 40)  # the next Stop, seconds later
    second(["issue", "list", "-R", DEADNIGHT])
    assert len(calls) == 1
    now = guards.time.time()
    monkeypatch.setattr(guards.time, "time", lambda: now + 61)
    guards.IdleCache(path, 60, 40)(["issue", "list", "-R", DEADNIGHT])
    assert len(calls) == 2  # a minute later it asks again


def test_a_failing_gh_and_a_used_up_budget_raise_instead_of_hanging(tmp_path, monkeypatch):
    monkeypatch.setattr(
        guards.subprocess, "run", lambda command, **kw: subprocess.CompletedProcess(command, 1, stdout="", stderr="no")
    )
    with pytest.raises(RuntimeError):
        guards.IdleCache(tmp_path / "c.json", 60, 40)(["issue", "list"])
    with pytest.raises(RuntimeError, match="used up"):
        guards.IdleCache(tmp_path / "c.json", 60, 0)(["issue", "list"])


def test_the_hook_reads_the_kits_own_window_code(workspace):
    module = guards.issues_module(guards.KIT)
    assert module is not None and hasattr(module, "compute_window") and hasattr(module, "parse_block")


# --- the disk guard (docs/studio/hooks.md#disk) -----------------------------------------------------------------------


def disk_agent_call(cwd: Path, kind: str = "godot-engineer") -> dict:
    prompt = "Issue: Ryubara/deadnight#7\nDo it." + READ
    return {
        "hook_event_name": "PreToolUse",
        "tool_name": "Agent",
        "cwd": str(cwd),
        "tool_input": {"subagent_type": kind, "prompt": prompt},
    }


def started_ledger(workspace: Path) -> None:
    (workspace / "cache").mkdir(exist_ok=True)
    (workspace / "cache" / "issues-started.json").write_text(
        json.dumps({"started": {"ryubara/deadnight#7": {"branch": "b"}}})
    )


def test_a_task_agent_is_refused_under_the_hard_limit_and_starts_above_it(workspace):
    started_ledger(workspace)
    (workspace / "cache" / "disk-guard.json").write_text(
        json.dumps({"biggest": [{"path": "scratch/deadnight/web-night-load", "gb": 6.1}]})
    )
    FREE["gb"] = 4.0
    reason = denied(disk_agent_call(workspace))
    assert "starting a godot-engineer agent is refused: the disk has 4.0 GB free, under the hard limit of 10" in reason
    assert "scratch/deadnight/web-night-load 6.1 GB" in reason
    FREE["gb"] = 20.0  # soft: agents still start
    assert denied(disk_agent_call(workspace)) == ""


def test_helpers_and_the_reviewer_start_under_the_hard_limit(workspace):
    FREE["gb"] = 1.0
    assert denied(disk_agent_call(workspace, "Explore")) == ""
    assert denied(disk_agent_call(workspace, "reviewer")) == ""


def test_git_worktree_add_is_refused_under_the_hard_limit(workspace):
    repo = workspace / "repos" / "game"
    repo.mkdir(parents=True)
    subprocess.run(["git", "-C", str(repo), "init", "-q", "-b", "main"], check=True)
    command = "git worktree add ../../worktrees/game/x -b x"
    assert denied(shell(command, repo)) == ""
    FREE["gb"] = 2.0
    assert "a new worktree is refused" in denied(shell(command, repo))
    assert denied(shell("git worktree list", repo)) == ""


def test_outside_a_workspace_the_disk_is_not_checked(tmp_path):
    FREE["gb"] = 1.0
    assert "disk" not in denied(disk_agent_call(tmp_path, "Explore"))
    assert denied(shell("git worktree add x", tmp_path)) == ""


def test_an_agent_is_told_to_keep_its_output_small_under_the_soft_limit(workspace):
    FREE["gb"] = 30.0
    text = context("SubagentStart", workspace, agent_type="godot-engineer")
    assert "Disk SOFT: 30.0 GB free" in text and "reduce downloaded CI artifacts to their numbers" in text
    FREE["gb"] = 80.0
    assert "Disk" not in context("SubagentStart", workspace, agent_type="godot-engineer")


def test_the_disk_guard_starts_in_the_background_and_is_throttled(monkeypatch, workspace):
    started: list[list[str]] = []

    class FakePopen:
        def __init__(self, command, **kwargs):
            started.append(command)

    patch(monkeypatch, "start_disk_guard", REAL_START_DISK_GUARD)
    monkeypatch.setattr(guards.subprocess, "Popen", FakePopen)
    monkeypatch.setattr(guards.shutil, "which", lambda name: "/bin/uv")
    assert guards.start_disk_guard(workspace, CONFIG) is True
    assert started[0][-3:] == ["gds", "disk", "guard"]
    assert (workspace / "scratch" / "disk-guard.log").exists()
    assert guards.start_disk_guard(workspace, CONFIG) is False  # within every_seconds
    assert guards.start_disk_guard(workspace, CONFIG, force=True) is True
    off = {**CONFIG, "disk": {**CONFIG["disk"], "enabled": False}}
    assert guards.start_disk_guard(workspace, off, force=True) is False
    # every tool call in a workspace may start it (throttled by the stamp)
    (workspace / "cache" / "disk-guard-started").unlink()
    dispatch.answer(shell("ls", workspace), CONFIG)
    assert len(started) == 3


# --------------------------------------------------------------------------------------------------------------------
# Comments (docs/studio/hooks.md#comments): every route in gh 2.102's manual, and what must keep working
# --------------------------------------------------------------------------------------------------------------------

# The command that put the closing comment on #691, as it was run.
CLOSE_691 = (
    'gh issue close 691 -R Ryubara/gdstudio --comment "$(cat "C:\\Users\\Noah\\scratchpad\\close.md")" '
    "&& gh issue view 691 -R Ryubara/gdstudio --json state,labels -q '.state'; df -k /c | tail -1"
)
COMMENT_COMMANDS = [
    "gh issue comment 5 --body hi",
    "gh issue comment 5 --body '/claim'",
    "gh issue comment 5 --body /release",
    "gh issue comment 5 -b hi --attach a.png",
    "gh issue comment 5 -F body.md",
    "gh issue comment 5 --edit-last -b hi",
    "gh pr comment 5 --body hi",
    "gh pr comment --edit-last --create-if-none -b hi",
    "gh discussion comment 5 --body hi",
    "gh discussion comment DC_abc --edit --body hi",
    "gh pr review 5 --approve",
    "gh pr review 5 --comment --body hi",
    "gh pr review 5 -r -b hi",
    "gh pr review",
]
CLOSE_COMMANDS = [
    "gh issue close 5 --comment hi",
    "gh issue close 5 --comment=hi",
    "gh issue close 5 -c hi",
    "gh issue close 5 -c=hi",
    "gh issue close 5 -chi",
    'gh issue close 5 --reason completed --comment "two words"',
    "gh pr close 5 --comment hi",
    "gh pr close 5 --comment=hi",
    "gh pr close 5 -c hi",
    "gh pr close 5 -dc hi",
    "gh pr close 5 --delete-branch -c hi",
    "gh issue reopen 5 --comment hi",
    "gh issue reopen 5 -c hi",
    "gh pr reopen 5 --comment hi",
    "gh pr reopen 5 -c hi",
]
ROUTE_SPELLINGS = [
    CLOSE_691,
    "gh issue -R o/r close 5 --comment hi",
    "gh issue --repo=o/r comment 5 -b hi",
    "gh pr -R o/r review 5 --approve",
    "gh issue --comment hi close 5",
    '"gh" issue close 5 "--comment" hi',
    "gh.exe issue close 5 -c hi",
    "'C:\\Program Files\\GitHub CLI\\gh.exe' issue close 5 -c hi",
    "& gh issue close 5 -c hi",
    "GH_REPO=o/r gh issue close 5 -c hi",
    "env GH_REPO=o/r gh issue close 5 -c hi",
    "timeout 30 gh issue close 5 -c hi",
    "command gh issue close 5 -c hi",
    "echo 5 | xargs gh issue close -c hi",
    "if true; then gh issue close 5 -c hi; fi",
    "(gh issue close 5 -c hi)",
    "(gh pr review)",
    "try { gh issue close 5 -c hi } catch {}",
    "5, 6 | ForEach-Object { gh issue close $_ -c hi }",
    "gh api -iX POST repos/o/r/issues/5/comments",
    "x=$(gh issue close 5 -c hi)",
    'echo "$(gh pr comment 5 -b hi)"',
    "echo `gh pr comment 5 -b hi`",
    "bash -c 'gh issue close 5 -c hi'",
    "sh -lc 'cd x && gh issue close 5 -c hi'",
    'pwsh -Command "gh pr close 5 -c hi"',
    "cmd /c gh issue close 5 -c hi",
    "eval 'gh issue close 5 -c hi'",
    "gh issue close 5 \\\n  --comment hi",
    "gh issue close 5 `\n  --comment hi",
    "cd sub && gh issue close 5 -c hi",
    "gh alias set done 'issue close --comment finished'",
    "gh alias set note 'issue comment 5 --body hi'",
]
API_COMMANDS = [
    "gh api repos/o/r/issues/5/comments -f body=hi",
    "gh api repos/o/r/issues/5/comments -fbody=hi",
    "gh api repos/o/r/issues/5/comments --raw-field body=hi",
    "gh api repos/o/r/issues/5/comments --field=body=hi",
    "gh api repos/o/r/issues/5/comments -F body=@note.md",
    "gh api repos/o/r/issues/5/comments --input note.json",
    "gh api -X POST repos/o/r/issues/5/comments",
    "gh api -XPOST repos/o/r/issues/5/comments",
    "gh api --method=post repos/o/r/issues/5/comments",
    "gh api --method POST /repos/{owner}/{repo}/issues/5/comments -f body=hi",
    "gh api https://api.github.com/repos/o/r/issues/5/comments -f body=hi",
    "gh api -H 'Accept: application/json' repos/o/r/issues/5/comments -f body=hi",
    "gh api -X PATCH repos/o/r/issues/comments/9 -f body=hi",
    "gh api repos/o/r/pulls/5/comments -f body=hi",
    "gh api repos/o/r/pulls/5/comments/9/replies -f body=hi",
    "gh api -X PATCH repos/o/r/pulls/comments/9 -f body=hi",
    "gh api repos/o/r/pulls/5/reviews -f event=COMMENT",
    "gh api repos/o/r/pulls/5/reviews/9/events -f event=APPROVE",
    "gh api -X PUT repos/o/r/pulls/5/reviews/9 -f body=hi",
    "gh api -X PUT repos/o/r/pulls/5/reviews/9/dismissals -f message=hi",
    "gh api repos/o/r/commits/abc/comments -f body=hi",
    "gh api -X PATCH repos/o/r/comments/9 -f body=hi",
    "gh api gists/abc/comments -f body=hi",
    "gh api -X PATCH gists/abc/comments/9 -f body=hi",
    "gh api repos/o/r/discussions/5/comments -f body=hi",
    "gh api orgs/o/teams/t/discussions/5/comments -f body=hi",
]
# Every mutation of GitHub's schema that adds, edits or submits a comment or a review (asked of the API on 2026-11-05).
COMMENT_MUTATIONS = [
    "addComment",
    "addDiscussionComment",
    "addPullRequestReview",
    "addPullRequestReviewComment",
    "addPullRequestReviewThread",
    "addPullRequestReviewThreadReply",
    "dismissPullRequestReview",
    "submitPullRequestReview",
    "updateDiscussionComment",
    "updateIssueComment",
    "updatePullRequestReview",
    "updatePullRequestReviewComment",
]
GRAPHQL_UNREADABLE = [
    'gh api graphql -f query="$QUERY"',
    "gh api graphql -F query=@mutation.graphql",
    "gh api graphql --input mutation.json",
    'gh api graphql -f query="$(cat mutation.graphql)"',
]
ALLOWED_COMMANDS = [
    "gh issue close 5",
    "gh issue close 5 --reason completed",
    "gh issue close 5 -r 'not planned' -R o/r",
    "gh issue close 5 --reason -c",
    "gh issue close 5 -Rco/r",
    "gh issue close 5 --duplicate-of 4",
    "gh pr close 5",
    "gh pr close 5 --delete-branch",
    "gh pr close 5 -d",
    "gh issue reopen 5",
    "gh pr reopen 5",
    "gh pr merge 5 --squash",
    "gh pr merge 5 --squash --body 'the commit text' --subject 'a title'",
    "gh issue view 5 --comments",
    "gh issue view 5 -c",
    "gh pr view 5 --comments",
    "gh pr view 5 -c",
    "gh discussion view 5 --comments",
    "gh issue list --search comments",
    "gh issue create --title x --body y --attach a.png",
    "gh issue edit 5 --body y",
    "gh pr edit 5 --title y",
    "gh pr edit 5 --add-reviewer someone",
    "gh pr ready 5",
    "gh search issues --commenter me",
    "gh help issue comment",
    "gh help pr review",
    "gh alias set co 'pr checkout'",
    "gh api repos/o/r/issues/5/comments",
    "gh api repos/o/r/issues/5/comments --paginate --jq '.[].body'",
    "gh api --method GET repos/o/r/issues/5/comments -f per_page=100",
    "gh api repos/o/r/pulls/5/reviews",
    "gh api -X DELETE repos/o/r/issues/comments/9",
    "gh api -X DELETE repos/o/r/pulls/comments/9",
    "gh api repos/o/r/issues/5/labels -f 'labels[]=A-hooks'",
    "gh api repos/o/r/pulls/5/requested_reviewers -f 'reviewers[]=someone'",
    "gh api repos/o/r/issues -f title=x -f body='see /comments'",
    "gh api graphql -f query='{ viewer { login } }'",
    'gh api graphql -f query=\'{ repository(owner:"o", name:"r") { pullRequest(number:1) { id } } }\'',
    "gh api graphql -f query='mutation { closeIssue(input:{issueId:\"I\"}) { clientMutationId } }'",
    "gh api graphql -f query='query($n:Int!){ viewer { login } }' -F n=1",
    "uv run --project python gds issue start Ryubara/gdstudio#695 --agent claude",
    "echo gh issue comment 5 --body hi",
    "echo 'gh issue close 5 --comment hi'",
    'grep -n "gh issue close --comment" docs/studio/hooks.md',
    "git log --grep 'gh pr comment'",
    "git commit -m 'hooks: Refuse gh issue close --comment'",
    "git commit -m \"$(cat <<'EOF'\ngh issue close 5 --comment hi\nEOF\n)\"",
    "cat > note.md <<'E'\ngh issue close 5 --comment hi\nE",
    "gh pr view 5 --jq '.body' | grep 'gh issue comment'",
    "gh issue create --title x --body 'never run `gh issue comment` here'",
    "bash -c 'gh issue close 5'",
    "python -c 'print(1)'",
]


def test_a_comment_posted_while_closing_is_refused_with_the_way_out(tmp_path):
    reason = denied(shell(CLOSE_691, tmp_path))
    assert "`gh issue close --comment`" in reason and "under the maintainer's GitHub account" in reason
    assert "gh issue close N" in reason and "scratch" in reason


@pytest.mark.parametrize("command", COMMENT_COMMANDS + CLOSE_COMMANDS + ROUTE_SPELLINGS + API_COMMANDS)
def test_every_gh_route_that_posts_a_comment_is_refused(tmp_path, command):
    assert "under the maintainer's GitHub account" in denied(shell(command, tmp_path))


@pytest.mark.parametrize("mutation", COMMENT_MUTATIONS)
def test_every_graphql_mutation_that_posts_a_comment_is_refused(tmp_path, mutation):
    command = f"gh api graphql -f query='mutation {{ {mutation}(input:{{}}) {{ clientMutationId }} }}'"
    assert "under the maintainer's GitHub account" in denied(shell(command, tmp_path))


@pytest.mark.parametrize("command", GRAPHQL_UNREADABLE)
def test_a_graphql_query_the_guard_cannot_read_is_refused(tmp_path, command):
    assert "cannot be read for a comment" in denied(shell(command, tmp_path))


@pytest.mark.parametrize("tool", ["Bash", "PowerShell"])
def test_the_comment_guard_covers_both_shell_tools(tmp_path, tool):
    payload = shell("gh issue close 5 --comment hi", tmp_path) | {"tool_name": tool}
    assert "under the maintainer's GitHub account" in denied(payload)


@pytest.mark.parametrize("command", ALLOWED_COMMANDS)
def test_what_is_not_a_comment_keeps_working(tmp_path, monkeypatch, command):
    patch(monkeypatch, "held", lambda target, repo, cwd: False)
    assert denied(shell(command, tmp_path)) == ""
