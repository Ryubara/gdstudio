---
areas: [blender, godot]
---
# An atlas cell read from UV was upside down

2026-11-03

- **Saw:** a shader meant to make the palette atlas's Amber and Pink cells glow lit nothing on the marquee's bulbs.
- **Cause:** the row was computed as `floor((1 - UV.y) * 5)`, Blender's bottom-up V. Blender's glTF export flips V, and
  Godot's UV starts at the image's top, where the atlas's first row is.
- **Fix:** `cell = floor(UV.x * 5) + 5 * floor(UV.y * 5)` in Godot; check it on one known swatch in a capture.
- **Docs:** [A backdrop past the playable bounds](../engines/godot/compat-lighting.md#a-backdrop-past-the-playable-bounds).
