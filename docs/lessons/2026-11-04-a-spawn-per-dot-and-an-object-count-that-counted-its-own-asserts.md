---
areas: [godot, gameplay, tests]
---
# A trail made a mesh, a material, a node and a tween for every dot, and the test that counts objects counted its own assertions

2026-11-04

- **Saw:** the grenade trail dropped a dot about 30 times a second while a grenade flew (Deadnight #936): each a new
  64 x 32 sphere (4,224 triangles), material, node and tween, 27 alive, so 166 objects and 27 draw calls at the peak of
  a 3 s flight. It was freed (the tween freed each dot), so it never leaked, and nothing flagged it: "freed" was taken
  for "cheap". The first version of the pooling test then failed with 360 more objects after a flight, none of them
  the game's: `assert_int(...)` inside the step loop makes an object each call.
- **Cause:** a fade written as "one node and one tween per dot" is the easy shape for one-off effects, and a trail is
  not one-off. And an assertion is itself an `Object` (a `RefCounted` of GdUnit), so counting `OBJECT_COUNT` around
  assertions measures the assertions.
- **Fix:** many identical short-lived fading things are one `MultiMesh` over one shared mesh and one shared material
  (`vertex_color_use_as_albedo` with the per-instance colour alpha for the fade), a ring with a cap that takes over the
  oldest, aged by the simulation's step, written as one `PackedFloat32Array` (16 floats an instance with colours); the
  class holds the shared resources and the warm-up draws it once. A test that counts objects reads
  `Performance.get_monitor` before and after and asserts afterwards, never inside the counted loop.
- **Docs:** [Performance review](../engines/godot/performance-review.md), checklist 3 (spawns and lifetime) and "How to
  measure
  it".
- **Also:** `pre-commit run --all-files` ran before `git add`, so it never saw the new files: the commit then failed on
  a line over 100 characters and a missing `.gd.uid`. `git add -A` first (and open the project once for the uid), then
  run the hooks.
