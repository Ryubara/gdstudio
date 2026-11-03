---
areas: [gameplay, godot, web]
---
# A through-walls outline was drawn on the visible parts too, and had a glow

2026-11-02

- **Saw:** the maintainer, on Deadnight's last-zombies outline (#580): "an orange haze around the thick outline" and
  the outline showing on parts of a zombie in plain sight. It should only show on the hidden parts, per pixel.
- **Cause:** two words of the ask read too literally. "A glowing outline" became a second ring of faint passes (a
  halo, `glow = 0.6`) that nobody had asked to keep once it was on screen. "Visible through walls" and the done line
  "no depth test" became "draw everywhere": the mask and the line passes both had `depth_test_disabled`, so no pass
  ever asked whether a pixel was hidden. The captures of a zombie in the open were judged "readable", never "has no
  outline", and a zombie half behind a car was never shot.
- **Fix:** no glow at all; each line pass reads the depth texture (`hint_depth_texture` works in Compatibility and
  the web build) and keeps a pixel only if the body's surface it stands for is behind what the scene drew, at its own
  pixel and where the copy lands. Three things took a capture each to find: cull back faces (the body's own back
  face counted as hidden by its front), test five samples (the ground beside a foot), and a margin that grows with the surface's
  slope (feet sink a few centimetres into the ground, metres along the view at a grazing angle).
  A pixel test renders the open, half-behind and behind-a-wall cases and fails on the old shader.
- **Docs:** [Outline through walls](../godot/outline-through-walls.md#only-where-it-is-hidden). Next time: for any
  effect described by a place (through walls, only where hidden), capture the case where it must NOT show, and a
  case half in and half out, before calling it done.
