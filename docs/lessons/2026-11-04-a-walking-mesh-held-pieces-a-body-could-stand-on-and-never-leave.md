---
areas: [gameplay, tests, godot]
---
# A walking mesh held 131 pieces joined to nothing that a body could stand on

2026-11-04

- **Saw:** one piece of 2 by 2 m reported beside a barricade (Deadnight #1051), inferred to be left by the cut that takes
  the polygons across a barricade's line out of the walking mesh. Measured on every saved mesh of both maps with the real
  capsule walked off each piece: the cut did make that one (the two polygons joined the mesh by one edge of a polygon
  across the line), and it was one of 131 on the lot. The other 130 were in the bake: an island among the cars and the
  tops of cars and crates. On the mesh as it was, a bot set on a bonnet stood there for 15 s for every order.
- **Cause:** nothing ever asked what the pieces of the mesh were. A path never leaves the piece it starts on, and
  `map_get_path` says so with a short path and no error. A jump puts a body on a top the mesh has no way to or from, and
  every caller's fix (a walk back in one mode) sits above the fault.
- **Fix:** where the mesh goes into the regions, a piece under 30 m2 but for the largest moves to the region on the layer
  only the dead ask for. `map_get_path` starts on the nearest polygon of the layers asked for, so a person's path from
  such a spot starts on the walking ground and every mode walks off it, with no code of its own. Polygons only leave the
  walking layer, so no way across the boards can open, and the union stays, so the dead's paths do: a test compares them
  (by length: a path across two regions has a point more where they meet).
- **Check for next time:** before fixing one stranded spot, count them: list every piece of the mesh, per door state, with
  its size and place, and walk the real capsule off each (a flood over the floor) to the ground the players start on,
  then from each top so reached to the next: one climb from the ground found 80 of the 131, the car roofs are two. A
  mesh's islands are of five kinds and only one of them is a fault of the map: rooms behind a shut door, the far side
  of a barricade, roofs over the reach, hollows inside solid boxes, and what a body can walk or climb off. Mind that a
  top is a place a jump reaches even though no path does: the walking mesh is not the set of places a body can be.
  A guard for the same fault landing first (Deadnight #1050, a walk back in one mode) had a test that asserted the
  piece was cut off, so the merge turned that test red: merge the other pull request before calling the fix done, and
  read any test whose premise is the fault.
- **Docs:** [one navigation map for two kinds of walkers](../engines/godot/navigation-layers.md), Deadnight
  `docs/research/map-review.md#the-pieces-of-the-walking-mesh-1051`.
