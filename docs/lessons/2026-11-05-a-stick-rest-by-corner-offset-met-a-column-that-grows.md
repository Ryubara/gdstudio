---
areas: [godot-ui, input, tests]
---
# A resting place kept by a corner offset met a column that grows with the party

2026-11-05

- **Saw:** after the HUD's players column rose a weapon strip's height (Deadnight #1284), the move stick's resting ring
  (330 right, 390 up of the corner, times the touch scale) was over the points card, and the perk badges beside the
  column. Raising the number moved the first-run hint over the cards instead (the first attempt, Deadnight #1280).
- **Cause:** the column grows upward with the party (the points card's top is 769 units up with one player, 607 with
  four, 503 with eight), the badges grow with the perks, and the offset was scaled by the touch scale (0.8 to 1.4), so
  no one corner offset clears them for every party and every scale. A test with one party size and one scale passed.
- **Fix:** the place is kept clear by its edges (left edge right of the column and the badges, bottom edge above the
  tallest strip, neither scaled), so it is beside the column, not above it; the test runs both phone pages, three
  interface sizes, both hands, three touch scales and parties of one, four, eight and eight with bots, and fails with
  the old numbers. A layout number is tested against the thing that grows, at its largest.
- **Docs:** [Mobile controls](https://github.com/Ryubara/deadnight/blob/main/docs/research/mobile-controls.md), "The
  stick's resting place", in Deadnight.
