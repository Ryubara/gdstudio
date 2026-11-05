---
areas: [godot-ui, input]
---
# A tag the issue put in a column of cards could not stand clear of the stick's ring

2026-11-05

- **Saw:** Deadnight #1286 asked for a bots' order tag "in the players' column", with the stick's resting ring clear
  of it. Built there (between the points and the health card, then above the points) a test for the ring failed at the
  interface sizes 0.8 and 1.0 on both phone pages: 8 units into the ring at 1.0, 54 at 0.8.
- **Cause:** the ring (radius 105 at 225 to 435 units from the edge) crosses the column's cards, so no part a
  fingertip high and 14 CSS px wide in words can stand in the column clear of it; a card taller by a fingertip also
  costs the column's room. The issue's place and the issue's clearance could not both be met.
- **Fix:** measured, then moved the tag to the bottom row, at the inner end of the weapon strip (under the ring, no
  extra height), and said so in the pull request. Check for next time: when an issue names a place and a clearance,
  put the part there first with the clearance as a test and read the number before building the rest; a gap that the
  numbers rule out is reported with the numbers, not met by moving another issue's constants.
- **Docs:** [Touch controls](../godot/ui-controls.md#touch-controls).
