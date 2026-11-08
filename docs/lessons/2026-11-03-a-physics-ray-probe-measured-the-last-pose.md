---
areas: [tests, godot]
---
# A physics ray probe measured the last pose, and the clip before it

2026-11-03

- **Saw:** a clip sampler (rays against `ConcavePolygonShape3D`s rebuilt for every pose) gave a clip 120 mm alone and
  132 mm after another clip; the first probe of a closed ball said every ray saw through it.
- **Cause:** new shape faces reach the space's broadphase only after a full physics step, and one awaited
  `physics_frame` was not always one; clips that do not key the fingers kept the last clip's fingers; the probe had
  flipped the triangles, but a concave shape's faces front the way the mesh draws them.
- **Fix:** await two `physics_frame`s after `set_faces` (and run the suite at `physics_ticks_per_second = 480`),
  `Skeleton3D.reset_bone_poses()` before each sample, keep the mesh's winding; a test checks the probe on a closed and
  an opened ball first (Deadnight `test_soldier_watertight.gd`).
- **Docs:** [Closed, and fitting, in every combination](../tools/blender/variants.md#closed-and-fitting-in-every-combination).
