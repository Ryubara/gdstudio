# A simulated mouse click never reached the menu under test

2026-11-01

- **Saw:** `Input.parse_input_event` with an `InputEventMouseButton` over a button did nothing in a GdUnit4 test,
  though keyboard and gamepad events on the same screen worked and the control's global rect was inside the window.
- **Cause:** the test runner keeps its own full-window `Stage` control; the screen added as a child of the test sat
  under it, so `gui_get_hovered_control()` was the `Stage`. In a headless run the window is also smaller than a 1920 by
  1080 design size, so a control laid out for the design size can lie outside it.
- **Fix:** add the screen to a `CanvasLayer` (layer 100) and set `get_window().size` to the design size before
  instancing it; then clicks land. Click at `control.get_global_transform_with_canvas() * local_point`.
- **Docs:** [UI controls](../godot/ui-controls.md).
