# A new navigation region answers path queries only after a few map iterations

2026-11-01

- **Saw:** `map_get_path` returned `[]` and `map_get_closest_point` `(0, 0, 0)` for a few physics frames after a baked
  `NavigationRegion3D` joined; a query before the first sync printed `navigation map query failed because it was made
  before first map synchronization`. Waiting for `map_get_iteration_id` to rise by 2 worked until `NavigationLink3D`
  nodes were added: they bump the id too, and the wait ended early.
- **Cause:** the server applies a region over the map's next iterations, and any change is an iteration, so the id
  counts changes, not readiness. The default map is shared between tests, so its id is already high in a second test.
- **Fix:** wait for an answer: `await physics_frame` until `map_get_closest_point` on one of the mesh's own vertices
  lands within half a metre, or a path across open ground is not empty, then a few frames more for links. Take the map
  from `get_world_3d().navigation_map` (`region.get_navigation_map()` is null before the region is in the tree).
- **Also:** after a re-bake, the new mesh reached the map 3 to 12 physics ticks after `baked` under load while the old
  mesh kept answering; poll until the points the new mesh opens are reachable, not a fixed number of frames.
- **Docs:** [Zombie crowds](../godot/crowds.md); Deadnight `docs/research/zombies.md`.
