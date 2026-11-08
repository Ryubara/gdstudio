---
areas: [input, tools]
---
# Injected touch drags turned the view by the wrong amount

2026-11-01

- **Saw:** a test that sent a look drag of 100 units to the touch controls turned the view by a different amount at
  each window size; separately, every touch on the controls also fired, as if clicked.
- **Cause:** `Input.parse_input_event` takes window pixels and runs them backwards through the viewport stretch, so
  a drag written in canvas units is rescaled. And with `input_devices/pointing/emulate_mouse_from_touch` on, each
  touch also produces a mouse click, which the game maps to Fire.
- **Fix:** multiply canvas positions by the viewport's `get_final_transform()` before injecting; turn
  `Input.emulate_mouse_from_touch` off while touch controls are shown. In a web check, read a JavaScript `eval`
  answer with `int()`: it may come back as a bool or a number.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#touch-controls).
