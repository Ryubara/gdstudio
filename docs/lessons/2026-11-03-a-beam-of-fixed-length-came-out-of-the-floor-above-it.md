---
areas: [godot, gameplay]
---
# A fixed-length beam of light rose through the floor and the roof over it

2026-11-03

- **Saw:** the maintainer, playing round 12 (Deadnight #911): "The mystery box's light that shoots up in the sky to
  indicate where it is bleeding through objects e.g. it ideally should continuously go up until it collides with a floor
  or object." The prize crane's beam stood out of the concession's roof and showed on the second map's upper floor.
- **Cause:** the beam was a 36 m additive cone (`BEAM_HEIGHT`) that nothing measured against what is above the crane.
  The depth test (the only wall a glow has in Compatibility) hides the part of the cone behind a surface from the
  camera, not the part beyond it on the camera's side; every capture of the crane was taken from the floor in front
  of it or from across the lot, never from the floor above it.
- **Fix:** one ray up from the marquee when the crane is placed or moves (`PrizeCrane.beam_length_over`, world layer);
  the same cone is shortened to the first solid, with a fade over its last metre (0.39 m under the second map's
  ceiling, the full 36 m in the open). A test casts the ray from every crane spot of both maps and checks nothing
  solid stands inside the beam; the capture stands on the first solid over each spot. For any column, shaft or
  beam of light: set its length from what is above its source and shoot it from above.
- **Docs:** [Compatibility lighting](../godot/compat-lighting.md#a-column-of-light-has-a-length-from-what-is-above-it).
