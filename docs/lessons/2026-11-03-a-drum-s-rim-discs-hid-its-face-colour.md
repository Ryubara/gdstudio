---
areas: [blender]
---
# A drum's rim discs hid its face colour

2026-11-03

- **Saw:** the PPSh's drum, planned Grey2 with a DarkGrey rim, read DarkGrey in the render, and
  `measure_weapons.py` gave the gun 46 % DarkGrey and 12 % Grey2 (Deadnight #795).
- **Cause:** each rim was a short cylinder of a slightly larger radius at the drum's face, and a cylinder is capped:
  its end disc covered the whole Grey2 face.
- **Fix:** one DarkGrey band round the drum's middle (a cylinder across part of its width) and Grey2 to the faces. A
  trim on a round part is a band or a ring, never a capped cylinder over a face; read the cells by area after a build.
- **Docs:** [Weapons, building by script](../tools/blender/weapons.md#building-by-script).
