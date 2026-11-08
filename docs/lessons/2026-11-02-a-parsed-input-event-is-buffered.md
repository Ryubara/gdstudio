---
areas: [input, blender]
---
# An action read right after `Input.parse_input_event` was not pressed yet

2026-11-02

- **Saw:** in Deadnight's scoreboard tests (#472), an action sent with `Input.parse_input_event` did not show in the
  action state when the test read it.
- **Cause:** `Input.parse_input_event` is buffered: the event waits until the buffer is flushed.
- **Fix:** call `Input.flush_buffered_events()` and wait two frames before reading the action state.
- **Docs:** [UI controls](../engines/godot/ui-controls.md#menus-under-test).
