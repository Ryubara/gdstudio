---
areas: [tests, godot]
---
# "No error printed" cannot be asserted with GdUnit4 alone

2026-11-02

- **Saw:** a scenario that must print no navigation error (Deadnight #226, a path query made before the map's first
  synchronisation prints `ERROR: ... before first map synchronization`) passed with the error in the log: GdUnit4
  counts a failed assertion, not a line the engine printed, and the CI step only greps for "leaked" and "still in use".
- **Cause:** engine errors go to the log, not to the test.
- **Fix:** install a `Logger` (`OS.add_logger`) for the length of the test, collect `_log_error`, and assert it is
  empty; remove it in `after_test`. A test of the catcher itself makes a query on a map that has not synchronised and
  asserts the line was caught.
- **Docs:** [Navigation in tests](../godot/navigation-in-tests.md#asserting-that-nothing-was-printed).
