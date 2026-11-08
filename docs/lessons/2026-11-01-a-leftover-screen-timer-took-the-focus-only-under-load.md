---
areas: [tests, input]
---
# A test lost the focus to a screen an earlier suite left behind, only on a loaded machine

2026-11-01

- **Saw:** a GdUnit4 test that focuses a control and presses the d-pad found the focus on another screen's button (the
  main menu's `Play`) in a full run with five or more suites at once; alone, or on an idle machine, it passed.
- **Cause:** an autoload (the screen router) is shared by every suite in the run. The suite before had left the real
  main menu on it, and the menu's entrance `create_timer` (0.55 s of wall time) ended and called `grab_focus()` in
  whichever test was running by then; under load the tests are slower, so that was a different, unlucky test.
- **Fix:** a suite that starts a screen on a shared autoload clears it in `after_test`; a suite that builds its own
  screen clears the autoload in `before_test`. Find the thief by printing the time and frame in the screen's timer
  callback and in `before_test`, then run just the two neighbouring suites (6 s) under load (at most four parallel
  suites).
- **Docs:** [UI controls](../engines/godot/ui-controls.md); Deadnight `docs/research/ui-foundation.md`.
