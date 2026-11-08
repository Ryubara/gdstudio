---
areas: [gameplay, tests]
---
# Bots walked the dead's mesh through the boards and stood at them

2026-11-04

- **Saw:** a bot sent back from the road stood at (12.0, 0, 33.45) with `Board1` of a fence breach 0.4 m in front, for
  minutes, with no dead near (Deadnight #995, found as a flaky `test_autopilot_machines.gd`: it passed when a 47 s wait
  happened to free the bot).
- **Cause:** the baked mesh is the dead's: the gap in a fence is their way in, and the boards across it are not in the
  bake. #903 put 16 such gaps around the lot, the road door joined the yard and the plaza to them, and the nearest way
  home from the road became a gap. Earlier fixes (#677) checked a *path* for what a body cannot walk through and marked
  the goal unreachable, which stops the bot standing but leaves it with no route; the autopilot asked the mesh itself and
  never checked at all. A test sent a bot to goals beyond the fence, never from the road to the far side of the lot.
- **Fix:** two regions in one map: the mesh without the polygons that cross a barricade's line (layer 1) and those
  polygons (layer 2); bots ask layer 1, the dead ask both (`NavLayers`, `NavmeshSplit`). A test walks a path over every
  barricade of the map for both kinds and puts a bot on each side of the lot's pockets with every door sold.
- **Docs:** [One navigation map for two kinds of walkers](../engines/godot/navigation-layers.md).
