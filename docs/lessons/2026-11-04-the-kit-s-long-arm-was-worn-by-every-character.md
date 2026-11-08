---
areas: [blender]
---
# The kit's long arm was worn by every character, and read longest on her

2026-11-04

- **Saw:** the maintainer pointed out that the female characters' arms looked too long, and that the male ones
  needed checking too (Deadnight #978).
- **Cause:** nothing stretched them and hers equalled his: every look of both characters wore the kit Soldier's arm
  unchanged, 0.547 of the height (span 1.23 times it), the forearm longer than the upper arm, the fingertips hanging
  below the knee. Her body was his with only the trunk warped (a narrower waist, his shoulders, arms and hands), and
  her bare-armed presets showed a thin skin arm from the sleeve to the knee. The style bible listed head, hips and span
  but never the arm against the height, and the guns were then held at that arm's full reach.
- **Fix:** the forearm shortened at rest on the imported kit body, before any clip is authored (skeleton, skin and
  every reach-solved clip get the one arm): 0.507 of the height, the forearm 0.91 of the upper arm, the hand kept for
  the grips. A two-handed hold bends the elbows further out (the right forearm had folded into the jacket) and slides
  the gun back along its barrel when the fore-end is out of the left arm's reach; more stance reached too, but turned
  the armband deeper into the chest. A test pins each look's arm over its height. Before shortening, try it at run
  time: set the skeleton rest of the bones below the forearm in a probe and read the IK's reach for every hold.
- **Docs:** [Character variants: proportions](../blender/variants.md#proportions-measure-the-arm).
