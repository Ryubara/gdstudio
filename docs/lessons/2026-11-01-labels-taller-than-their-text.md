---
areas: [godot-ui, godot]
---
# A label's rectangle is taller than its text, and SHRINK_END aligns boxes, not baselines

2026-11-01

- **Saw:** a HUD number box 42 units high held a 32-unit label whose rectangle ended 3 units below the box; a small
  reserve count beside a big magazine count sat below its baseline, though both were `SIZE_SHRINK_END`.
- **Cause:** a Label is as tall as its font's line (about 1.4 times the size), not its capitals, and `SHRINK_END` lines
  up the bottoms of the boxes, which differ by the fonts' descents.
- **Fix:** size a box from the line height it holds; put two sizes on one baseline by placing each label at `baseline -
  font.get_ascent(size)`, or by lifting the smaller one by the difference of the descents. A layout test that measures
  label rectangles against their parent's finds both at once.
- **Docs:** [UI controls](../engines/godot/ui-controls.md); in Deadnight, `docs/research/hud.md`.
