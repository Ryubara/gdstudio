# GdUnit4 with `-d` hangs on the first script error

2026-11-01

- **Saw:** a headless GdUnit4 run printed `Debugger Break` over and over and never finished.
- **Cause:** the documented command line passes `-d`, which attaches Godot's debugger; a script error then stops the
  engine at a `debug>` prompt that waits for input nobody gives.
- **Fix:** run `godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests -c
  --ignoreHeadlessMode` without `-d`; script errors are then reported as test failures.
- **Docs:** deadnight `docs/research/ui-foundation.md` (Tests).
