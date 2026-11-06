---
areas: [tests, godot]
---
# A test freed a screen inside the signal it was waiting on

2026-11-06

- **Saw:** `test_night_tap_targets` printed three `ERROR: Object ... was freed or unreferenced while a signal is being
  emitted from it` lines, backtrace `RouterFixture.clear` <- the test <- `_night` (`await night.ready_to_play`) <-
  `Night._go`. The suite passed, so no check saw it.
- **Cause:** an `await signal` resumes the caller synchronously inside the emit. A test that does nothing between
  `await night.ready_to_play` and `RouterFixture.clear` (the other tests of the suite read the screen first) freed the
  screen, and so the night, while `Night._go` was still emitting `ready_to_play`. The game does not do this: its
  handlers of that signal free nothing, and the router frees its screens between its own jobs. A fault of the fixture's
  contract, not a product fault.
- **Fix:** `RouterFixture.clear` yields one frame before freeing anything, which leaves every emit its caller was in;
  `test_router_fixture.gd` checks the screen is still alive when `clear` first gives control back. When a headless run
  must be free of `ERROR`, grep the log for it: a green suite proves nothing about engine errors.
- **Docs:** the doc comment of `RouterFixture.clear` in Deadnight.
