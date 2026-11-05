---
areas: [tests, godot-ui]
---
# A pixel test of an icon's position missed its dark outline and reported errors that were not there

2026-11-04

- **Saw:** a test that measured where an icon's ink sat by drawing the place twice (with the icon, and with it made
  clear) and taking the rows where the pictures differ reported the scoreboard's icon 1.2 px off. A second look, with
  the icon drawn in one flat colour, showed it was within 0.4 px: the first reading had been wrong.
- **Cause:** the icon's outline is nearly black and the card behind it is nearly black, so those rows differ by less
  than the threshold and are not "changed": the icon looked shorter at its dark edge, and its centre moved. The error
  followed the art (one frame had a dark edge at the bottom) and so looked like a real fault in some levels only.
- **Fix:** read a thing's pixels by drawing it in a flat colour no other thing uses and counting that colour's share of
  each pixel over the ground (digits: the label's colour, outline and shadow set clear; icon: the atlas with its
  colours replaced and its alpha kept). Check a measurement against a case you know before trusting it: the "before"
  of a fix measured with the new method showed which places had never been wrong.
- **Docs:** [Level badge alignment](https://github.com/Ryubara/deadnight/blob/main/docs/research/level-badge-alignment.md),
  "How it is measured" (Deadnight).
