---
areas: [godot, tests]
---
# A lit window pane glowed from the field and was a hole from the room

2026-11-03

- **Saw:** the concession's glow panes showed from outside only; from inside the stand the maintainer saw straight
  through them (Deadnight #701).
- **Cause:** the pane was a flat `QuadMesh` on a `StandardMaterial3D` with the default back-face culling, built and
  captured only from the field side. The lot's glow shader was already `cull_disabled`, so nothing suggested a glow
  could be one-sided; no capture or test looked at a flat see-through mesh from behind.
- **Fix:** `cull_mode` Disabled on the pane's material, plus a test that finds every flat see-through mesh of the maps
  and demands both faces (it fails with the fix off), and one that keeps a pane inside its opening so two faces cannot
  show through a wall. Capture any flat glow, window or sign from behind before calling it done.
- **Docs:** [Compatibility lighting](../engines/godot/compat-lighting.md#lamps-in-a-game-what-looks-like-light-and-what-is-light).
