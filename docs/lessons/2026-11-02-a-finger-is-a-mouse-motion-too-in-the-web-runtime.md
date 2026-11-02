# A finger turned the view twice on a phone: the web runtime reads touch pointer moves as the mouse

2026-11-02

- **Saw:** on a phone (Deadnight #470) the move stick turned the camera and a look drag flew round; the desktop
  GdUnit touch tests and the touch design all passed.
- **Cause:** Godot's web runtime listens for `pointermove` on the window and makes a mouse motion of it (`movementX`
  times `canvas.width / rect.width`, so device pixels). A touch pointer fires `pointermove` as well, so each finger
  also moved the mouse, three times too far at a pixel ratio of 3. Synthetic `InputEventScreenDrag` events in the
  desktop runner never take that path; `Input.emulate_mouse_from_touch = false` does not touch it. The layer's own
  look was also twice too fast (3.2 rad per screen height).
- **Fix:** in the export's `html/head_include`, a capture-phase `window` `pointermove` listener that calls
  `stopImmediatePropagation()` for `pointerType === 'touch'`; in the game, ignore a mouse motion that is not the touch
  layer's own (tagged with its own `device`) while a finger was the last input (Deadnight #480). Proved in a
  phone-emulated Chrome with `Input.dispatchTouchEvent`, reading the yaw off the web probe: each finger alone does
  only its own job, and a drag of N px turns by the designed angle.
- **Docs:** [Web export](../godot/web-export.md); Deadnight `docs/research/web-export.md`,
  `docs/design/touch-controls.md`.
