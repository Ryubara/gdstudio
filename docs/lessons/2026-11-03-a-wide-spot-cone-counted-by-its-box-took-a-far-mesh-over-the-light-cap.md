---
areas: [godot, tests]
---
# A wide spot cone is counted by the box of its widest end, and took a far mesh over the light cap

2026-11-03

- **Saw:** the back lot's new neon sign carried the stand sign's spot (85 degrees, range 10 m) in place of an omni, and
  `test_lot_light_cap` failed: "crane spot SpotCraneYard: GeneratorYard/Ground0_1 is lit by 7 lights, over 6" (Deadnight
  #852). The yard is 60 m from the sign.
- **Cause:** `LightReach` counts a spot by the axis-aligned box of the base of its cone, `range * tan(angle)` on a side:
  `tan(85 degrees)` is 11.4, so a 10 m spot is a box 114 m across and reaches every ground tile of the lot on its line.
  The stand's sign passes because its neighbours are few; the box does not care what the cone really lights.
- **Fix:** narrow the cone where nothing needs it wide (`LotNeonSign.light_angle`, 60 degrees: a 17 m box) and run the
  light-cap suite before a spot is added or swapped in, with the new lamp's reach printed when it fails.
- **Docs:** [Compatibility lighting](../engines/godot/compat-lighting.md) (the "Test the cap" bullet).
