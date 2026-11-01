# The whole GdUnit4 run found no tests

2026-11-01

- **Saw:** a full `GdUnitCmdTool` run that printed the banner, "Scanning for test suites", one `SCRIPT ERROR: Parse
  Error` and no `STARTED` line at all, then ended; the log had no failure to find.
- **Cause:** one test script did not parse (`gdformat` had rewritten a multi-line lambda inside a call into a form
  Godot refuses), and the scanner gives up the whole scan, not just that suite.
- **Fix:** read the top of the log first (`grep -c STARTED` is 0), fix the one script (a named helper function instead
  of the lambda), and rerun. Check the count of started tests before trusting a green run.
- **Docs:** [gdformat turned a chained assert into invalid GDScript](2026-11-01-gdformat-turned-a-chained-assert-into-invalid-gdscript.md).
