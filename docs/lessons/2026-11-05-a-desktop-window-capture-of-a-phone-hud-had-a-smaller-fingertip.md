---
areas: [godot-ui, tests]
---
# A desktop-window capture of a phone's HUD drew the column 37 units lower than the page does

2026-11-05

- **Saw:** the first picture of the players' column (Deadnight #1301), taken in a 1334 x 750 window with the touch
  layout forced on, put the column's top at 370 where the measuring test and the real page put it at 333, and the
  first-run hints ("DRAG TO MOVE") stood over the objective's second line and the column's first box.
- **Cause:** a desktop window reports a pixel ratio of 1, so `MenuScale.tap_units` gave a shorter fingertip and
  the weapon strip under the column was shorter than on a phone page (ratio 2: 102 units at 1.25); and the touch
  layer shows its first-run hints in any scene that does not mark them used.
- **Fix:** a capture scene that stands for a phone sets `MenuScale.pixel_ratio = 2.0` (the web build reads the page's
  own) and marks every hint used (`controls.hints.mark_used`) when a picture of the HUD is the point; the numbers that
  matter are read from the web export in Chrome as a phone, not from a desktop window.
- **Docs:** [Players' column on a phone](https://github.com/Ryubara/deadnight/blob/main/docs/research/players-column-phone.md).
