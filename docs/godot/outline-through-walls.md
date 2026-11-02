# Outline through walls (stencil) in Compatibility

A glowing silhouette edge that shows through walls, for any skinned or static mesh, on the Compatibility renderer
and in the web build (WebGL2). Learned on Deadnight's issue #523; the shader, the component and the numbers are in
that game's `game/gameplay/outline/` and `docs/research/outline.md`.

## What works

- **`stencil_mode` in a spatial shader works in Compatibility, on desktop and in the web export** (Godot 4.7.2,
  checked in Deadnight's night on desktop OpenGL, in Chrome with a GPU and in Chromium on SwiftShader).
  The docs call it experimental and say it is read only in the transparent pass: a pass with `blend_mix` and
  `ALPHA = 0` still writes the stencil, so a mask that draws nothing is possible.
- **The recipe:** one mesh `material_overlay` chain (`next_pass`):
    1. mask: `render_mode unshaded, depth_test_disabled, cull_disabled, blend_mix; stencil_mode write, compare_always, 1;`
       with `ALPHA = 0`;
    2. N copies of one shader that move the clip-space position by a few pixels along N screen directions
       (`clip.xy += dir * px * 2.0 / VIEWPORT_SIZE * clip.w`), with `stencil_mode read, write, compare_not_equal, 1;`
       (draw outside the mask, write as you go so a pixel is coloured once).
  Set `render_priority` on each material (mask lowest): the passes of different meshes are sorted together in the
  transparent list, and an unordered mask would let one body's line cover another's.
- **Why copies and not an inverted hull:** a hull pushed along normals splits at the hard edges of a low-poly mesh
  and its width changes with distance. Eight copies shifted in screen space are a dilation: constant pixel width, no
  cracks. 8 directions cover a band of `cos(PI / 8)` = 0.92 of the radius between two copies; divide the asked width
  by it. The vertex function sees the skinned pose, so skinned meshes work with no extra step.
- **One shared set of materials** for every outlined mesh: a change of colour or width is one set of uniform writes.
  All copies share one shader, so the whole thing is two GL programs (mask and line), built on first use: draw an
  outlined sample once in the night's warm-up.

## Pitfalls

- A mesh outlined with no stencil-aware ordering shows one body's outline over another's: use `render_priority`.
- Thickness in raw pixels looks thinner on a big screen: scale by `VIEWPORT_SIZE.y / 1080`.
- Cost is passes: with 17 passes (mask, 8 line, 8 glow) three outlined zombies added 51 draw calls (85 to 136) and no
  measurable frame time in Chrome with a GPU (2.66 to 2.62 ms), but +20 % on SwiftShader (199 to 239 ms, 8 outlined:
  293 ms). Measure both; `glow = 0` leaves out half the passes. Leave the overlay off (null) when nothing is
  outlined: then it costs nothing. See the
  [lesson](../lessons/2026-11-02-a-render-cost-showed-nothing-on-a-gpu-and-20-percent-on-software-gl.md).
