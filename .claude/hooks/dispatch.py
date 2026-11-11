"""GDStudio's Claude Code hook dispatcher: the one entry point for every hook event (docs/studio/hooks.md).

`.claude/settings.json` sends every event here (a game repository through its `launch.py`). Each event runs the guards
registered for it in `guards.py`; every reason they give is returned at once, so an agent fixes all of them in one go.

Answers follow Claude Code's JSON protocol with exit code 0: `permissionDecision: deny` before a tool runs, `decision:
block` at Stop and SubagentStop, `additionalContext` at SessionStart, UserPromptSubmit, SubagentStart and PostToolUse.
Never exit code 2: `uv` and Python also exit 2 when they cannot start, and a PreToolUse hook exiting 2 would block
every tool call. If the dispatcher itself breaks, it lets the call through and says so on stderr: a broken guard
must never lock a session out.

Standard library only: hooks run under `uv run --no-project`.
"""

from __future__ import annotations

import json
import os
import sys
import tomllib
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import guards  # noqa: E402  (after the path insert, so the module beside this file is found)

DEFAULTS = HERE / "hooks.toml"
# The events that only add context, and the guard that writes it.
CONTEXT_EVENTS = {
    "SessionStart": "session_start",
    "UserPromptSubmit": "user_prompt_submit",
    "SubagentStart": "subagent_start",
    "PostToolUse": "post_tool_use",
}


def load_config(project_dir: Path | None) -> dict[str, Any]:
    """The kit's hooks.toml, with a project's `.claude/hooks.local.toml` replacing the keys it sets."""
    config = tomllib.loads(DEFAULTS.read_text(encoding="utf-8"))
    local = project_dir / ".claude" / "hooks.local.toml" if project_dir else None
    if local and local.exists():
        for section, values in tomllib.loads(local.read_text(encoding="utf-8")).items():
            config.setdefault(section, {}).update(values)
    return config


def answer(payload: dict[str, Any], config: dict[str, Any]) -> dict[str, Any] | None:
    """The JSON answer for one hook input, or None to let it pass silently."""
    event = payload.get("hook_event_name")
    if event == "PreToolUse":
        reasons = guards.pre_tool_use(payload, config)
        warnings = guards.take_warnings()  # a guard that failed open says so: the user sees it, and so does the model
        if reasons:
            text = "Refused by GDStudio's hooks:\n" + "\n".join(f"- {r}" for r in reasons)
            return {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": text,
                }
            }
        if warnings:
            text = "GDStudio's hooks let this through unchecked:\n" + "\n".join(f"- {w}" for w in warnings)
            return {
                "systemMessage": text,
                "hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": text},
            }
    elif event in ("Stop", "SubagentStop"):
        reason = (guards.stop if event == "Stop" else guards.subagent_stop)(payload, config)
        if reason:
            return {"decision": "block", "reason": reason}
    elif event in CONTEXT_EVENTS:
        text = getattr(guards, CONTEXT_EVENTS[event])(payload, config)
        if text:
            return {"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}
    return None


def main() -> int:
    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    try:
        payload = json.loads(raw or "{}")
        project = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd")
        result = answer(payload, load_config(Path(project) if project else None))
    except Exception as error:  # the dispatcher broke: let the call through, and say why
        sys.stderr.write(f"gdstudio hooks: {type(error).__name__}: {error} (call allowed)\n")
        return 0
    if result is not None:
        sys.stdout.write(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
