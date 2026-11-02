---
areas: [gameplay, godot]
---
# A goal in the middle of a door slab snapped into the shut room behind it

2026-11-02

- **Saw:** with only the concession open, a bot's path to the booth door's use point (the slab's middle, 0, 1.3, 22.2)
  ended 6.75 m short, beside the booth's wall, and the bots never bought the door. A person standing 1 m in front of the
  door reached it at once; the other doors' middles were only 1.2 m off the mesh, so only one door stalled.
- **Cause:** the baked mesh is cut back 0.5 m from a wall on both sides, so a slab in a wall lies between two cut edges.
  `map_get_closest_point` (and the end of `map_get_path`) took the edge on the shut side (the booth's floor, 0.55 m away,
  a different island) instead of the open side (0.9 m): the path then ended at the nearest point of the reachable part,
  6.75 m away. The mesh was right (z 21 in front of the door is reachable); the goal was the problem.
- **Fix:** a goal that is to be walked to is a point on the open side, never a point in a wall or a slab. The greybox
  writes a `Stand*` marker 1.5 m in front of each door slab (`NightWorld.door_stands`), and a test buys every door in the
  shop's order from its stands (path ends within 2.5 m, a body there is offered the door). The use point stays where the
  hand reaches from.
- **Docs:** [A goal in a wall](../godot/navigation-in-tests.md#a-goal-in-a-wall).
