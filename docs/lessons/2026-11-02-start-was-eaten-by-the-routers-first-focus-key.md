---
areas: [input, godot-ui]
---
# The pad's Start did nothing in the night: the UI router ate it

2026-11-02

- **Saw:** a controller's Start button did not pause the game (Deadnight #494).
- **Cause:** `project.godot` binds Start (button 6) to both `pause` and `ui_accept`. When no control has the focus, the
  UI router spends the first focus key on focusing the top screen and marks the event handled, so every Start in a
  running night was eaten before `pause` saw it. The pause matrix test pressed Esc first, which focused Resume, so its
  Start press then hit Resume and passed. Behind it (from #481): after a Start resume the player waited for pointer lock,
  which a browser never grants to a gamepad button, so a pad-only web player had no controls.
- **Fix (Deadnight #519):** a live game screen says it does not want the focus key, so Start reaches `pause`; the mouse
  alone waits for pointer lock, a pad never does.
- **General:** press every action as the first input on the live screen, on a pad (device 0 and another id) and in the
  web build with a virtual pad. Anything bound to the same button as a `ui_*` action is tested on a screen with no
  focused control.
- **Docs:** [What the maintainer caught](../studio/maintainer-corrections.md).
