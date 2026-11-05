---
areas: [godot-ui, tests]
---
# A locked tile's way-to-earn caption wrapped to four lines and was drawn under the next row's art

2026-11-05

- **Saw:** the first capture of Deadnight #1172's hidden cards on the equip screen: the riddle under a locked emblem
  read "Eight reels in, and one" and the rest was gone; on main the locked emblems with "Play a night with another
  person" had the same overlap, unseen because nobody had read that frame at player size.
- **Cause:** `PlateTile` reserved room for two caption lines (the title and one line of what it takes); an emblem's tile
  is 132 units wide, so a sentence of 40 characters wraps to three, and the label drew past the tile into the row below,
  whose art is drawn later and covers it.
- **Fix:** the tile reserves four lines (`PlateTile.CAPTION_LINES`) and the riddles are written under 30 characters.
  Check for next time: a screen that shows a sentence in a grid is captured on its narrowest tile (the emblem tab) at
  player size and read, with the longest sentence in the data, before the sentence is written.
- **Docs:** [Calling cards](https://github.com/Ryubara/deadnight/blob/main/docs/research/calling-cards.md#hidden-pieces)
  (Deadnight).
