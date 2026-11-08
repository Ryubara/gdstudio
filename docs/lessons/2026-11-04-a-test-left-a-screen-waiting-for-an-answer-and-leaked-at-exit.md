---
areas: [tests, godot]
---
# A test left a screen waiting for an answer and the run leaked at exit

2026-11-04

- **Saw:** a new GdUnit suite passed, and its run ended with `leaked at exit` and `Resource still in use:
  .../together_screen.gd`, `lobby_screen.gd`, `night_screen.gd` and a list of script classes. The CI step fails any run
  with those lines, though every test passed; the same screens opened by the older suites left nothing.
- **Cause:** the suite put the Play together screen in its name prompt by calling `_ask_name()`, which ends in
  `await name_decided`. Nothing ever answered, so the screen was freed with its coroutine suspended on a signal that
  would never fire, and the suspended function state kept the script (and everything the script preloads) alive to the
  end of the run.
- **Fix:** whatever a fixture starts that awaits an answer, it answers before it frees the screen (here the fixture
  emits `name_decided` in `close()`). Run the new suite alone, without `--verbose`, and look for `leaked at exit` before
  pushing: a passing summary does not show it.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#a-card-taller-than-its-screen).
