---
areas: [gameplay, tests]
---
# A kit lever written in points moved the strong simulated player by a quarter

2026-11-04

- **Saw:** a first kit measurement (+5 points of dodge, +50 percent magazine) gave the Veteran solo cell 41 minutes a
  night and +13 percent rounds from the dodge alone, and a double barrel of 2 shells got a third shell from a
  "+6 percent magazine".
- **Cause:** the simulator's dodge is a chance a blow is avoided, so +0.05 on 0.80 is 25 percent fewer blows landing for
  the Veteran and 11 percent for the Regular: the same card number is a different change per skill level. The magazine
  was rounded up, so any bonus gave a small magazine a whole round.
- **Fix:** state a defence lever as a multiplier on the blows that land (`land=0.97`) and a magazine lever rounded to
  the nearest round; measure one lever at a time at a size well above the noise (400 nights a cell, mean round and
  kills, not the median, which jumps a round on a boss wall) before combining levers; print the confidence of a mean
  next to every difference.
- **Docs:** Deadnight `docs/research/weapon-progression.md` ("Which levers matter", "The simulator patch").
