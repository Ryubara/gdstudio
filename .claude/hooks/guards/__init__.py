"""The guards behind dispatch.py (docs/studio/hooks.md#modules), one module per job. Each check returns the reasons it
refuses a call, with what to do instead; an empty list lets it through. Standard library only.

This module holds the entry points the dispatcher calls: `pre_tool_use`, `post_tool_use`, `stop` and `subagent_stop`,
which run the guards of every module, and `take_warnings`; the other context writers (`session_start`,
`user_prompt_submit`, `subagent_start`) are found in their modules. Each entry point imports the modules it needs when
it runs, so a call loads only what it judges: a Read or a Grep, which runs the PreToolUse hook too, loads two modules.
`guards.<name>` still names every guard and helper, as the single file did."""

from __future__ import annotations

import importlib
from pathlib import Path
from types import ModuleType
from typing import Any

from .disk import start_disk_guard
from .workspace import AGENT_TOOLS, EDIT_TOOLS, SHELL_TOOLS, take_warnings, workspace_of

# What the dispatcher calls (dispatch.py); `__getattr__` finds the other context writers in their modules.
__all__ = ["post_tool_use", "pre_tool_use", "stop", "subagent_stop", "take_warnings"]
# Every module of the package, in the order `guards.<name>` searches them.
MODULES = (
    "agents",
    "behind_base",
    "bodies",
    "comments",
    "commits",
    "disk",
    "docs",
    "idle",
    "issues",
    "launches",
    "learning",
    "mains",
    "merges",
    "proof",
    "protected",
    "session",
    "shell",
    "stall",
    "sweep",
    "workspace",
)


def modules() -> tuple[ModuleType, ...]:
    """Every module of the package, imported now if it was not."""
    return tuple(importlib.import_module(f"{__name__}.{name}") for name in MODULES)


def __getattr__(name: str) -> Any:
    """`guards.<name>` names any guard or helper of the package, as it did when the guards were one file."""
    for module in modules():
        if name in vars(module):
            return vars(module)[name]
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")


def pre_tool_use(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """Every reason to refuse this tool call."""
    tool = payload.get("tool_name", "")
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace:
        start_disk_guard(workspace, config)  # throttled: one stat of a stamp file when it is not yet time
    if tool in AGENT_TOOLS:
        from .agents import check_agents, check_read
        from .disk import check_disk_agent
        from .issues import check_issue

        return (
            check_agents(payload, config)
            + check_issue(payload, config)
            + check_read(payload, config)
            + check_disk_agent(payload, config)
        )
    if tool in EDIT_TOOLS:
        from .protected import check_edit

        return check_edit(payload, config)
    if tool not in SHELL_TOOLS:
        return []
    from .comments import check_comments
    from .launches import check_browser_probe, check_godot_audio, check_godot_window, check_kill, check_tools
    from .protected import check_secrets
    from .shell import change_dir, program, segments

    command = (payload.get("tool_input") or {}).get("command", "")
    cwd = Path(payload.get("cwd") or ".")
    reasons = check_comments(command)
    lost = False  # a `cd` this cannot follow came before: a relative path no longer has a known folder
    for words in segments(command):
        moved, folder = change_dir(words, cwd)
        if moved:
            if folder is None:
                lost = True  # and it stays so for the rest of the line, whatever a later `cd` says
            else:
                cwd = folder
            continue
        name = program(words)
        if name == "git":
            from .commits import check_git

            reasons += check_git(words, cwd, config)
        elif name == "gh":
            from .behind_base import check_behind
            from .bodies import check_pr_body
            from .issues import check_labels
            from .merges import check_hold, check_merge

            reasons += check_merge(words, cwd)
            reasons += check_hold(words, cwd)
            reasons += check_behind(words, cwd)
            reasons += check_labels(words)
            reasons += check_pr_body(words, cwd, config, lost)
        reasons += check_tools(words, config)
        reasons += check_godot_window(words, config)
        reasons += check_godot_audio(words, config)
        reasons += check_browser_probe(words, config)
        reasons += check_kill(words, config)
        reasons += check_secrets(words, command, config)
    return list(dict.fromkeys(reasons))


def stop(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """Every reason to hold the session back once (the proof gate, the lessons queue), or None. A session already
    held by a Stop hook (`stop_hook_active`) is let go, so the gates never loop."""
    from .docs import stop_kit_docs
    from .idle import stop_idle
    from .learning import stop_queue
    from .mains import pull_mains
    from .proof import stop_proof
    from .sweep import start_sweep

    idle = stop_idle(payload, config)  # counts its own refusals, so it ignores stop_hook_active
    if payload.get("stop_hook_active"):
        return idle
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace:
        pull_mains(workspace, config)
        start_sweep(workspace, config)
        start_disk_guard(workspace, config)
    reasons = [
        r for r in (stop_proof(payload, config), stop_queue(payload, config), stop_kit_docs(payload, config), idle) if r
    ]
    return "\n\n".join(reasons) or None


def post_tool_use(payload: dict[str, Any], config: dict[str, Any]) -> str:
    """After a shell command: pull every local main when it merged a pull request; name local image references left in
    a pull request description it opened or edited."""
    if payload.get("tool_name") not in SHELL_TOOLS:
        return ""
    from .bodies import check_opened_body
    from .mains import is_merge, pull_mains
    from .shell import segments
    from .sweep import start_sweep

    notes = [check_opened_body(payload, config)]
    command = (payload.get("tool_input") or {}).get("command", "")
    if any(is_merge(words) for words in segments(command)):
        workspace = workspace_of(Path(payload.get("cwd") or "."))
        if workspace:
            start_sweep(workspace, config, force=True)
        merged = pull_mains(workspace, config, force=True) if workspace else []
        if merged:
            notes.append("Local mains after the merge: " + "; ".join(merged))
    return "\n".join(note for note in notes if note)


def subagent_stop(payload: dict[str, Any], config: dict[str, Any]) -> str | None:
    """An agent may not finish while its kit docs are unpublished, while its report lists mistakes and names no
    section its kit branch edits, or while a task agent's report leaves out the sections it read and the gaps it found
    (held back once: `stop_hook_active` lets the next finish through), or while it ends on a step instead of a report
    (`stop_stall`, which counts its own refusals). Helpers and the reviewer are exempt."""
    from .agents import without_read_lines
    from .docs import mistakes_text, read_report_reason, report_of, sections_named, stop_kit_docs
    from .stall import stop_stall

    stalled = stop_stall(payload, config)
    if payload.get("stop_hook_active"):
        return stalled
    exempt = [*config.get("agents", {}).get("helpers", []), *config.get("issues", {}).get("exempt", [])]
    if payload.get("agent_type") in exempt:
        return None
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace is None:
        return None
    start_disk_guard(workspace, config)
    reasons = [stalled, stop_kit_docs(payload, config)]
    report = report_of(payload)
    if payload.get("agent_type") in config.get("stop_check", {}).get("agents", []) and report.strip():
        reasons.append(read_report_reason(report, config))
    if mistakes_text(report) and not sections_named(workspace, without_read_lines(report)):
        reasons.append(
            "Your report has a Mistakes section but names no topic section that your kit branch updates. Update the "
            "topic section each mistake belongs to with an entry (the approach, what to watch out for, where it was "
            "seen): `gds learn <words>` finds the closest; make a new section only when none fits, with a reason line "
            "(docs/studio/rules.md). Open the kit pull request and name the section in your Mistakes section as "
            "`page.md#anchor`; or, if nothing went wrong, write `Mistakes: none`. Lesson pages are gone: none is "
            "written."
        )
    return "\n\n".join(r for r in reasons if r) or None
