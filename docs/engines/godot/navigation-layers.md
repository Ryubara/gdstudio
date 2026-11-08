# One navigation map for two kinds of walkers

From Deadnight #995: the dead need a gap that a person is shut out of (a fence breach, a window with boards across it),
and the bots must not path through it. One baked mesh serves both with navigation layers.

## What worked {#what-worked}

- **Split the mesh, not the map.** Put the baked `NavigationMesh` in a region on layer 1 with the polygons across the
  gap taken out, and those polygons in a second `NavigationRegion3D` on layer 2. Both regions are in the one map. A
  path asked with `navigation_layers = 1` (the default of `NavigationServer3D.map_get_path`) never uses layer 2's
  polygons; one asked with `3` uses both. Edges the two meshes share (they come from one mesh, so their vertices are
  the same) join across the regions: the dead's paths ran from outside a gap to inside it after the split.
- **Make the default the safe one.** A region made without a layer is layer 1 and a query made without one asks layer
  1. Let layer 1 be the person's, and ask for the extra layer only where the dead are (their pathing class, their spawn
  checks): a test's arena, a stub map and a new caller then all walk where a body can. The other way round (the
  person's layer is 2) left every bot with no path in any arena that built its own region.
- **Cut by the line the boards stand on.** A polygon goes to the gap region when it crosses the barricade's line within
  the boards' length (`Geometry2D.intersect_polygons` of the polygon with a 0.2 m thick box, in the barricade's own
  space) and its height is within a storey of the barricade's feet. Polygons of the lot's mesh are 1 to 3 m across: 57 of
  3,000 cross the 16 barricades. Prefilter by bounding box: the cut costs 10 ms for a lot's mesh on a desktop.
- **`map_get_closest_point` has no layers.** A start or a goal snapped with it can land on a polygon of the other layer
  (within about 0.75 m of a barricade's line). A path started from there with the person's layer still works: it
  starts on the nearest polygon that layer allows and takes the long way round (checked from five points across a
  gap; the dead's path from the same points crosses it). A *goal* snapped onto the gap's polygons ends at the nearest
  walkable one, so a caller that accepts a path ending within a couple of metres of its goal walks up to the boards:
  keep goals and stands a metre or more from the line, or snap them yourself.

- **Take what is no place to walk off the walking layer as well.** A path never leaves the piece of the mesh it starts
  on, so a body on a scrap the cut left, on an island the bake left or on a top it jumped to has no way anywhere, with no
  error to say so. Moved to the second region (a piece under 30 m2 but for the largest; 187 of 207 pieces on Deadnight's
  lot, about 430 polygons, 6 ms more on a desktop), such a spot is not on the walking layer, and a person's path from
  it starts on the nearest walking polygon, in any mode, with no code of its own.

## What did not {#what-did-not}

- **Trusting the path and checking it after.** A ray along each path segment found the boards and cut the path short or
  marked the goal unreachable, but the nearest route to the goal was still the one through the boards, so the bot gave up
  the goal (or stood at the boards, for a brain that did not check) instead of taking the long way round by the gate.
