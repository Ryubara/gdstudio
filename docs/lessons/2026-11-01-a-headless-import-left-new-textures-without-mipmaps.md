---
areas: [godot, blender]
---
# A headless import left new textures without mipmaps

2026-11-01

- **Saw:** the drive-in lot's new ground textures, imported with `godot --headless --import`, got
  `mipmaps/generate=false` in their `.import` files, so the far ground would alias.
- **Cause:** the default for a 2D texture is no mipmaps; the editor turns them on (and VRAM compression) when it
  first sees the texture used in 3D (`detect_3d`), and a headless import never does.
- **Fix:** set `mipmaps/generate=true` in each `.import` file, import again, and commit the `.import` files.
  Also set `detect_3d/compress_to=0`: leaving Detect 3D on made the editor recompress every palette on open
  ([the follow-up](2026-11-01-the-editor-recompressed-palettes-on-open.md)).
- **Docs:** [Surface materials in Compatibility](../godot/surface-materials.md#pitfalls).
