---
areas: [blender, gameplay]
---
# A body lifted by the simulation and folded by a clip left its zones and the bots' aim in the air

2026-11-04

- **Saw:** with a climb clip (#991) the head over a window's sill was drawn 0.9 m under the head zone: the zones were
  the standing set at the lifted origin, and the bots aimed 1.1 m over that origin, at nothing.
- **Cause:** a clip that moves the body a long way from its origin changes what a shot and an aim point mean, and
  neither looks at the clip: `ZombiePose` chose the set from the mode, and the aim was a number over the feet.
- **Fix:** a set of its own for the clip (twice the shapes: the body travels over a metre), chosen by the snapshot's
  bit, and the aim read from that set; bots, the autopilot and touch aim assist pass the bit. When a clip moves a body
  off its origin, grep for the hit sets and every aim offset in the same change.
- **Docs:** [Animation tree](../engines/godot/animation-tree.md#a-clip-driven-by-place).
