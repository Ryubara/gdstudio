---
areas: [tests, godot]
---
# A test that waited a fixed 12 physics frames for a door's navigation mesh failed about one run in three

2026-11-03

- **Saw:** `test_bot_navigation` failed some runs on `main` with `Out of bounds get index '-1' (on base:
  'PackedVector3Array')`; the real failure sat above it: the first area the doors open answered `UNREACHABLE` (status 4).
  The run is seeded and the same every time, so it looked like the bot, not the clock.
- **Cause:** the test gave the engine `await physics_frame` x 12 after the doors, and the saved mesh a door swaps in
  reaches the navigation map over 8 to 12 physics frames (the map synchronises on a background thread, so the count
  moves with machine load): 12 was the edge. A failed GdUnit assertion does not stop the test, so the next line read
  `points[-1]` of the empty path and raised the engine error that hid the cause.
- **Fix:** wait for the answer, not a frame count: poll until a path from the start to the first sample of every open
  area ends within a metre of it (and the bake is not busy), with a large cap that fails with a message. Guard the
  line after an assertion that can fail (`continue` when `points` is empty). A second test shows the wait is needed
  (the map does not answer the frame a door is bought).
- **Docs:** [Navigation in tests](../engines/godot/navigation-in-tests.md); the same rule as
  [a new region](2026-11-01-wait-for-a-navigation-answer-not-an-iteration-id.md).
