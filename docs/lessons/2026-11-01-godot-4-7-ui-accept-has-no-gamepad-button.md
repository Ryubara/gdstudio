---
areas: [input, godot-ui]
---
# A gamepad could not press a button or go back in the UI

2026-11-01

- **Saw:** the D-pad moved focus, but joypad A did nothing while Enter worked; docs and tests claimed gamepad support.
- **Cause:** in Godot 4.7.2 `ui_accept` is Enter, Kp Enter and Space and `ui_cancel` is Escape; only the focus
  directions have joypad events. A test that calls `pressed.emit()` or sends keys never notices.
- **Fix:** add an `[input]` section to `project.godot` that repeats the defaults plus joypad A and Start (accept) and B
  (cancel), device -1 (any pad); test with real `InputEventJoypadButton` through `Input.parse_input_event`.
- **Docs:** [UI controls](../engines/godot/ui-controls.md).
