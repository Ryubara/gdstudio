"""The maintainer's hold switch (docs/studio/hooks.md#hold): off, nobody takes `S-hold` off; on, the coordinator may,
and each lift is logged; a task agent never may; and no agent can turn the switch on. The key is built from the
module's constants, so this file never holds the assignment the guards refuse."""

from __future__ import annotations

from pathlib import Path

import pytest
from hook_support import CONFIG, denied, dispatch, guards, patch

from gds_tools import hold_switch
from gds_tools import workspace as ws

LIFT = "gh pr edit 7 --remove-label S-hold"
TASK_AGENT = {"agent_id": "a1b2", "agent_type": "godot-engineer"}


@pytest.fixture(autouse=True)
def nothing_asks_github(monkeypatch):
    """Pull request 7 carries the hold; nothing reaches GitHub."""
    patch(monkeypatch, "held", lambda target, repo, cwd: str(target) == "7")


def turn(workspace: Path, value: str, extra: str = "") -> None:
    """Write the switch the way the maintainer does, by hand."""
    body = f'[tools]\ngodot = "x"\n\n[{hold_switch.SECTION}]\n{hold_switch.KEY} = {value}\n{extra}'
    (workspace / hold_switch.FILE).write_text(body, encoding="utf-8")


def run(workspace: Path, command: str, **who) -> str:
    payload = {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": command}}
    return denied({**payload, "cwd": str(workspace), **who})


def edit(workspace: Path, tool: str, path: Path, **tool_input) -> str:
    payload = {"hook_event_name": "PreToolUse", "tool_name": tool, "cwd": str(workspace)}
    return denied({**payload, "tool_input": {"file_path": str(path), **tool_input}})


def lifts(workspace: Path) -> str:
    log = workspace / hold_switch.LOG
    return log.read_text(encoding="utf-8") if log.exists() else ""


# --- off: today's refusal, for everyone ---


@pytest.mark.parametrize("value", [None, "false", '"true"', "1"])
def test_off_or_missing_refuses_the_coordinator(workspace, value):
    if value is not None:
        turn(workspace, value)
    assert "only by the maintainer" in run(workspace, LIFT)
    assert lifts(workspace) == ""


def test_a_file_that_cannot_be_read_is_off(workspace):
    (workspace / hold_switch.FILE).write_text("[hold\nnot toml", encoding="utf-8")
    assert not hold_switch.read(workspace).on
    assert run(workspace, LIFT) != ""


# --- on: the coordinator may lift, and it is logged ---


@pytest.mark.parametrize(
    "command",
    [LIFT, "gh pr edit 7 --remove-label=S-hold", "gh pr edit 7 -R Ryubara/gdstudio --remove-label docs,S-hold"],
)
def test_on_lets_the_coordinator_lift_and_logs_it(workspace, command):
    turn(workspace, "true")
    assert run(workspace, command, session_id="s-1") == ""
    line = lifts(workspace)
    assert "7" in line and "s-1" in line and "coordinator" in line


def test_the_log_names_the_repository(workspace):
    turn(workspace, "true")
    run(workspace, "gh pr edit 7 -R Ryubara/gdstudio --remove-label S-hold")
    assert "Ryubara/gdstudio#7" in lifts(workspace)


def test_on_a_task_agent_is_still_refused(workspace):
    turn(workspace, "true")
    reason = run(workspace, LIFT, **TASK_AGENT)
    assert "coordinator" in reason
    assert lifts(workspace) == ""


def test_a_session_started_as_an_agent_is_not_the_coordinator(workspace):
    turn(workspace, "true")
    assert run(workspace, LIFT, agent_type="godot-engineer") != ""


@pytest.mark.parametrize(
    "command",
    [
        "gh label delete S-hold --yes",
        "gh label edit S-hold --name not-a-hold",
        "gh api -X DELETE repos/o/r/issues/7/labels/S-hold",
        "gh api -X PUT repos/o/r/issues/7/labels -f 'labels[]=docs'",
        "gh pr merge 7 --squash",
    ],
)
def test_on_the_label_is_still_never_deleted_renamed_or_merged_past(workspace, command):
    turn(workspace, "true")
    assert run(workspace, command) != ""


def test_doctor_says_whether_it_is_on(workspace):
    assert hold_switch.read(workspace).describe().startswith("off")
    turn(workspace, "true", f'{hold_switch.SINCE} = "2026-11-11"\n{hold_switch.BY} = "maintainer"\n')
    line = hold_switch.read(workspace).describe()
    assert line.startswith("on") and "2026-11-11" in line and "maintainer" in line


# --- no agent can turn it on ---


@pytest.mark.parametrize("who", [{}, TASK_AGENT])
@pytest.mark.parametrize("tool", ["Edit", "Write"])
def test_the_file_is_never_edited_by_a_session(workspace, who, tool):
    assert "protected" in edit(workspace, tool, workspace / hold_switch.FILE, content="x", **who)


@pytest.mark.parametrize(
    "command",
    [
        "echo '[hold]' >> {ws}/gdstudio.local.toml",
        "cat x.toml>gdstudio.local.toml",
        "Add-Content -Path gdstudio.local.toml -Value x",
        "Set-Content gdstudio.local.toml x",
        "sed -i 's/false/true/' {ws}/gdstudio.local.toml",
        "echo x | tee -a gdstudio.local.toml",
        "cp other.toml {ws}/gdstudio.local.toml",
        "cp /tmp/t/gdstudio.local.toml {ws}/",
        "cp /tmp/t/gdstudio.local.toml .",
        "Copy-Item /tmp/t/gdstudio.local.toml -Destination {ws}",
        "mv /tmp/t/gdstudio.local.toml {ws}/gdstudio.local.toml",
        "python -c \"open('gdstudio.local.toml','a').write('x')\"",
        'python -c "import x; x.{key} = True"',
        "printf '{key}=true' > /tmp/x",
    ],
)
def test_a_shell_write_of_the_switch_is_refused(workspace, command):
    command = command.format(ws=workspace.as_posix(), key=hold_switch.KEY)
    assert "maintainer" in run(workspace, command)
    assert "maintainer" in run(workspace, command, **TASK_AGENT)


@pytest.mark.parametrize(
    "command",
    [
        "cat gdstudio.local.toml",
        "grep tools {ws}/gdstudio.local.toml",
        "cp {ws}/gdstudio.local.toml /tmp/t/",
        "cp {ws}/.gdstudio-workspace {ws}/gdstudio.local.toml /tmp/t",
        "cat gdstudio.local.toml > /tmp/t/copy.toml",
        "head gdstudio.local.toml 2>/dev/null",
        "uv run --project python gds doctor",
    ],
)
def test_reading_or_copying_the_file_away_passes(workspace, command):
    assert run(workspace, command.format(ws=workspace.as_posix())) == ""


@pytest.mark.parametrize("name", ["flip.py", "notes.toml"])
def test_writing_the_key_into_any_file_is_refused(workspace, name):
    content = f"{hold_switch.KEY} = true\n"
    assert "maintainer" in edit(workspace, "Write", workspace / name, content=content)
    assert "maintainer" in edit(workspace, "Edit", workspace / name, old_string="a", new_string=content)
    many = {"edits": [{"old_string": "a", "new_string": f'"{hold_switch.KEY}": True'}]}
    assert "maintainer" in edit(workspace, "MultiEdit", workspace / name, **many)


def test_naming_the_key_without_setting_it_passes(workspace):
    content = f'KEY = "{hold_switch.KEY}"\nSee `{hold_switch.KEY}` under `[hold]`.\n'
    assert edit(workspace, "Write", workspace / "hold.py", content=content) == ""


def test_workspace_init_keeps_the_switch(tmp_path):
    turn(tmp_path, "true", f'{hold_switch.SINCE} = "2026-11-11"\n')
    ws.write_local_config(tmp_path, {}, "windows-x64")
    text = (tmp_path / ws.LOCAL_FILE).read_text(encoding="utf-8")
    assert hold_switch.read(tmp_path).on and "[tools]" in text and text.count("[hold]") == 1


def test_workspace_init_never_adds_a_switch(tmp_path):
    ws.write_local_config(tmp_path, {}, "windows-x64")
    assert "[hold]" not in (tmp_path / ws.LOCAL_FILE).read_text(encoding="utf-8")


def test_the_file_names_agree():
    assert hold_switch.FILE == ws.LOCAL_FILE
    assert any(p.endswith(hold_switch.FILE) for p in CONFIG["protect"]["paths"])


def test_the_refusal_reaches_a_session(workspace):
    out = dispatch.answer(
        {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": LIFT}, "cwd": str(workspace)},
        CONFIG,
    )
    assert out["hookSpecificOutput"]["permissionDecision"] == "deny"
    assert guards.HOLD in out["hookSpecificOutput"]["permissionDecisionReason"]
