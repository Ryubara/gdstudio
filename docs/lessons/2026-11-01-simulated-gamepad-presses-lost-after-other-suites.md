---
areas: [input, godot-ui]
---
# Simulated d-pad presses worked alone and were lost in the full run

2026-11-01

- **Saw:** a GdUnit4 test that sent `InputEventJoypadButton` presses with `Input.parse_input_event` moved a selection
  three times when its suite ran alone, but once (or not at all) in the full run.
- **Cause:** the `Input` singleton tracks which buttons are held across suites, and the UI router swallows input while
  a transition runs; a press or transition left over from an earlier suite makes the new press a no-op.
- **Fix:** send events with `get_viewport().push_input(event)` (press and release a frame apart), and wait for the
  router to be idle in `before_test` when it is busy.
- **Docs:** [UI controls](../engines/godot/ui-controls.md).
