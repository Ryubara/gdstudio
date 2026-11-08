---
areas: [gameplay, input]
---
# A kit Run's planted-foot speed jumped with small changes

2026-11-01

- **Saw:** the same zombie Run read 4.4 m/s in Godot and 5.7 in Blender, and a 1.2 times longer stride read 9.7, not
  6.9.
- **Cause:** the kit's planted foot barely moves at touchdown and then sweeps fast, so the median of the planted
  samples falls between two groups and flips with sampling phase or a small change of the feet.
- **Fix:** author the contact as one steady sweep that touches down and lifts off at ground speed; set the game's
  blend point from the Godot reading.
- **Docs:** [Gaits from kit clips](../tools/blender/gaits.md).
