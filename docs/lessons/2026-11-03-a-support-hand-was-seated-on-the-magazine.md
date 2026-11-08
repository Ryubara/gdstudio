---
areas: [blender, tests]
---
# A support hand was seated on the magazine, not the hand guard

2026-11-03

- **Saw:** the MP5's left hand floated 17 cm under its hand guard, fingers open, the palm 22 mm off the gun in the
  capture, while the solver's table said the palm was 2.3 mm in and the grip and hold tests passed (Deadnight #795).
  I first blamed the solver's slide along the fingers (`shift` 0.020); it is baked into the right hand's hold and never
  moves the left hand.
- **Cause:** the solver seats the hand by bisecting along the palm's normal for where the palm meets the gun, which
  assumes one surface in that line; the curved magazine in front of the well was a second one, and the search settled
  on it. The per-pose test walks catalogue weapons only, so a model that is not a weapon yet has no per-pose check.
- **Fix:** the `Support` socket 2 cm further forward (x -0.30, the hand's rear clear of the magazine); after a solve,
  compare the solved `left_hand` origin with the support point (12-14 cm under it on a gun that works, 20 cm on this
  one) and read the model sheet's contact lines in the game pose, which print where each miss is in model space.
- **Docs:** [Weapons, hands on the weapon](../tools/blender/weapons.md#hands-on-the-weapon).
