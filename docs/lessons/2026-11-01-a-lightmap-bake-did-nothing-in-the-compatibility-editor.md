---
areas: [godot-ui, godot]
---
# A lightmap bake did nothing in the Compatibility editor

2026-11-01

- **Saw:** "Bake Lightmaps" ended in 0.00 s with no file and no error; scripts cannot call `LightmapGI.bake()`.
- **Cause:** baking needs a RenderingDevice, which the Compatibility editor lacks; with no `light_data` the button
  only opens a file dialog.
- **Fix:** a Vulkan editor (`--editor --rendering-method forward_plus`), a saved `light_data`, and the button pressed
  from a tool plugin; the game still runs in Compatibility.
- **Docs:** [Compatibility lighting](../engines/godot/compat-lighting.md#lightmapgi).
