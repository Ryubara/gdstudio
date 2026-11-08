---
areas: [tests, tools]
---
# A full GdUnit4 run was cut off at gds godot's 900 seconds

2026-11-03

- **Saw:** a whole-suite GdUnit4 run of Deadnight (#683) through `gds godot -- --headless ... GdUnitCmdTool.gd -a res://tests`
  ended with `gds: godot did not finish within 900 s and was stopped`, part-way through `tests/net`, and no summary.
- **Cause:** `gds godot` has its own `--timeout`, 900 s by default, separate from the shell's `timeout`; the full suite
  (3,400 cases) takes longer.
- **Fix:** give the run `gds godot --timeout 3500 -- ...` (and a shell timeout above it), in the background; check the
  log for `did not finish` before reading the summary.
- **Docs:** [Starting Godot without the focus](../engines/godot/no-focus.md).
