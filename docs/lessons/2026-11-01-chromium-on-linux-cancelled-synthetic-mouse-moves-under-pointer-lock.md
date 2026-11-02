---
areas: [input, ci]
---
# Chromium on Linux cancelled synthetic mouse moves under pointer lock

2026-11-01

- **Saw:** the web smoke's mouse-look check passed on Windows and failed in CI (headless Chromium on the Ubuntu
  runner): the view never turned.
- **Cause:** under pointer lock, headless Chromium on Linux delivers each synthetic `page.mouse.move` as a motion and
  then the opposite motion (+15 px, -15 px), so they cancel. Windows does not do it. Pointer lock itself works.
- **Fix:** when the real moves did not turn the view, the smoke dispatches `PointerEvent('pointermove', {movementX})`
  on the canvas, which Godot's web runtime listens for (Deadnight #299, #390).
- **Docs:** [Web export](../godot/web-export.md).
