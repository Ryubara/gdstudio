---
areas: [godot, tests, general]
---
# A profile's "what is left" was written down as the crowd's engine cost

2026-11-04

- **Saw:** the sweep of #906 split a 20 ms frame into labelled script (12 ms) and "the engine's own: skinning 135
  skeletons, drawing, physics server, audio mix: about 8 ms", and filed it as the crowd's cost (#949). Ablating the same
  night (dead hidden; animation stopped; both at the ceiling of 99, two runs each, interleaved) gave: drawing the dead
  1 to 1.5 ms (7 to 20 draw calls, 25 to 40 thousand triangles, 0.2 ms of render CPU: 64 of 92 dead stood past 40 m and
  most of the rest out of view), animation and skinning 1 to 2.4 ms (9.4 tree advances a frame, about 41 microseconds of
  CPU each). Most of the remaining "8 ms" was the lot, the HUD, the physics server and the frame's waits.
- **Cause:** a remainder is not a measurement. It carried every cost nobody had labelled and the name of the biggest
  thing in its sentence. The frame-time noise of a shared machine (the same arm ran 17 and 29 ms) hid that the dead's
  part was a third of it.
- **Fix:** ablate (hide the thing, stop the thing, count what is advanced and drawn by distance and view) in the real
  night, interleaved arms, three or more pairs, and report the deterministic counts (advances, draws, triangles) beside
  the times; cut the part that was measured. A census line a second (views by distance band and throttle tier,
  advances a frame, the viewport's CPU and GPU render time) found in a minute what a frame time could not.
- **Docs:** [Crowds](../engines/godot/crowds.md#what-a-crowd-costs-at-the-ceiling-in-the-real-night) and
  [Performance review](../engines/godot/performance-review.md).
