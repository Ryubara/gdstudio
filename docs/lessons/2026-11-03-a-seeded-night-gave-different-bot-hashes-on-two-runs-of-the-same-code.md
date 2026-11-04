---
areas: [tests, gameplay]
---
# A seeded night gave different bot hashes on two runs of the same code

2026-11-03

- **Saw:** to show that a change left the bots alone, a seeded night (seed 11, three bots, 5,400 ticks run by hand with
  `BotTelemetry.hashing` on) was run on `main` and on the branch. The command hashes of one bot differed from tick
  1,799. Run again, `main` differed from `main`, and the branch matched `main` in one of two runs.
- **Cause:** a whole night through the real server is not bit-repeatable on this machine (something in it, perhaps the
  navigation on its worker thread or the load, moves a step); so one pair of runs proves nothing either way.
- **Fix:** do not hang "the bots are identical" on one A/B of a full night. Run the baseline twice first; if it differs
  from itself, use the bots' own deterministic suites (`tests/bots`, the golden test, the rig that feeds a bot its
  frames by hand) and say in the pull request which one was the proof.
- **Docs:** [Crowd budget](https://github.com/Ryubara/deadnight/blob/main/docs/research/crowd-budget.md) in the game.
