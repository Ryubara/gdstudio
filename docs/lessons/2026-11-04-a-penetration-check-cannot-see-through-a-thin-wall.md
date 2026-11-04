---
areas: [blender, tests]
---
# A penetration check cannot see through a thin wall

2026-11-04

- **Saw:** every clip passed for a skirt whose wall a thigh went through: the check asks whether a limb's vertex is
  inside another surface, and a thin wall has no inside. The first replacement, a ray from the hips to the vertex,
  reported 0.6 m on a 0.4 m thigh. The sheet at full-body size hid the fault; at the hips the grey legs showed.
- **Cause:** a thin wall folds near the hips, so that ray crosses it far from the limb, and distance along it is not
  depth.
- **Fix:** test the wall against the limb: sample places on the wall (corners, edge and face middles), and count one
  as inside when nothing lies between it and the limb's own bone line, with the depth being the way on out. Past a
  bone's end a tube is open, so those places are left out. A number larger than the limb is a broken metric: sanity-check
  a new metric against a size you know before tuning art to it.
- **Docs:** [Character variants, clothes that stand off the body](../blender/variants.md).
