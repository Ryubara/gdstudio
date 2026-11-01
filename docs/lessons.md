# Lessons

Problems we hit and how we solved them, newest first. One entry each: what you saw, why it happened, the fix, and
where it is documented. Before solving something, search this page: it may have happened before.

## 2026-11-01: hooks judged text as commands

- **Saw:** the hooks refused harmless commands: a Python heredoc line starting `blender = ...`, and a `grep -E "a|godot"`.
- **Cause:** the guard split shell lines on `|` inside quotes and read heredoc bodies as commands.
- **Fix:** split only outside quotes; drop heredoc and here-string bodies before judging.
- **Docs:** Hooks (`docs/hooks.md`).

## 2026-11-01: new agent definitions invisible to a running session

- **Saw:** `.claude/agents/*.md` written mid-session; starting one failed with "agent type not found".
- **Cause:** Claude Code loads project agents when a session starts.
- **Fix:** restart with `claude --resume <session id>` (the conversation is kept).
- **Docs:** Agents (`docs/agents.md`).

## 2026-11-01: Blender's download site refuses scripts

- **Saw:** downloads from download.blender.org returned a browser-check page, not the file.
- **Cause:** the site sits behind a bot check.
- **Fix:** the official mirrors (same checksum file), pinned in `tools.toml`.
- **Docs:** [Workspace](workspace.md#tools).

## 2026-11-01: Godot rewrites project.godot

- **Saw:** a hand-written comment in `project.godot` vanished after the first import.
- **Cause:** Godot owns that file and rewrites it in its own format.
- **Fix:** never hand-comment it; local-only settings go in an untracked `override.cfg`.
- **Docs:** [Workspace](workspace.md).
