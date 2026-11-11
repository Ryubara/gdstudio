"""The guards package and the kit modules it loads by file run on the standard library alone: the hooks start under
`uv run --no-project`, with no `gds` package and nothing installed (docs/studio/hooks.md#modules)."""

from __future__ import annotations

import json
import subprocess
import sys

from hook_support import HOOKS, guards

# Run with `-I -S`: no site-packages, no PYTHONPATH, no current folder; only the hooks folder is put on the path.
PROBE = """
import sys
sys.path.insert(0, sys.argv[1])
import guards
for name in ("pr", "lessons", "issues", "hold_switch"):
    if guards.load_kit_module(name) is None:
        raise SystemExit(f"gds_tools/{name}.py does not load with the standard library alone")
print("loaded", " ".join(sorted(m for m in sys.modules if m.startswith("_gds_"))))
"""


def test_the_kit_modules_the_hooks_load_need_only_the_standard_library():
    done = subprocess.run(
        [sys.executable, "-I", "-S", "-c", PROBE, str(HOOKS)], capture_output=True, text=True, timeout=60
    )
    assert done.returncode == 0, done.stdout + done.stderr
    assert done.stdout.split() == [
        "loaded",
        "_gds_hold_switch_for_hooks",
        "_gds_issues_for_hooks",
        "_gds_lessons_for_hooks",
        "_gds_pr_for_hooks",
    ]


def test_one_loader_serves_the_three_kit_modules():
    assert guards.load_pr_module().__name__ == "_gds_pr_for_hooks"
    assert guards.lessons_module(guards.KIT).__name__ == "_gds_lessons_for_hooks"
    issues = guards.issues_module(guards.KIT)
    assert issues is guards.issues_module(guards.KIT)  # loaded once
    assert guards.load_kit_module("no_such_module") is None  # a hook never locks a session out
    assert (guards.KIT / ".claude" / "hooks" / "guards" / "__init__.py").is_file()


TOOL_CALL = """
import json, sys
sys.path.insert(0, sys.argv[1])
import dispatch
call = json.loads(sys.argv[2])
dispatch.answer({"hook_event_name": "PreToolUse", "cwd": sys.argv[1], **call}, dispatch.load_config(None))
print(" ".join(sorted(m.removeprefix("guards.") for m in sys.modules if m.startswith("guards."))))
"""
STOP_ONLY = {"docs", "idle", "learning", "proof", "session", "stall"}


def modules_loaded_by(call: dict) -> set[str]:
    done = subprocess.run(
        [sys.executable, "-I", "-S", "-c", TOOL_CALL, str(HOOKS), json.dumps(call)],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert done.returncode == 0, done.stdout + done.stderr
    return set(done.stdout.split())


def test_a_tool_call_loads_only_the_modules_that_judge_it():
    assert modules_loaded_by({"tool_name": "Read", "tool_input": {"file_path": "x"}}) == {"disk", "workspace"}
    assert modules_loaded_by({"tool_name": "Edit", "tool_input": {"file_path": "x"}}) == {
        "disk",
        "protected",
        "shell",
        "workspace",
    }
    shell = modules_loaded_by({"tool_name": "Bash", "tool_input": {"command": "git push --force"}})
    assert {"comments", "commits", "launches", "protected"} <= shell
    assert not shell & STOP_ONLY
    assert set(guards.MODULES) == {path.stem for path in (HOOKS / "guards").glob("*.py")} - {"__init__"}
