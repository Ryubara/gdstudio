---
areas: [camera, tests]
---
# A muzzle flash lying in the muzzle's plane was hidden by the gun and hands

2026-11-02

- **Saw:** the maintainer said the flash was weaker than it seemed; it passed its frame and position tests and looked fine
  in a close-up capture.
- **Cause:** from the shoulder camera the flash was 6 % of the screen's height at most and 2 frames long, and the gun, hand
  and arm round the muzzle, nearer the camera than the plane the flash lay in, hid up to nine tenths of it. A close-up from
  the side shows none of that.
- **Fix:** measure the flash's own pixels from the real camera (draw the frame again without it and compare), draw the
  quads toward the camera (scaled by the same ratio), a bigger star in a flat glow disc, 3 frames and 60 ms at least, and
  floors in a probe and a test.
- **Docs:** [Measuring an effect on the screen](../engines/godot/measuring-effects-on-screen.md) (a kit page, drafted below).
