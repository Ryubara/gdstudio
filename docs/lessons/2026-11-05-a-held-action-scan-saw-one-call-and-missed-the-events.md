---
areas: [tests, input]
---
# A scan for held input actions read one call and missed the ones pressed by an event

2026-11-05

- **Saw:** a probe between the suites of the nine CI shards listed `ui_tab_prev`, `ui_tab_next`, `ui_accept` and
  `ui_cancel` still down after three suites, while `test_input_left_clean` (the scan for a held action, written for
  #1220) passed on every one.
- **Cause:** the scan looked for the text `Input.action_press(` and nothing else. The three suites pressed their
  actions with `Input.parse_input_event` of an `InputEventAction` with `pressed = true` and never sent the release;
  the engine holds an action pressed by an event exactly as one pressed by the call. A check written from the one
  example that failed (the scoreboard key) covered that example's way of pressing.
- **Fix:** the scan counts a function that sends an event with `pressed = true` as a press, accepts only a release in
  the same function or in an `after_test`/`after` reached from it (a node's `pressed = false` in a hook does not
  count), and a read-only test fails when an action is down at the start of its own suite. `InputFixture.release_all()`
  flushes the buffered events (`Input.flush_buffered_events()`, because an event only presses at the frame's flush and
  would land after a release made in the same frame) and releases every action that is down. The check was shown red
  on those three suites first, then green.
- **Check for next time:** when a check is written for a leak, list every way the game's engine lets the thing be set
  (here a call, an action event, a key event, a touch's emulated mouse button) and make the check red against one
  suite for each, before relying on it; a check that sends a release itself hides the leak it looks for, so it only
  reads.
- **Docs:** the game's `docs/research/input-tests.md`, "Finding what a suite leaves for the next".
