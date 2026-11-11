"""The PreToolUse guards of every day: agent types, commits and pushes, pinned tools, windows, audio and browser
probes, kills, secrets and protected files; the proof gate, SessionStart, and the dispatcher's protocol."""

from __future__ import annotations

import json
import subprocess
import sys

from hook_support import CONFIG, denied, dispatch, guards, shell


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


def test_godot_as_an_argument_is_not_a_start(tmp_path):
    # gdstudio #1192: a search or listing that names a `godot` folder runs find, ls, grep or git, never Godot; a line
    # continued with `\` (bash) or a backtick (PowerShell), or an escaped `\;` ending find's -exec, is one command.
    passes = [
        "find godot -name '*.gd'",
        "ls godot/",
        "grep -r x godot",
        "git -C repos/game diff godot/tests/x.gd",
        "find \\\n  godot -name '*.gd'",
        "find . -name '*.gd' -exec grep -l x {} \\; godot",
        "ls -d \\\n  godot/",
        "ls \\\r\n  godot/",
    ]
    for command in passes:
        assert denied(shell(command, tmp_path)) == "", command
    ps = {**shell("Get-ChildItem `\n  godot -Recurse", tmp_path), "tool_name": "PowerShell"}
    assert denied(ps) == ""


def test_a_path_godot_behind_a_launcher_is_refused(tmp_path):
    # gdstudio #1192: the program is judged after the launcher words that start it (env, cmd /c, start, nohup, timeout).
    refused = [
        "env godot -e",
        "env -u DISPLAY FOO=1 godot --headless",
        "cmd /c godot -e",
        'cmd.exe /d /c "godot --headless --path game"',
        'cmd /c "ls && godot -e"',
        'start "" godot.exe -e',
        "start /b godot --headless",
        "nohup godot --headless &",
        "timeout 600 godot --headless --path game",
        "echo x | godot -e",
        "ls && godot -e",
    ]
    for command in refused:
        assert "pinned" in denied(shell(command, tmp_path)), command
    for command in ("Start-Process godot -ArgumentList '-e'", "Start-Process -Wait -FilePath godot.exe"):
        assert "pinned" in denied({**shell(command, tmp_path), "tool_name": "PowerShell"}), command
    assert "takes the keyboard focus" in denied(shell("env $GODOT --path game", tmp_path))
    pinned = '"C:/ws/tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe"'
    assert denied(shell(f"cmd /c {pinned} --headless --path game", tmp_path)) == ""
    assert "environment" in denied(shell("env", tmp_path))  # a bare env still prints the environment
    assert denied(shell("start https://example.com", tmp_path)) == ""
