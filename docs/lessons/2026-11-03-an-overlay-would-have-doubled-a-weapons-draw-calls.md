---
areas: [godot, web]
---

# A skin over a weapon is a swap of the surface's material, not an overlay

- **Symptom (caught before it shipped):** the first idea for Deadnight's re-cut weapon skin (#787) was a
  `material_overlay` on every mesh, which the old bench glow used. An overlay draws each surface a second time, and the
  phone's budget is draw calls.
- **Cause:** an overlay looks like a layer over the palette material, which is what the maintainer asked for, but the
  renderer reads it as a second pass.
- **Fix:** a shader that stands in the surface's own material (`set_surface_override_material`), copying its palette
  texture, metallic and roughness, so the weapon draws as often as before; a test counts the surfaces with and without
  the skin and that no mesh has an overlay or a `material_override`. The web bench (20 zombies, ten re-cut weapons
  held out near the camera) read the same draw calls with and without it (111.0 and 111.0 on the phone profile).
- **Documented:** [Surface materials](../godot/surface-materials.md#re-skinning-a-model-that-is-already-painted).
