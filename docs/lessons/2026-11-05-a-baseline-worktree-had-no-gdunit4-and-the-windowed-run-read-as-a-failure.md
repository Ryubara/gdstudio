---
areas: [tests, tools]
---
# A baseline worktree of main had no GdUnit4, and its windowed run exited 1 with no test result

2026-11-05

- **Saw:** to tell a failing suite from a regression, three suites were run on a detached worktree of `origin/main`
  through `gds godot`; each exited 1 and printed `Attempt to open script 'res://addons/gdUnit4/bin/GdUnitCmdTool.gd'
  ... File not found`, which looks like a failure of the suite.
- **Cause:** `addons/gdUnit4` is excluded from git in the game repository (`.git/info/exclude`) and is installed into a
  worktree by `gds issue start`; a worktree made by hand has none.
- **Fix:** copy `game/addons/gdUnit4` from a started worktree, import once (`--headless --import`), run again. Read the
  log for `Overall Summary` before comparing numbers; "exit 1, no summary" is a run that never started.
- **Docs:** [No focus](../godot/no-focus.md).
