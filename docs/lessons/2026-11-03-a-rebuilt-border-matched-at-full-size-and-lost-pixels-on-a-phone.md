---
areas: [godot-ui, tests]
---
# A rebuilt border matched pixel for pixel at full size and lost its pixels on a phone

2026-11-03

- **Saw:** the HUD's cards were rebuilt as one triangle array (Deadnight #948). The before and after captures at 1920 x
  1080 were identical (0 differing pixels outside the 3D portraits); at 844 x 390, 174 pixels of card borders (whole
  runs along the top and bottom edges) were missing.
- **Cause:** the polyline's quads were offset at a corner along the mean of the two normals, which is shorter than the
  true mitre. At 1:1 a 2-unit border covers every pixel centre it passes either way; at 0.36 scale it is 0.7 pixel
  thick and a centre is covered or not by a few tenths of a unit, so the short corner left the end of each edge empty.
- **Fix:** mitre the corner (the offset divided by `dot(mean, normal)`). A spike that drew the engine's `draw_polyline`
  and the rebuilt one at 844 x 390 found it in two runs; after it the four captures (desktop and phone, fight and round
  start) differ by at most one level of 255.
- **Check next time:** a rebuilt shape is compared at the smallest scale the game runs at, not only at 1:1: capture
  both builds at the phone's window, mask what is not deterministic (3D portraits), and read the differing pixels.
- **Docs:** [Canvas draw calls](../godot/canvas-draw-calls.md#draw-many-shapes-as-one-command).
