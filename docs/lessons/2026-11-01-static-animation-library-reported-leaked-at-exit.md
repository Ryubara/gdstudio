---
areas: [godot, blender]
---
# A static AnimationLibrary was reported as leaked at exit

2026-11-01

- **Saw:** a headless run ended with `ERROR: N resources still in use at exit`, naming the clips of a shared animation
  library, though every character was freed.
- **Cause:** the library was built once and kept in a `static var` so every model's `AnimationPlayer` could share it; a
  static outlives the scene tree.
- **Fix:** give the owner a `release()` that sets the static to `null`, call it when the last user goes, and call it in
  the teardown of tests that build the library.
- **Docs:** [Rig sharing](../godot/rig-sharing.md).
