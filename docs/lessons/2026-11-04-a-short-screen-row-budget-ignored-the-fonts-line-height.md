---
areas: [godot-ui]
---
# A row-height budget for a short screen did nothing: a label is as tall as its font

2026-11-04

- **Saw:** two tickets on the end board shared the screen's height by a sum of row heights (28 px floor), but at the
  smallest canvas the lower one ran 30 px off the screen, and a mutation of the sum (the room not taken off) changed
  no picture.
- **Cause:** a `Label` is never shorter than its font's line (`custom_minimum_size.y` only raises it, `clip_text` does
  not lower it), so a 24 px label in a 26 px row made the row 33 px, and the players' 32 px type held its rows near 50
  px whatever the sum said. The sums described heights nothing drew.
- **Fix:** step the type down until `font.get_height(size)` is at most the row (floor `HudStyle.MIN_TEXT`), then
  measure: a test reads the drawn rectangles at the real canvases, and a second one checks the sum's own numbers at
  heights where the sum, not the font, decides (a mutation of the sum fails it). A test with the fullest card of the
  left column was too tall for the smallest canvas by itself (Leave off the screen): use a busy night's card to test
  what you add, and say so.
- **Docs:** none yet; `HudCredits._cell` is the example.
