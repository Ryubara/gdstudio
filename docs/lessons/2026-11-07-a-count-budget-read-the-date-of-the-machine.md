---
areas: [tests]
---
# A count held as the same on every machine changed with the date of the machine

2026-11-07

- **Saw:** Deadnight's late-round budget step failed every pull request on one day (`challenge.advance happens 0.23
  times a tick, over its limit 0.18`) with changes that touched nothing near it; main's run the day before read 0.13 on
  the same commit, and a rerun did not help.
- **Cause:** the bench's accounts were dealt their daily challenges from the machine's clock, and which three dailies
  are dealt decides how often a challenge advances. A limit on a count is only a limit when every input of the run is
  fixed: the seed, the step, the crowd and the day.
- **Fix:** the run pins the clock the code under measure reads to a fixed day (the existing `ChallengeClock.fixed`
  seam, set before the first account sits down) and the limit is set from that day. A test deals the same account
  three different machine dates and expects the same dailies (and, unpinned, different ones). Before trusting a count
  limit, run the bench with the date moved by a day (or the seed by one) and see that the count does not move; do not
  raise the limit to hide a number that moves.
- **Docs:** [Budgets: counts tight, time loose](../engines/godot/performance-budgets.md#budgets-counts-tight-time-loose).
