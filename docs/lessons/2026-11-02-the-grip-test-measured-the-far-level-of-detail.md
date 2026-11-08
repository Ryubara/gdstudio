---
areas: [blender, tests]
---
# The grip test measured the far level of detail too

2026-11-02

- **Saw:** after sparing the hands in the short-sleeved tops (Deadnight #678), only the tank top failed one contact:
  the right palm 10.4 mm into the rifle, with palm vertices and weights identical to the jacket's. I first guessed a
  test artefact twice (an older soldier's `skeleton_updated` firing the measurement; the per-position dedup hiding a
  cuff vertex): each change left the number exactly as it was.
- **Cause:** `HandContact` measured every *visible* skinned mesh, and the far level of detail (#139) is visible; it is
  hidden by a visibility range, not by `visible`. The tank's decimated far hand put a palm vertex in the rifle. And
  the rifle's grip had been solved through the same measure: its right middle fingertip touched only on the far mesh
  (6.9 mm off on the near one).
- **Fix:** skip meshes with `visibility_range_begin > 0` in `HandContact` (Deadnight `tests/art/hand_contact.gd`) and
  re-solve the rifle's grip (`tests/art/solve_grips.gd -- --only lever_rifle`). When a number does not move at all
  under a change of the suspected cause, drop the guess: list every input the measure reads (here, which meshes)
  before changing the test.
- **Docs:** [Character variants](../tools/blender/variants.md#a-second-body-on-the-same-parts).
