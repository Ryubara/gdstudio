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
