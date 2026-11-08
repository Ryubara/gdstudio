---
areas: [tests, godot]
---
# A counting lambda that read the state it listened to failed a shard with every test green

2026-11-05

- **Saw:** Deadnight #1074's pull request failed `godot (6)` with 576 tests passed and exit code 0:
  `6 ObjectDB instances were leaked at exit`, `3 resources still in use` (`GdUnitTestSuite.gd`, `client_state.gd`,
  `tests/challenges/test_night_challenges.gd`). The suite had been run inside its folder, whose summary line was
  green, and nobody read its exit lines.
- **Cause:** the test counted events with `state.event_received.connect(func(event): ... state.player_id ...)`: the state
  holds the connection, the lambda holds the state, nothing breaks the cycle. The same shape as the
  [lambda cycle](2026-11-01-refcounted-lambda-cycle-leaks-at-exit.md) lesson, written in a new place.
- **Fix:** the lambda captures the player's id (`var player_id := state.player_id`), not the state, and the test
  disconnects it before it frees the night. The suite alone, on the old code, printed the same 6 and 3; on the fix its
  exit lines are clean. Check for next time: after any test that connects a lambda to an object it also reads, run the
  suite by itself and grep the whole log for `leaked at exit|still in use` before the first push; the summary line
  does not carry it.
- **Docs:** [Test exit leaks](../engines/godot/test-exit-leaks.md) and the
  [lambda cycle](2026-11-01-refcounted-lambda-cycle-leaks-at-exit.md) lesson.
