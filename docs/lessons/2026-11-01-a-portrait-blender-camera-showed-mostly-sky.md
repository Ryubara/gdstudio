---
areas: [blender, camera]
---
# A portrait Blender camera showed mostly sky

2026-11-01

- **Saw:** the 2:3 versions of Deadnight's title art, rendered with the 16:9 shots' cameras and lenses, had the
  players small at the bottom under two thirds of empty sky.
- **Cause:** with `sensor_fit = "AUTO"` Blender fits the 36 mm sensor to the frame's long side, so in a tall frame
  the same lens covers the full 36 mm vertically (84 degrees at 20 mm) and only 24 mm across.
- **Fix:** frame portraits with a longer lens (the landscape lens times about 1.35) and the subject a little lower,
  or set `sensor_fit = "HORIZONTAL"` when the width must match.
- **Docs:** [Key art](../blender/key-art.md#title-art-and-store-sizes).
