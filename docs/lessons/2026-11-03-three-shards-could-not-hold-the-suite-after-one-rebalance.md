---
areas: [ci, tests]
---
# Three shards, rebalanced once by script, were back at the 15-minute limit within a day

2026-11-03

- **Saw:** `godot (1)` of Deadnight was cancelled at 15 min on `main` and on two pull requests, five main runs in one
  day (11 min 51 s, 14 min 46 s, 14 min 12 s, then two cancelled), after the earlier fix (#676) had left "about 10
  minutes each". No test failed.
- **Cause:** the suites alone were 2,018 s on the runner in a fast run and 2,325 s in a slower one (a run varies by
  15 %), the suite grows with every merged PR, and a shard's job is its suites plus about 50 s of setup. Three shards
  cannot be under 9 minutes for 2,000 s; moving three scripts only delayed the limit.
- **Fix:** read the seconds per script from the job logs of two green `main` runs (the gap between `Run Test Suite:`
  lines), and size the number of shards from the total (`total / 480 s`, rounded up with a margin for a slow runner),
  not from the folder that is over. Deadnight now has six shards of about 6 minutes of suites; the limit stays 15.
- **Check for next time:** when a shard drifts, divide the total of all shards by the budget before moving scripts; if
  the quotient is above the shard count, add a shard. Leave the budget (about 7 min a shard, limit twice that) as it
  is.
- **Docs:** [CI time](https://github.com/Ryubara/deadnight/blob/main/docs/research/ci-time.md) (Deadnight; the section
  "Six shards, by measured seconds").
