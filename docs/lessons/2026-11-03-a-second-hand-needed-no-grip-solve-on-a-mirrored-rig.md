---
areas: [blender, gameplay]
---
# A second hand needed no grip solve: the rig is an exact mirror

2026-11-03

- **Saw:** the dual pistols (Deadnight #789) asked for a weapon in each hand, and the first plan was to run the grip
  solver and author the left arm's clips again for the left hand.
- **Cause:** nothing measured whether the left side was a different problem. One probe printing each left bone's rest
  rotation against its right one's showed an exact mirror (`y` and `z` negated, to 1e-5), and the Blender build's
  mirror check read 0.0 m.
- **Fix:** the left gun is the right one mirrored (a second node on `Index1.L`), the left fingers are the right grip's
  with the sign flip, the left arm reaches the mirror of the right arm's pose, and the six clips are the Pistol clips with
  the right arm's rotations copied to the left flipped. The first test run passed with both hands within 2 mm; swapping
  the flip for a plain copy failed it by 35 mm, so the test does measure the mirror.
- **Check next time:** before solving anything per side, compare the two sides' rest poses; and make the test fail once
  with the flip removed.
- **Docs:** [A weapon in each hand](../blender/weapons.md#a-weapon-in-each-hand).
