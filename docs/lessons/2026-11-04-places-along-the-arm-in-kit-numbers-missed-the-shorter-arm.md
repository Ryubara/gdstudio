---
areas: [blender]
---
# Places along the arm written in the kit's numbers missed the shorter arm

2026-11-04

- **Saw:** with the Soldier's forearm shortened, the bare-armed tops came out with bracelets at the wrists and
  `test_soldier_watertight.gd` saw through both wrists of 24 top and armwear combinations.
- **Cause:** the parts build picks the cuff faces (`|x| > 0.8`), the bare-skin push's taper (0.74-0.83) and the wrist
  openings it bridges (0.74-0.95) by their place along the arm at rest, in the kit's numbers; the wrist had moved 7 cm
  in, so cuff faces fell under 0.8 and kept their colour and the push reached the seam.
- **Fix:** the places stay in the kit's numbers and are read through one map of the change
  (`soldier_arms.along(x)`: the upper arm's unchanged, the forearm's scaled from the elbow, the hand's moved with the
  wrist). When a rest pose changes, grep the build for constants that name a place on what moved.
- **Docs:** [Character variants: proportions](../blender/variants.md#proportions-measure-the-arm).
