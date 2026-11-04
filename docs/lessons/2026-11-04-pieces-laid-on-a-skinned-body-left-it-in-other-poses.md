---
areas: [blender]
---
# Pieces laid on a skinned body fitted at rest and left it in other poses

2026-11-04

- **Saw:** Deadnight's overalls had the shirt through the straps and bib once the arms hung; shoulder braids floated off
  the sleeve; a fix for those put stubs on the collar, seen only in the run pose.
- **Cause:** four separate things. Weights picked from faces "led by a trunk bone" skipped the chest's edges and the
  shoulders, which are weighted to the arms and move when they hang. A piece on one bone ignores that the kit's shoulder
  faces close up as the arm drops. A ray or a nearest-face search from outside finds whatever is first: on this body the
  tall collar's flare overhangs the shoulder, so both the seat and the weights came from the collar. And the first
  reading of the stubs (a skinning fault) was wrong: the piece was sitting on the collar at rest.
- **Fix:** choose source faces by place, not by bone, and interpolate over the face (`mathutils.interpolate.poly_3d_calc`);
  give a small rigid piece the weights at its middle; rest a sheet's point on the highest surface under its whole
  footprint; start a seating ray under anything that overhangs. Print where a piece is at rest before blaming the skin,
  and look at each piece in at least two poses that move the arms.
- **Docs:** [Pieces laid on a body](../blender/variants.md#pieces-laid-on-a-body).
