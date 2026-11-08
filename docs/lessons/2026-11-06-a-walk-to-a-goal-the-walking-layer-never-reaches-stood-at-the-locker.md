---
areas: [tests, gameplay]
---
# A walk test sent a body to a goal its layer never reaches, and it stood at a locker that was already in the mesh

2026-11-06

- **Saw:** Deadnight #1340 (the second map's four lockers put into the baker's group, the meshes baked again): the
  suite that walked a body across each locker still failed on the new mesh, 2.03 s against `LockerStart`, and passed
  for the other three on the old mesh, where only one stood. A probe of the saved mesh gave a path round the locker.
- **Cause:** three things in the test, none in the mesh. (1) `HumanWalker` steers to the first path point more than a
  metre away and, when the path ends short of the goal, to the goal itself: given a goal outside the building (the
  breach was boarded, so the person's path stopped at the wall) it walked into the wall and the locker's corner. (2)
  The night's map is not the saved mesh: it is cut into a walking region and a region of the dead's gaps
  (`NavmeshSplit`), so a probe on the saved mesh found a ring upstairs that the walking layer does not have; the
  pocket round `LockerUpstairsA` is a piece only the dead walk. (3) Goals taken on a ring round the prop and snapped
  with `map_get_closest_point`, which has no layers, may be on the other layer.
- **Fix:** keep a walk only when the person's path reaches its goal (ends within a metre, `BotPath` ray clear), keep the
  pairs whose straight line crosses the prop, count the walks each prop got, and say in the suite which prop has none
  (its crossings are the dead's) and check that one by the dead's own path (`NavLayers.DEAD`): the least distance of
  the path from the box's footprint, 0.10 and 0.19 m on the old mesh (two of the four), at least 0.3 m on the new.
- **Check for next time:** a stall test asserts first that the path it walks reaches its goal; a probe of a mesh the
  night uses goes through the night's map (`night.world.map()`), not a map made from the saved resource; and a test
  that "fails on main" is run on main with every prop, because a walk that passes there tests nothing (here the
  roam-spot pairs: 0 stops before and after).
- **Docs:** `docs/engines/godot/navigation-in-tests.md` ("A walk to a goal the layer never reaches").
