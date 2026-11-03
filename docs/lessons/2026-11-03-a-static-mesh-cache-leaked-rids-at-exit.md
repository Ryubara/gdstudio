---
areas: [godot, tests]
---
# A static cache of meshes failed CI's exit-leak gate

2026-11-03

- **Saw:** `godot (6)` failed on deadnight #837: `ERROR: 22 RID allocations of type 'DummyMesh' were leaked at
  exit` (plus 2 DummyShader, 1 DummyMaterial); `! grep -E "leaked at exit|still in use" tests.log` is the gate.
- **Cause:** `static var _cache: Dictionary[StringName, ArrayMesh]` shared one mesh per weapon, and a static outlives
  the scene tree, so the meshes (and the material and shader inside them) were still alive when the engine quit.
  The local headless run checked for `ERROR` at start-up but not the exit-leak grep over the whole test log.
- **Fix:** hold `WeakRef`s in the static: a mesh lives while a plaque shows it, spots still share one, nothing is
  left at exit. Before pushing, run the shard's folders with `--verbose` and grep the log for `leaked at exit|still
  in use` (the CI step's command).
- **Docs:** [Godot leaks at exit](../godot/index.md); the CI test step in a game's `.github/workflows/ci.yml`.
