---
areas: [blender, tests]
---
# A thin closed shape turned inside out looked right in the engine

2026-11-04

- **Saw:** Deadnight's Cinema glasses looked correct on the turntable with back faces culled; the sweep
  (`test_every_part_is_closed_on_both_bodies`) failed them with 4 rays seeing through. A coveralls patch beside them
  rendered as a half-moon.
- **Cause:** a prism's outline given clockwise, or built with a negative thickness, has every face turned inward. With a
  shape only 14 mm thick the culled front lets you see the inside of the back wall, in the same swatch, about where the
  front was: the shape is there, the eye is simply looking through it.
- **Fix:** one rule in the helper (`plate`: the outline is always counter-clockwise from the front, and the two ends are
  sorted, so a negative thickness cannot flip it). Do not judge the winding of a thin shape from a render: run the probe
  on every new part alone.
- **Docs:** [Closed, and fitting, in every combination](../tools/blender/variants.md#closed-and-fitting-in-every-combination).
