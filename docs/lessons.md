# Lessons

Problems we hit and how we solved them, newest first. One entry each: what you saw, why it happened, the fix, and
where it is documented. Before solving something, search this page: it may have happened before.

## 2026-11-01: original weapons read thin beside the kit

- **Saw:** weapons drawn at real proportions had the kit's lengths and triangle counts but looked spindly on a turntable
  sheet beside the kit's guns.
- **Cause:** the kit fattens every cross-section; a real rifle's barrel, receiver and stock are far thinner.
- **Fix:** scale every part 1.4-1.5x across its length before chamfering; check by eye on a sheet, not by the numbers.
- **Docs:** [Blender weapons](blender/weapons.md).

## 2026-11-01: a kit weapon's hold does not carry over to a new weapon

- **Saw:** copying the kit AK's transform in the Soldier's hand onto a new gun made it tiny.
- **Cause:** the AK and Sniper copies in the character file carry rescaled mesh data (object scale 0.21-0.42); the
  Shotgun and Shovel copies are unit-scale.
- **Fix:** take the hold from the Shotgun (guns) or the Shovel (melee).
- **Docs:** [Blender weapons](blender/weapons.md#axes-origin-and-the-hold).

## 2026-11-01: Movie Maker ignores `--resolution`

- **Saw:** `--write-movie` with `--resolution 1280x720` (or 960x540) still wrote 1920x1080 frames.
- **Cause:** the movie is the project's viewport size; the window resolution request does not change it (Godot 4.7.2).
- **Fix:** scale afterwards, which `gds capture sheet` and `gds capture clip` do.
- **Docs:** [Capture](capture.md).

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
