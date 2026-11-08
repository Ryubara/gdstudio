---
areas: [tests, blender]
---
# A light cap test that saw only boxes

2026-11-01

- **Saw:** the lot's light cap test passed, yet a stronger test found six meshes reached by 7 or 8 lights, before any
  muzzle flash or blast added its own.
- **Cause:** the test walked `CSGBox3D` only and accepted a worst of exactly 8; props, cars and run-time lights were
  never counted.
- **Fix:** count every shaded mesh, keep 2 lights free for the fight, find light sources by walking the project, and
  hold known overruns in a ratchet table.
- **Docs:** [Lighting in Compatibility](../engines/godot/compat-lighting.md).
