---
areas: [tests, godot-ui]
---
# A column ran off the screen while the test looked at one part

2026-11-04

- **Saw:** Deadnight #1145. With the fullest night report at 1536 x 864 the end board's Leave button sat at y 950, below
  the screen, and the card's own fit test was green. It was found by reading a report's sum, not by a test.
- **Cause:** the test asked whether the card was on screen and clear of Leave, never whether Leave was on screen. The
  column's parts stand in a box that grows with them, so the card stayed inside while what followed it left. Beneath
  that: a hand-written chrome of 150 against 239 real units, a title that wrapped to a second line, and a row floor of
  24 below the type's own height of 34, so shrinking the rows did nothing.
- **Fix:** every part of the column is checked, at the fullest content and at every canvas. The card measures itself
  instead of a constant, and its rows and type step down together.
- **Check:** a fit test names each part of the column, above all the one the player must reach, and uses the fullest
  content the game can produce, not a busy example. A smaller size has to be measured to shrink anything: see
  [a row budget that ignored the font](2026-11-04-a-short-screen-row-budget-ignored-the-fonts-line-height.md).
