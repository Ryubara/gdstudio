# Outline through walls (stencil) in Compatibility

A silhouette edge that shows through walls, and only where the body is hidden, for any skinned or static mesh, on
the Compatibility renderer and in the web build (WebGL2). Learned on Deadnight's issues #523 and #617; the shader,
the component and the numbers are in that game's `game/gameplay/outline/` and `docs/research/outline.md`.

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

## Only where it is hidden {#only-where-it-is-hidden}

The mask has no depth test (a hidden part must count as the body), so the stencil alone also outlines a body in the
open. Draw the line only on hidden pixels with the **depth texture**, which works in Compatibility and in the web
build (WebGL2): `uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;` in the line
shader, and `discard` the pixels where the body is not behind the scene.

- Reconstruct the distance with `INV_PROJECTION_MATRIX * vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0)`, then
  `-view.z / view.w`. Compatibility's depth holds 0 to 1, so the clip depth is `depth * 2.0 - 1.0`.
- A copy shifted on the screen shows a body point that really lies `shift` away. Pass that point's view depth from the
  vertex function (`varying`), and test the scene at the point's own pixel (`SCREEN_UV - shift`, y flipped: clip y is
  up, uv y is down) **and** at the copy's pixel. The first alone leaves the line a line's width past an occluder's
  edge; the second alone draws it on the ground beside a foot.
- `cull_back` in the line passes: with `cull_disabled` the copy's back faces are behind the body's own front faces
  and count as hidden by them, so a zombie in the open grew a line under its soles.
- Require **five depth samples** (the pixel and four a pixel and a half round it) to all be nearer than the body
  point, and make the margin `0.12 m + 0.01 m per metre + 4 times the depth step across the surface`: feet sink a few
  centimetres into the ground, which is metres along the view at a far zombie's grazing angle. A flat per-metre
  margin either left specks under the feet (0.04) or stopped a car 1.5 m in front of a zombie from hiding it (0.12).
- `VIEWPORT_SIZE` can be read in `vertex` and `fragment` only, not in a helper function: pass it in.
- The glow (a second, wider ring) was dropped: it read as an aura. The line alone is the look.
- Prove it with pixels: render the open, half-behind-a-counter and behind-a-wall cases in a `SubViewport` and count
  the line's colour above and below the occluder's edge and by distance from the silhouette
  (Deadnight `tests/outline/test_outline_pixels.gd`; it needs a real renderer, a headless dummy cannot read pixels).
  Also capture the half case from the player's camera: a zombie half behind a car.
  A windowed run is minimized and draws nothing by itself: `RenderingServer.force_draw(false)` (a few times), never
  `await RenderingServer.frame_post_draw`, which hangs. See the
  [lesson](../../lessons/2026-11-02-a-pixel-test-hung-or-read-a-blank-picture-in-a-minimized-window.md).

- **Approach:** Turn each adjective of an ask into a capture that can fail (the target in the open, half hidden, fully
  hidden), ask about any effect the ask did not name, and draw an effect meant for hidden parts from the depth per
  pixel. **Watch out for:** two words of the ask were read literally: the glow became a faint halo pass, the outline
  through walls was drawn everywhere, captures in the open were judged readable, never as having no outline, and a
  half-hidden zombie was never shot. **Seen:** Deadnight #617, 2026-11-02 (fix: the outline reads the depth per pixel,
  as above).

## Pitfalls

- Make the outline's node and materials with the body, not at the first mark: a pooled-crowd game counts nodes made
  after the warm-up (Deadnight's kill-allocations test caught a node made at a zombie's first mark in the last
  round); run the suites that watch allocations, not only the outline's own, when a change touches the view pool.
- A mesh outlined with no stencil-aware ordering shows one body's outline over another's: use `render_priority`.
- Thickness in raw pixels looks thinner on a big screen: scale by `VIEWPORT_SIZE.y / 1080`.
- Cost is passes, and the depth read: with 17 passes (mask, 8 line, 8 glow) three outlined zombies added 51 draw calls
  (85 to 136) and no measurable frame time in Chrome with a GPU (2.66 to 2.62 ms), but +20 % on SwiftShader (199 to
  239 ms). The depth-texture version has 9 passes (+12 ms on 243 for 3 zombies on SwiftShader) but **a fixed 3 to 4 ms
  on the GPU while any mesh wears it** (2.67 to 6.51 ms; a shader that only reads the depth costs the same): the
  engine copies the depth buffer for the shader (probably the multisample resolve: the project has 2x MSAA; not
  isolated). Nothing is paid while
  the overlay is off. Measure both, and with the depth read on and off. Leave the overlay off (null) when nothing is
  outlined: then it costs nothing. See
  [the web build on a phone](web-phone-frames.md#measuring-a-phone-without-one).
