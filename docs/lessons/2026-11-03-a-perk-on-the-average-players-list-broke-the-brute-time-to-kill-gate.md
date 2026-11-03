---
areas: [gameplay]
---
# A faster-fire perk on the average player's list put the brute under the gate by 0.01 seconds

2026-11-03

- **Saw:** Deadnight #687: with the double shot on the modelled average player's shopping list the balance gate failed
  on `time to kill a brute is 3.00 s, wanted 3.0 to 12.0`, and the four-player median went from 15 to 18 to 20 (the gate's
  ceiling is 17) with all six perks on the list.
- **Cause:** the gate's ranges describe nights without the new power; a perk that shortens every fight moves every one of
  them. And a solo median is not a stable number on a hundred nights: the same seed gave 13 and 10 on 100 and 150.
- **Fix:** read the mean round and the share of nights that reach round 10 and 14 beside the median; leave the ranges and
  choose what the modelled players buy (the average and the strong buy the quick load and the swift rescue, the weak
  none) and the double shot's strength (x1.33, 3,000); say in the research page that the double shot is held off the lists
  by the gate and what moving the ranges would mean.
- **Check for next time:** a feature that raises damage, fire rate or health runs the whole gate (`test_balance_targets.gd`)
  and the nine cells before the pull request, not only the cell it was built for.
- **Docs:** Deadnight `docs/research/perks.md`, `docs/research/balance-simulator.md`.
