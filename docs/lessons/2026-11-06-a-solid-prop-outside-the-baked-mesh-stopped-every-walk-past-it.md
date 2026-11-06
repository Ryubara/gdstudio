---
areas: [gameplay, godot]
---
# A solid prop outside the baked walking mesh stopped every body that walked past it

2026-11-06

- **Saw:** Deadnight #1334: a bot (and the `boards mid_e` errand) walking from the west of the lot to the east midway's
  stand walked into the west face of the booth's breaker post and stood there. Walking the stretch of every roam-spot
  path that passes a post, with a body, found 3 stops, all at that one post, and none at the other three.
- **Cause:** the baker (`NavmeshBaker.source_data`) reads CSG boxes only, and a breaker post is a `StaticBody3D`: solid
  to a body, absent from the mesh. A path hugs the mesh edge, which is 0.5 m off a wall, and the post sat 0.05 m off
  that wall, so the line through the corner ran through it. Bots and dead alike walk the one mesh.
- **Fix:** a solid prop that is not CSG says so with the group `navmesh_obstacle` (`NavmeshBaker.OBSTACLE_GROUP`; its
  box shapes are baked like a CSG box) and the saved meshes are baked again (`bake_lot_navmeshes.gd`); a test finds
  every body with only the world's layer on and fails on one outside the group. Show what a baked-in prop changes
  with a path check over the points the walk uses, on every saved set, before and after (here 0 pairs lost, 0 gained,
  +16 polygons a set). Boards and window frames stay out: baking them would shut the breach the dead come through.
- **Docs:** Deadnight `docs/research/zombies.md`, "A solid prop that is not CSG is not in the mesh either".
