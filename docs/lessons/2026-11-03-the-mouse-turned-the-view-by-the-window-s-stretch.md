---
areas: [input, camera, godot, tests, web]
---
# The mouse turned the view further in a small window, because it read the stretched motion

2026-11-03

- **Saw:** the agent measuring the look under lag (Deadnight #905): a 1280 pixel window turned the view 1.5 times as
  far per mouse pixel as a 1920 one, a 2560 one 0.75 times, a 64 pixel headless window 30 times. No test had a window
  size in it, so all passed.
- **Cause:** the player turned by `InputEventMouseMotion.relative`, which is in the viewport's units: with the
  `canvas_items` stretch it is the screen motion times `1920 / window width`. `screen_relative` is the unscaled motion.
- **Fix:** turn by `screen_relative` (`MouseMotion.pixels`). Two things the switch needed: the touch layer's synthetic
  motion and every test's hand-made one set `screen_relative` too (it is zero otherwise), and on the web the runtime
  reports device pixels, so `screen_relative` is `devicePixelRatio` times the browser's `movementX` (the stretch used to
  cancel the ratio; a ratio-2 screen turned twice as far in the first probe) and the look divides it out. The test
  resizes the root window across sizes and stretch modes and fails on the old line; a browser probe resizes the page at
  two pixel ratios.
- **Docs:** [Mouse look at any frame rate](../godot/mouse-look.md); Deadnight `docs/research/mouse-look-window-size.md`.
  Check: a look or aim that reads a mouse motion reads `screen_relative`, and a test of it runs at more than one window
  size and stretch mode.
