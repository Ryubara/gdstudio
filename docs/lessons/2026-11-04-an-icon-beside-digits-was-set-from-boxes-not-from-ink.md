---
areas: [godot-ui]
---
# An icon beside digits looked misaligned because each place centred it on a box

2026-11-04

- **Saw:** the maintainer: "the level number and the icons aren't really aligned vertically". Measured from pixels
  (Deadnight #1161): the icon's body sat 7 px above the digits in the bottom-left box (9.5 in the local one, 3 in the
  compact one), 1 to 1.4 px in the lobby, and under half a pixel in the scoreboard, the tag and the report.
- **Cause:** the digits are placed from a baseline and the icon from a box (the box's middle, a `0.3 * font size`
  nudge, a centring container), and neither box is what is drawn: digits sit on the baseline at the font's digit
  height (the line keeps room for a descender), the art's body is not at the middle of its cell (the bulbs take the
  bottom; 0.46 or 0.445 by frame), and the engine sets a label's line on a whole unit. Where a guess was right the fault
  hid; the box's baseline belongs to the big numerals, so the guess there was far out. A test of rectangles ("the icon
  is centred in the box") had pinned the fault in place.
- **Fix:** one helper (`LevelTag.digits_centre`, `icon_top`, `icon_top_in_row`) that takes the digits' ink from the
  font's glyph outlines and the icon's body from the atlas, called by every place; a pixel test of every place at
  every size (`test_level_ink.gd`) instead of the box test.
- **Docs:** [Level badge alignment](https://github.com/Ryubara/deadnight/blob/main/docs/research/level-badge-alignment.md)
  (Deadnight); check for the next pair that travels together: place the second by where the first is drawn.
