---
areas: [input, camera, web]
---
# A steady touch drag turned the view in jumps: the look was applied per sample, not per frame

2026-11-02

- **Saw:** on a phone a slow drag of the look finger turned the camera in jerks: "playable and better than before,
  but not smooth" (Deadnight #598, after the fixes of #470 and #497). No test saw it: they check how far a drag
  turns and that no frame turns too far, never how evenly.
- **Cause:** the touch layer turned the view the moment a finger sample arrived, in that frame, and a touch screen
  samples at 60 or 120 Hz while the page draws at another rate, never an even number of samples per frame. Measured in
  the web build (Chrome, 779 x 360 phone, a finger moving at a steady 20 px/s): a page at 175 fps turned the view in
  1 frame of 3 and held it still in the other 2 (variation of the per-frame turn 1.4, biggest step 3 times the mean); a
  page at about 30 fps with a 120 Hz finger turned it in alternate frames (variation 1.0). No frame turned back. Nothing
  was wrong with the drag's size, only with when it was applied.
- **Fix:** the layer lets the look wait and turns the view a share of it each frame, in proportion to the frame's
  length (`LookSmoother`, about 40 ms behind the finger): variation 0.15 to 0.21 and 0 still frames at 175 fps, 0.31
  to 0.41 at 30 fps. Measure it with per-frame yaw rows read in the browser (`tools/web_smoke/touch_look_smooth.py` in
  Deadnight), with the page's CPU slowed to phone speed (`Emulation.setCPUThrottlingRate`), and keep a test that drives
  a steady drag through the real input path and counts still frames.
- **General:** a control that arrives at its own rate (a finger, a gamepad poll, a network update) and drives something
  drawn at another rate is smoothed at the frame, with the rate it was sent at kept in the numbers; test the evenness
  of the output per frame, not only its total.
- **Docs:** Deadnight `docs/research/touch-look-smoothness.md`, `docs/design/touch-controls.md`.
