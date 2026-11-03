---
areas: [godot, blender]
---
# A texture import rule written for one file never matched it

2026-11-03

- **Saw:** a rule `("game/assets/smallmap/chalk_messages.png", TILING)` in Deadnight's `tools/check_texture_imports.py`
  still wrote `mipmaps/generate=false` for that texture.
- **Cause:** `ensure_import` asks `wanted()` with the path of the `.import` file, not of the image, so a pattern that
  ends in `.png` never matches; the existing rule (`textures/*`) matched by its wildcard.
- **Fix:** end a single-file rule in `*` (`chalk_messages.*`) and read the written `.import` after a build.
- **Docs:** this lesson; Deadnight `docs/design/style.md` (palette imports).
