---
areas: [tests, godot]
---
# A probe run with `godot -s` has no autoloads, so it cannot build a night

2026-11-03

- **Saw:** a probe script (`extends SceneTree`, run `godot --headless --path game -s probe.gd`) that built the game's
  night printed `SCRIPT ERROR: Compile Error: Identifier not found: UIRouter` (and `Audio`) at the first script that
  names an autoload, then `Failed to compile depended scripts` down the whole chain, and ran on for minutes with
  nothing printed because the build failed inside `_init`.
- **Cause:** a `-s` SceneTree script starts before the project's autoloads exist, so any class that names one does not
  compile. The probe that only loaded a scene and a navigation mesh (no autoload anywhere in its chain) had worked, which
  hid it.
- **Fix:** write the probe as a scene in the game's `tests/captures/` and run it with
  `godot --headless --path game res://tests/captures/probe.tscn -- <args>`; the autoloads are there, the output goes to
  a log file, and what began as a probe usually stays as the soak. Put `timeout` on it as for any headless run.
- **Docs:** [Probes and tools in headless Godot](../engines/godot/headless-probes.md).
