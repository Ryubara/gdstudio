---
areas: [input, tests]
---
# The machine's real mouse turned a capture's camera

2026-11-01

- **Saw:** the same capture script gave different clips: the shoulder camera turned up to 65 degrees between runs.
- **Cause:** the maintainer used the mouse on the same machine; a `--no-window` (or private-desktop) game still reads
  the system's mouse motion, so the player's look took it.
- **Fix (Deadnight #364, #368):** capture and tour scenes set `player.local_input = false` after `Night.start` and drive
  the player with input actions only.
- **Check:** every scripted capture disables the device input of the player it drives.
- **Docs:** [Captures](../capture.md), [Godot without focus](../godot/no-focus.md).
