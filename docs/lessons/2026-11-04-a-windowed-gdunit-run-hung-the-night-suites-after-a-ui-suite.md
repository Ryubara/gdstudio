---
areas: [tests, tools]
---
# A windowed GdUnit run hung every night suite that came after a UI suite

2026-11-04

- **Saw:**
  `gds godot -- ... GdUnitCmdTool.gd -a <a UI suite that pushes mouse events> -a res://tests/ui/test_night_crosshair.gd`
  never finished: the night's `UIRouter.idle` never fired and each test timed out after 5 minutes (and `gds godot` itself
  stopped the run at its default 900 seconds, which also cut the log short). The crosshair suite alone passed in 14 s.
- **Cause, found on 2026-11-05 (Deadnight #1207):** it was not the pointer events. GdUnit minimizes the window after
  every suite, a minimized window draws no frame, and the night's warm-up waits for `RenderingServer.frame_post_draw`;
  any suite that opens a night after another suite hung, in either order. See
  [the lesson](../engines/godot/minimized-window.md) and
  [A minimized window draws nothing](../engines/godot/minimized-window.md). Written first as "not found in the code".
  The same pair run **headless**, as CI runs it (`godot --headless ... --ignoreHeadlessMode`),
  passed in 11 s; the hang is in the windowed run on the private desktop after the first suite's pushed pointer events.
  Bisecting by hand was misleading for a time: `-a file.gd:test_name` runs nothing of that file when more than one is
  given, so "single tests pass" was the second suite's result alone.
- **Fix:** run GdUnit headless like CI (`godot --headless --path game -s
  res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a <suite> -c --ignoreHeadlessMode`) and keep `gds godot` for
  captures and for the one suite that needs a window; give a long windowed run `gds godot --timeout 3000 -- ...`;
  a log written through `sed` is block-buffered and looks empty until the end, so read `FAILED` and
  `Overall Summary` after the run, not during it.
- **Docs:** [No focus](../engines/godot/no-focus.md).
