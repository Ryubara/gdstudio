"""Agent starts: no agent type without instructions, and a task agent's prompt names the sections of the docs it reads
first as `Read: page.md#anchor` (docs/studio/hooks.md#docs)."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from .issues import _WORK_LINE
from .workspace import kit_root, lessons_module, workspace_of


def check_agents(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """No agent without instructions: `general-purpose` (and an Agent call naming no type, which starts it)."""
    kind = (payload.get("tool_input") or {}).get("subagent_type") or "general-purpose"
    if kind not in config.get("agents", {}).get("refused", []):
        return []
    project = Path(payload.get("cwd") or ".")
    defined = sorted(p.stem for p in (project / ".claude" / "agents").glob("*.md"))
    allowed = defined + config["agents"].get("helpers", [])
    return [f"the agent type {kind!r} has no instructions or enforced rules; start one of: {', '.join(allowed)}"]


# `Read: page.md#anchor[, page.md#anchor ...]` on a line of an agent's prompt or report (a list bullet, a quote mark or
# bold around the label are fine), and the list lines right under it.
_READ_LINE = re.compile(r"(?im)^[ \t>*_-]*Read[*_]*[ \t]*:[*_]*(.*)$")
_LIST_LINE = re.compile(r"^[ \t]*[-*][ \t]+\S")


def read_lines(text: str) -> str:
    """The text of every `Read:` line of a prompt or report, with the list lines under one (`- page.md#anchor`)."""
    lines = text.replace("\r\n", "\n").split("\n")
    out = []
    for i, line in enumerate(lines):
        found = _READ_LINE.match(line)
        if not found:
            continue
        out.append(found.group(1))
        for after in lines[i + 1 :]:
            if not _LIST_LINE.match(after) or _READ_LINE.match(after):
                break
            out.append(after)
    return "\n".join(out)


def without_read_lines(text: str) -> str:
    """A report without its `Read:` lines and the list lines under them: a section the agent read is not one it
    updated, so the Mistakes check (`sections_named`) never counts it."""
    lines = text.replace("\r\n", "\n").split("\n")
    out, skipping = [], False
    for line in lines:
        if _READ_LINE.match(line):
            skipping = True
            continue
        if skipping and _LIST_LINE.match(line):
            continue
        skipping = False
        out.append(line)
    return "\n".join(out)


def check_read(payload: dict[str, Any], config: dict[str, Any]) -> list[str]:
    """A task agent's prompt names the sections of the docs it reads before it starts, as `Read: page.md#anchor`
    lines (`gds brief <owner/repo>#N` proposes them), and every one exists in the kit's docs. Helpers, the reviewer
    and `general-purpose` (refused by `check_agents`) are exempt, as for `check_issue`. A kit whose `lessons.py`
    cannot be loaded checks only that a line names a section."""
    rules = config.get("brief", {})
    inp = payload.get("tool_input") or {}
    kind = inp.get("subagent_type") or "general-purpose"
    exempt = [*config.get("agents", {}).get("helpers", []), *config.get("issues", {}).get("exempt", [])]
    if not rules.get("enforce", True) or kind in exempt or kind in config.get("agents", {}).get("refused", []):
        return []
    workspace = workspace_of(Path(payload.get("cwd") or "."))
    if workspace is None:
        return []
    prompt = inp.get("prompt") or ""
    work = _WORK_LINE.search(prompt)
    ref = f"{work.group(2)}#{work.group(3)}" if work else "<owner/repo>#N"
    gds = f"uv run --project {(workspace / 'repos' / 'gdstudio' / 'python').as_posix()} gds"
    kit = kit_root(workspace)
    module = lessons_module(kit)
    listed = read_lines(prompt)
    refs = module.refs_in(listed) if module else re.findall(r"[\w./-]+\.md#[\w-]+", listed)
    if not refs:
        return [
            f"the agent type {kind!r} starts with the sections of the docs it reads first, and its prompt names none: "
            f"run `{gds} brief {ref}` and put the `Read: <page>.md#<anchor>` lines it prints in the prompt (add or "
            f"drop sections as the task needs; `--why` says why each is proposed)"
        ]
    missing = module.missing_refs(kit, listed) if module else []
    if missing:
        return [
            f"the prompt's Read: lines name sections that do not exist in {(kit / 'docs').as_posix()}: "
            f"{', '.join(missing)}. Name a section as <page under docs/>.md#<anchor> (docs/studio/rules.md#anchors); "
            f"`{gds} brief {ref}` and `{gds} learn <words>` print real ones"
        ]
    return []
