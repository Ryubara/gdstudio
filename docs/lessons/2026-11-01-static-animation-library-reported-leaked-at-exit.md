---
areas: [godot, blender, tests]
---
# A static cache of resources was reported as leaked at exit

2026-11-01

- **Saw:** a headless run ended with `ERROR: N resources still in use at exit`, naming the clips of a shared animation
  library, though every character was freed.
- **Cause:** the library was built once and kept in a `static var` so every model's `AnimationPlayer` could share it; a
  static outlives the scene tree.
- **Fix:** give the owner a `release()` that sets the static to `null`, call it when the last user goes, and call it in
  the teardown of tests that build the library.
- **Again, 2026-11-03 (deadnight #837):** a `static var` of wall-silhouette meshes failed `godot (6)` with 22 DummyMesh,
  2 DummyShader and 1 DummyMaterial RIDs leaked, the materials and shaders held through the meshes. The fix there was a
  `Dictionary[StringName, WeakRef]`: a mesh lives while a node shows it, spots still share one, nothing outlives the
  tree. The local run had only grepped for `ERROR`; run the shard's folders with `--verbose` and grep the log for
  `leaked at exit|still in use` (the CI step's command) before pushing.
- **Docs:** [Rig sharing](../godot/rig-sharing.md).
