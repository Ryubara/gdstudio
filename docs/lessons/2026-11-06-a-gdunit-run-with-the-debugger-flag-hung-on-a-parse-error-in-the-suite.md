---
areas: [tests, godot]
---
# A GdUnit run with `-d` hung for minutes on a parse error in the suite

2026-11-06

- **Saw:** `godot --headless -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a <suite> -c --ignoreHeadlessMode` printed
  nothing and ran until the `timeout` (twice, 3 minutes each, in Deadnight #1323). The Godot processes stayed behind
  after the shell command was stopped.
- **Cause:** the suite had a parse error (`WebProbe.get_script()`: `get_script` is not a static call). With `-d` the
  engine's script debugger stops at a parse error and waits at `debug>` for input that never comes, so the log fills with
  `Debugger Break, Reason: 'Parser Error: ...'` and the run never ends. The output was piped through `grep`, which hid
  the repeating message.
- **Fix:** read the script's constants through `(load("res://...") as Script).get_script_constant_map()`. To find it, send
  the output to a file and read its tail instead of grepping it; drop `-d` (the repository's other runs omit it) or
  always give the run a short `timeout`, and look for leftover Godot processes of your worktree afterwards and stop
  them by PID.
- **Check for next time:** a GdUnit command with no output for more than a minute is a stuck debugger, not a slow suite:
  read the tail of its log. A test of a script that may lack a symbol (a "fails first" run against old code) reads the
  symbol dynamically so it fails with a value and does not stop the parse.
- **Docs:** [Test speed](../engines/godot/test-speed.md).
