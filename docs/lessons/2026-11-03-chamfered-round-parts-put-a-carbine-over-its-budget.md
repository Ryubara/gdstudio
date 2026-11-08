---
areas: [blender]
---
# Chamfered round parts put a carbine over its budget

2026-11-03

- **Saw:** the M4A1's first build was 1,576 triangles against a 1,500 cap and a 1,200 target (Deadnight #795).
- **Cause:** the chamfer modifier on a cylinder adds a ring of quads at each end: a 12-sided cylinder is 44 triangles
  bare and 92 chamfered. Five 12-sided ribs on the hand guard were 220 more; small blocks with a chamfer cost 44
  instead of 12.
- **Fix:** chamfer only the big round parts that face the camera (the hand guard), leave collars, rings and the flash
  hider bare, three ribs instead of five, no chamfer on small blocks: 1,236. Count with the build's `WEAPON` line on
  the first build, and spend chamfers on the signature parts.
- **Docs:** [Weapons, budgets](../tools/blender/weapons.md#budgets).
