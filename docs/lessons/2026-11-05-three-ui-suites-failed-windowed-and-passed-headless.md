---
areas: [tests, godot-ui]
---
# Three UI suites failed in a window and passed headless, so CI never saw them

2026-11-05

- **Saw:** Deadnight's `test_hover_room` (the Plate button), `test_bot_wheel_input` and `test_night_crosshair` failed
  under `gds godot` on `main` and passed headless, as CI runs them, with 0 skipped; nobody saw them for days.
- **Cause:** not the engine: the game's own switches that a headless run turns the other way. A 64 pixel headless
  window never makes the menu shell a phone's (`MenuShell._is_compact`), so the "phone" canvas of a hover suite ran the
  desktop layout in CI and the real phone layout (a Plate button 1.4 units too tall for its 99 unit strip) only in a
  window; a window plays the helicopter drop that opens a night (`NightScreen.arrival_enabled`), which holds the look,
  the touch layer and the HUD and hides the reticle, and a headless run has none.
- **Fix:** tell the headless run what a window of this size is (`MenuShell.phone_mode` from `MenuScale.is_phone`, which
  failed headless on the old game with the window's own line), and start a suite that is not about the drop with no drop
  due (`NightScreen.arrival_enabled = false`, restored), while a second set of tests plays it. Check for next time: a
  suite that pushes a night or a menu screen is run once in a window before its pull request (`gds godot --timeout 600
  -- ... GdUnitCmdTool.gd -a <suite>`); a "phone" case that sees no clipped button measured nothing, so it asserts it
  saw some.
- **Docs:** the game's `docs/research/windowed-vs-headless-tests.md`; [No focus](../godot/no-focus.md).
