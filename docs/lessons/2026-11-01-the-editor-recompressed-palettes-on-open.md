---
areas: [godot, blender]
---
# The editor recompressed the palettes on open

2026-11-01

- **Saw:** opening the pinned editor on the main checkout rewrote 11 texture `.import` files (palettes and lot
  textures): VRAM compression and mipmaps on, the palette colours off by up to 12/255.
- **Cause:** Detect 3D (`detect_3d/compress_to=1`, the default) switches a texture used by a 3D material to
  compressed with mipmaps the first time the editor sees it; headless imports (agents, CI) never do, so every editor
  session dirtied the checkout.
- **Fix:** Detect 3D off and every setting stated in all texture `.import` files; Blender builds write the `.import`
  with the PNG; a check runs in pre-commit and CI (Deadnight #441, #454).
- **Docs:** [Surface materials in Compatibility](../godot/surface-materials.md#pitfalls).
