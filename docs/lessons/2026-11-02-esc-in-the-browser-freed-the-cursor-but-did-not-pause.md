---
areas: [input, web]
---
# Esc in the browser freed the cursor but did not pause the game

2026-11-02

- **Saw:** in Deadnight's web build, Esc freed the cursor but the night kept going: moving the mouse still turned the
  view with the cursor hitting the screen edges, and a click back into the game fired the gun. A second Esc opened the
  pause menu, and Resume locked the mouse again.
- **Cause:** while the pointer is locked, the browser keeps the first Esc for itself: it exits pointer lock and the
  page gets no key event. The game paused only on its `pause` action (Esc, Start), so it never saw a pause, and the
  player's controls stayed on with the mouse no longer captured.
- **Fix:** pause on the loss of capture: when capture is expected and the real mouse mode is no longer captured (or the
  window loses focus), open the pause menu in that frame; no look or fire while unlocked; Resume re-locks from its
  click. A browser test releases the lock and checks the pause screen. In Deadnight #481 the grip polls
  `Input.mouse_mode` each frame (the web reports the real lock); unit tests need a stand-in platform, since headless
  Godot reads the mode back as visible; the browser test calls `document.exitPointerLock()`, as Playwright cannot
  press the browser's Esc.
- **General:** any web game with mouse look meets this on its first playable night. Design the pause around the lock,
  not around a key the browser may keep.
- **Docs:** [Web export](../godot/web-export.md#pointer-lock-and-esc-design-it-in-from-the-first-playable-night),
  [What the maintainer caught](../research/maintainer-corrections.md).
