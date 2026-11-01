# The same rotation raised one arm and folded the other

2026-11-01

- **Saw:** turning `UpperArm.L` and `UpperArm.R` both +X lifted one hand overhead and buried the other in the chest; a
  probe sheet (one axis per frame) was misread twice.
- **Cause:** the Quaternius rig's arm bones are rolled mirrored: X swings the hand up and in on both sides, Z lifts it
  up and out on the left and -Z on the right. A rendered probe hides depth.
- **Fix:** measure instead of looking: turn each axis 50 degrees and print where the hand bone's tail moved (out,
  forward, up). Straight overhead is X and +/-Z together.
- **Docs:** [Rig sharing](../blender/rig-sharing.md#posing-by-hand-position).
