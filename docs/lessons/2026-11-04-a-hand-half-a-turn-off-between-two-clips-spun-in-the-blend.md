---
areas: [blender, godot]
---
# A hand half a turn off between two clips spun in their blend

2026-11-04

- **Saw:** after a rebuild of the sprint carries with a shorter forearm, `test_sprint_start_blend.gd` failed on the
  puppet: `Index1.L turned 76.7 degrees in tick 19 of the start (most 20)`; the clips' own build reported the carries'
  left wrist 175-180 degrees off its turn in the gun hold (main's had been 178).
- **Cause:** the animation tree blends two rotations along the shorter arc; near half a turn apart the shorter arc
  swaps sides as either clip moves, so the blend jumps. Main's 178 was on the lucky side; a 1-degree change tipped it.
  Making the IK's own slerp keep its arc (`slerpni` and the frame before) did not help: the flip was in the tree.
- **Fix:** the carry rolls its forearm about its own axis, one roll for the whole loop (45-60 degrees), the least that
  keeps the wrist within 150 degrees of the hold's in every frame (`CARRY_WRIST_MAX`); the hand's world turn and the
  wrist's place do not change. Any clip the tree blends against another keeps each bone's local turn well under half a
  turn from the other's: print it at build time.
- **Docs:** [Animation tree](../engines/godot/animation-tree.md).
