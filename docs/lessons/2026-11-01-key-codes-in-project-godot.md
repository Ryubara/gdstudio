---
areas: [godot, input]
---
# A hand-typed key code in `project.godot` loaded but never fired

2026-11-01

- **Saw:** an action bound to PageUp/PageDown and a shoulder button worked on the gamepad and not on the keyboard, with
  no warning.
- **Cause:** the codes were typed from memory (4194326/4194327); `KEY_PAGEUP` is 4194323 and `KEY_PAGEDOWN` 4194324.
  Godot accepts any integer as a `physical_keycode`.
- **Fix:** write bindings in the editor or print `InputMap.action_get_events(action)` from a probe, and add a test that
  sends the real key.
- **Docs:** [UI controls](../engines/godot/ui-controls.md).
