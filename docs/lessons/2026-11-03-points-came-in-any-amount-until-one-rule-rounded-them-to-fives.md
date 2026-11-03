---
areas: [gameplay, tests]
---
# Points came in any amount until one rule rounded them to fives

2026-11-03

- **Saw:** the maintainer's score read 31, 32, 33, 34 ("always 5s for consistency", Deadnight #916). A scripted night
  showed pays of 4, 8, 12, 72, 156 and prices of 3, 8, 18, 33, 103.
- **Cause:** the score had no unit step. The tuning stepped by 1 (hit 4 and 8, repair 12), a zombie type's
  `points_multiplier` (1.2, 2.5, 6.0) scaled every pay and rounded it to a whole point, and part purchases, the
  crane refund and the down penalty each rounded to 1 in their own way. The HUD then merged hit rows into sums.
- **Fix:** one rule in one place on the server, after the last multiplier (`PointSteps`: an award to the nearest 5 and
  never below 5, a price up to the next 5, a loss down to the 5), the tuning fields stepped by 5, and a test that plays
  seeded full nights and fails on any points event, total or price off the step. Rounding 4 and 8 to 5 and 10 was a
  retune: the same nights earned 20% more (a brute pays 8 hits, a headliner 20, times 2.5 and 6) and the average solo
  median went from 13 to 15 rounds (the gate allows 14), so the kills pay 5 less. Run the balance gate in the same
  pull request as any rounding of a tuning number.
- **Docs:** the Deadnight rounds page, "Points come in fives" and "Points in fives (#916)".
