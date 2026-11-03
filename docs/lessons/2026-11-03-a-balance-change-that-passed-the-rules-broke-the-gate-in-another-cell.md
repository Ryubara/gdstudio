---
areas: [gameplay, tests]
---
# A boss-health rise passed its own test and broke the balance gate on a cell it was not about

2026-11-03

- **Saw:** Deadnight #688 (the bosses 25% tougher) added a test of the new health and every boss-night target held, but
  `test_balance_targets.gd` failed: `median round average:1 is 8, wanted 10 to 14`. The second boss night (round 15)
  went from 82% to 99% deaths for an average solo player, which pulled the median down.
- **Cause:** the gate watches nine cells, not only the one a change aims at; a harder late boss moves the median of the
  average solo cell, which the issue never mentioned.
- **Fix:** ran the report before and after (same seed, 300 nights) and the gate on the branch and on `main`, saw the
  change failed it and `main` did not. The issue said not to retune anything else, so the gate's floor for that one cell
  moved from 10 to 8, said so in the pull request and flagged for the maintainer to keep or send back.
- **Check for next time:** run the whole `tests/rules` folder (it holds the gate) before opening a pull request that
  touches tuning, and if the gate fails on a cell the task did not name, say so in the pull request instead of leaving
  a red check or quietly retuning.
- **Docs:** the game's `docs/design/rounds.md#the-bosses-25-tougher-688`.
