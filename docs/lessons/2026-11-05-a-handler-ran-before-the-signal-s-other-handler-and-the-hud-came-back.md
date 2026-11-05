---
areas: [tests, godot-ui]
---
# The HUD came back over the end board because two handlers of one signal ran in connect order

2026-11-05

- **Saw:** `test_night_screen_end` failed in a window and passed headless: after the night ended the HUD was visible
  over the end board (`Expecting 'false' but is 'true'`), along with a line that was only the test's (the helicopter
  drop hides the HUD on the first frame).
- **Cause:** the screen's `night_over` handler hid the HUD and put the board up, then the night's own `night_over`
  handler closed a drop still playing, whose `arrival_ended` made the screen show the HUD again. Handlers of one
  signal run in the order they were connected, and the screen connects before the night's own. A headless run has no
  drop, and the rules never end a night under one, so only a test that forces it could see it.
- **Fix:** the late handler (`_on_arrival_ended`) does nothing when the board is up, and a test ends the night under
  the drop on purpose. Read each line of a windowed failure on its own: one was the test's switch, one was the game.
  A handler that undoes another's work needs a guard on the state the first one set, not on the order.
- **Docs:** Deadnight `docs/research/windowed-night-ui-suites.md`.
