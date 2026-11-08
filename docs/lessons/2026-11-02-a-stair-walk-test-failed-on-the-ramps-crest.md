---
areas: [godot, tests]
---
# A stair walk test failed on a few millimetres at the ramp's crest

2026-11-02

- **Saw:** a test that walked the player up a stair's hidden ramp and allowed no downward move of the drawn body
  while climbing failed on the sprint and the L stair's corner: one tick of 4-8 mm at the top of each slope, with no
  step-up and the body on the floor (Deadnight #634).
- **Cause:** the capsule's round foot rolls over the edge where a slope meets the flat and settles. That is the
  engine's slope behaviour, not a step: a step-up lifts the body by a whole riser (200 mm) and sets `stepped_up`.
- **Fix:** judge a stair walk on what a step does: no tick with `stepped_up`, none off the floor, and a dip bound of
  10 mm a tick; prove the measure with a control (the same flight with its treads as collision steps fifteen times).
- **Docs:** [Modular kits: stairs](../tools/blender/modular-kits.md#stairs-rails-and-blockers).
