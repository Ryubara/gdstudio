---
areas: [godot-ui, input]
---
# A tag the issue put in a column of cards met the stick's ring, then the challenge card

2026-11-05

- **Saw:** Deadnight #1286 asked for a bots' order tag "in the players' column", with the stick's resting ring clear
  of it. Built there (between the points and the health card, then above the points) a test for the ring failed at
  the interface sizes 0.8 and 1.0 on both phone pages: 8 units into the ring at 1.0, 54 at 0.8. While the work was
  open another pull request (#1294) moved the ring beside the column, so the same tag would then clear it; a second
  measure (the challenge card against the touch HUD with and without a column tag) showed the card over the tag at
  4 players on 1920 x 1080 and 2337 x 1080 and at 2 on 1536 x 864.
- **Cause:** a part a fingertip high in a bottom-anchored column makes the column a fingertip taller (128 units), and
  parts that stand at a share of the screen's height (the challenge card at 0.36) were placed for the old column; the
  one clearance the issue named (the ring) was not the only neighbour. The marker capacity did not change.
- **Fix:** measured, then put the tag at the inner end of the weapon strip's row (no extra column height), and said so,
  with both measures, in the pull request. Check for next time: when an issue names a place, put the part there first
  and measure every neighbour that stands at a share of the screen or reads the column's height (the ring, the
  challenge card, the markers) with the touch layout on, before building the rest; and re-measure a number that
  another pull request can move before it goes into the argument.
- **Docs:** [Touch controls](../engines/godot/ui-controls.md#touch-controls).
