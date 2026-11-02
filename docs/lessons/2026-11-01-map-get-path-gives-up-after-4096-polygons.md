---
areas: [blender, gameplay]
---
# A path query to an unreachable point failed on a fine navmesh

2026-11-01

- **Saw:** on a finely baked mesh (0.05 m cells over a 124 x 116 m lot) a query into a closed-off area printed `ERROR:
  It's not expect to not find the most reachable polygons` and answered a path that stopped far from the nearest
  reachable point; a coarse mesh (0.25 m) never did.
- **Cause:** `map_get_path` searches at most `path_search_max_polygons` (4096 by default); proving a target unreachable
  means exploring the whole connected mesh.
- **Fix:** query with `NavigationServer3D.query_path` and `NavigationPathQueryParameters3D` whose
  `path_search_max_polygons` is larger than the mesh; read `NavigationPathQueryResult3D.path`.
- **Docs:** [Zombie crowds](../godot/crowds.md).
