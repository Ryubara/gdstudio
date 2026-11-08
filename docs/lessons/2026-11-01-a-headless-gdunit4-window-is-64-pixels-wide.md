---
areas: [input, tests]
---
# A mouse event sent in a headless GdUnit4 run landed outside the window

2026-11-01

- **Saw:** a menu test sent a mouse event with `Input.parse_input_event`, but nothing was hovered and `mouse_entered`
  never fired, while key events on the same screen worked.
- **Cause:** in `--headless` the test window is 64 x 64 pixels while the UI is laid out at its stretched size, so a
  mouse event sent in window coordinates lands outside the window.
- **Fix:** send mouse events with `get_viewport().push_input(event, true)` (viewport coordinates, `in_local_coords`);
  then `gui_get_hovered_control()` and `mouse_entered` work. Keys still go through `Input.parse_input_event`. If a
  test-runner control covers the screen as well, see [the click that never reached the
  menu](2026-11-01-gdunit4-mouse-click-never-reaches-the-menu.md).
- **Docs:** [UI controls](../engines/godot/ui-controls.md#menus-under-test).
