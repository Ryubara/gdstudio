---
areas: [input, godot]
---
# A single key press produced two jump or swap commands

2026-11-01

- **Saw:** a test pressed the shoulder-swap action for one tick and the shoulder ended on the original side.
- **Cause:** `Input.is_action_just_pressed` was read on a physics tick; a press that lands between ticks can report
  as "just pressed" on two consecutive physics frames. Pairing it with an `_unhandled_input` event flag counted the
  same press again.
- **Fix:** the player keeps its own per-tick edge: remember whether the action was down last tick and report the
  rising edge once. The same code works headless, where GdUnit4 does not transport input events at all (actions work,
  mouse motion does not; call `_unhandled_input` with an event instead).
- **Docs:** [Tests](../godot/index.md).
