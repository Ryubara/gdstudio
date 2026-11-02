# A script that fails to parse hangs headless Godot

2026-11-01

- **Saw:** `godot --headless -s res://tool.gd` printed `SCRIPT ERROR: Parse Error` and then sat idle until the
  30-minute timeout.
- **Cause:** with `-s` a SceneTree script that fails to compile never runs its `quit()`; the engine keeps running an
  empty main loop.
- **Fix:** give every headless tool run a short timeout and look for `SCRIPT ERROR` in the first seconds (or run
  `--check-only` first); `:=` from a Dictionary value is a warning treated as an error in projects that turn warnings
  up.
- **Docs:** [Godot index](../godot/index.md).
