---
areas: [godot-ui, web]
---
# A film scratch was read as a seam in the interface

2026-11-05

- **Saw:** a faint vertical line (+10 levels, 77% of the rows) through every plate of Settings on a phone page, at one
  screen x, stopping at each plate's border. The first guess was a seam in something sampled in screen space.
- **Cause:** a deliberate effect, the film overlay's scratch: a 1.6 px line at a new random x three times a second, over
  the whole router layer. A single capture cannot tell it from the panel's own hairline border (both are ridges in a
  column measure), and a layout seam would not move; this one was at a different column in each shot that showed it.
- **Fix:** measure a series, not a shot: 40 screenshots of a screen that holds still, subtract their per-pixel median,
  then read each column against columns x-3 and x+3 (the smaller of the two, so a step edge reads 0). The line showed
  in 8 of 40 shots on main, in 0 of 40 with the scratch removed, and the median screens differ by 0.4 levels.
  Check for next time: a defect that is at the same place in one capture and elsewhere in the next is in a time-driven
  layer (shader `TIME`, an overlay), not in a control's layout; grep the shaders over the screen first.
- **Docs:** the game's `docs/research/web-smoke-probes.md` (Deadnight #1249).
