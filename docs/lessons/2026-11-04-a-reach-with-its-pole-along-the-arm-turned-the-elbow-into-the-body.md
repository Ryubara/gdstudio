---
areas: [blender, godot, tests]
---
# A reach with its pole along the arm turned the elbow into the body

2026-11-04

- **Saw:** Deadnight's reload put the left hand 94-125 mm into the hip and "the right hand 74-101 mm into the trunk"
  (#987), on every gun, on both looks.
- **Cause:** four things under one number. The check lumped the body and the other arm: split by target, the right hand
  was never in the trunk, it was in the left hand and forearm. The hand went in a straight line from a gun out on the
  right to a belt on the left, through the belly. The belt point sat inside the hips. The two-bone IK's pole
  (`side + down`) lay nearly along an arm hanging to the belt, so its part across the arm was small, flipped between
  ticks and turned the elbow in; the hand kept the wrist bend of the fore-end grip, fingers into the thigh.
- **Fix:** split the check by target before tuning anything. The goal is moved out of an ellipse round the hips, the
  pouch goes forward and out where the arm still reaches, the pole blends to out and back as the arm hangs
  (`-(goal - shoulder).y`), the hand hangs in line with the forearm. Two big chibi fists cannot share a magazine:
  the left hand takes the far end of the magazine or drum, not its middle. A coordinate search on the keys cleared
  every gun but walked the hands off their parts (a drum held from the barrel) and merged two points of a cycle: search
  near the part and look at every result. Sample every tick at the end; every third missed the crossings of a transit.
- **Docs:** [Clips that keep the arms out](../tools/blender/variants.md#clips-that-keep-the-arms-out).
