---
areas: [blender, godot]
---
# A palette written as linear came out dark

2026-11-02

- **Saw:** Deadnight's small-map walls drew a muddy brown in Godot beside a CSG wall of the same Concrete tint. The
  saved palette's Concrete cell read `(82, 78, 67)` where the swatch is `#9a968c` `(154, 150, 140)`.
- **Cause:** the build filled a byte (8-bit) Blender image's `pixels` with `srgb_to_linear(swatch)`, believing the
  buffer is linear. For a byte image `pixels` are the stored values, so the PNG held linear numbers and every engine
  decoded them as sRGB again. The palette builder had been copied from the drive-in props, whose atlas has the same
  fault (Deadnight #651).
- **Fix:** write the sRGB swatch as it is (`px = [*rgb, 1.0]`); then read one cell of the saved PNG back and compare it
  with the hex value in the build log or a test.
- **Docs:** [Modular kits: building the pieces](../tools/blender/modular-kits.md#building-the-pieces).
