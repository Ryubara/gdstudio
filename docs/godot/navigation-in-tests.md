# Navigation in tests

How to test code that asks the navigation server for paths, from Deadnight's bot movement (Deadnight #226). The game's
own notes on its mesh are in `docs/research/zombies.md` and `docs/research/bots.md`.

## A small mesh of your own

A unit test of path code needs a mesh it controls, not the lot's. Build a navigation map of its own from squares of
ground: `NavigationServer3D.map_create()`, `map_set_active(true)`, a `region_create()` joined to the map with
`region_set_map`, and a `NavigationMesh` whose polygons share their corner vertices (neighbours join where they share an
edge; clockwise seen from above). Free the region and the map when the test ends.

- **`map_force_update` is not "ready".** It moves `map_get_iteration_id` to 1, and a query after it no longer prints the
  "before first map synchronization" error, but the polygons of a region you just added are still not in the map: the
  path comes back empty. Wait with `await get_tree().physics_frame` until `map_get_closest_point` on one of your own
  vertices answers within half a metre (the same rule as
  [a new region](../lessons/2026-11-01-wait-for-a-navigation-answer-not-an-iteration-id.md)).
- **A door's new mesh is an iteration.** Putting a fresh mesh into the region again and waiting a few physics frames
  moves the iteration id, which is how a test makes "the map took the new mesh in".
- **A lambda copies a packed array.** Building the vertex list inside a lambda (`var corner := func(...)` appending to a
  `PackedVector3Array` declared outside) appends to a copy and the mesh comes out empty
  ([lesson](../lessons/2026-11-02-a-lambda-appended-to-a-copy-of-a-packed-array.md)). Use a method and member variables.

## Asserting that nothing was printed

A navigation query before the map has synchronised prints an `ERROR` and the test goes on and passes: GdUnit4 does not
count it. Install a `Logger` for the length of the test and assert it saw nothing:

```gdscript
class_name ErrorCatcher
extends Logger

var lines: Array[String] = []

func start() -> void: OS.add_logger(self)
func stop() -> void: OS.remove_logger(self)

func _log_error(function: String, _file: String, _line: int, code: String, rationale: String,
        _editor_notify: bool, _error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
    lines.append("%s: %s %s" % [function, code, rationale])
```

Stop it in `after_test` as well, so a failing test does not leave it installed. The same class is what GdUnit4's own
`GdUnitScriptErrorCollector` uses.

## What the baked mesh closes

The lot's mesh is baked for an agent of radius 0.5 m; the player's capsule is 0.35 m. A 1.8 m gap between parked cars
is 0.8 m of mesh after the erosion, which the bake's cell rounding closes for most of them: of about 60 pairs of
neighbouring cars, four are open to the mesh and the rest are a 12 to 34 m detour. A test that crosses "every car gap"
must pick the gaps by asking the mesh (a path across them of about the straight length), not by the cars' positions
([lesson](../lessons/2026-11-02-the-baked-mesh-closes-the-car-gaps-the-player-fits.md)).

## A goal in a wall

A point inside a wall, a closed door's slab or a counter is no goal for a path: it snaps to whichever side of the wall's
cut-back edge is nearer in 3D, and that can be the shut room behind it (a different island), so the path ends far short.
Use a point on the open ground in front of it (Deadnight's `NightWorld.door_stands`, 1.5 m out) and make the test ask
the map where the path ends, within the bots' 2.5 m
([lesson](../lessons/2026-11-02-a-goal-in-a-wall-snapped-into-the-shut-room-behind-it.md)).

## Never wait a fixed number of frames for a mesh

A door's saved mesh is swapped into the region at once, but the map takes it in over 8 to 12 physics frames (async
map iterations: the count moves with machine load). A test that waited 12 frames failed one run in three
(Deadnight #699). Poll until the map answers for what the mesh opens (a path from the start to a point in each open
area ends within a metre of it, and `DoorNavigation.is_busy()` is false), with a large cap that fails with a message,
and do not read a path after an assertion on its status that may have failed: GdUnit goes on after a failed assertion
([lesson](../lessons/2026-11-03-a-fixed-frame-wait-for-a-navigation-mesh-failed-one-run-in-three.md)).

## A thread-synced map drops meshes swapped in one go

With `navigation/world/map_use_async_iterations` on (the default), a loop that swaps several meshes into a region in one
frame (a test selling every door) can leave the map on an older mesh for good: the iteration id ends lower on those runs
(7 against 8 or 9), `map_force_update` does not move it, and the dead's paths end short of their targets so they stand
still (Deadnight #733, #736). Turn it off for a server's map with
`NavigationServer3D.map_set_use_async_iterations(map, false)`: the physics step takes the mesh in, the same on every
machine ([lesson](../lessons/2026-11-03-async-navigation-iterations-dropped-the-last-of-several-door-meshes.md)). A
check that finds it: print the end of `map_get_path` from a stuck dead one to its target.

## A night stepped by hand has a stale map

A loop of `night.tick()` calls with no `await get_tree().physics_frame` between them never lets the navigation server
take a new mesh in: a door bought in it leaves the map as it was, so the dead (and the bots) path on the old walls.
Give the engine a physics frame every few ticks (the soak does one every 30) and wait for the map's answer after a
purchase, as `SeatedNight.settle` does ([lesson](../lessons/2026-11-02-a-night-stepped-by-hand-never-took-a-bought-doors-mesh.md)).

## Measuring a map on its mesh

How Deadnight's second map is held to its design targets (Deadnight #631, `tests/world/smallmap/` there):

- **Floor area.** Bake a second mesh with `agent_radius = 0` and fine cells (0.05 m) inside the building's box, with a
  box plugging every opening to the outside, so the mesh is the inside only. Walk the polygons joined to a start
  polygon (polygons are joined when they share an edge, two vertex indices) and add their areas on the ground plane:
  furniture tops and the space under a stair are walkable to the bake but never joined, so they drop out. Count a
  polygon to the room whose rectangle holds its middle on its floor. A 10 x 10 m room measures 94 to 97 m².
- **Which rooms join.** Bake the zombies' mesh once for each set of sold links (eight for three free links) and ask
  for a path between room middles. Compare the path's end in 3D, not on the ground plane: a goal upstairs is right
  above a floor the path does reach.
- **Laps and loops** are sums of path lengths through markers the generator places on the loop.
- **Sight lines.** Rays at eye height between standing points (each room's edge every 0.5 m, inside every metre):
  list the pairs, sort them longest first, and stop at the first clear one. 870 points take under a second.
- **Bodies on the mesh.** A soak that walks real player bodies along the mesh puts them on a physics layer of their
  own: bodies that collide stand on each other in a stair
  ([lesson](../lessons/2026-11-02-soak-bodies-that-collide-stood-on-each-other-on-a-stair.md)).
- A `SceneTree` script that measures starts after `await process_frame`, and every headless run gets a `timeout`
  ([lesson](../lessons/2026-11-02-a-scene-tree-script-with-a-parse-error-never-quit.md)).
