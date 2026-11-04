---
areas: [tests, general]
---
# A seed of the solo bot night failed when a change moved where the dead are hit

2026-11-04

- **Saw:** Deadnight #1038 (the dead hit by a folded set while they climb) failed `test_smallmap_bot_night` on seed 7
  only (1 of 620 cases): the solo bot was downed in round 4 at about 140 s and bought no weapon in 330 s. The same
  seed passed on main, and passed again on the PR merged with a later main.
- **Cause:** the night is deterministic per seed, so any change to a hit, a kill or a path moves every night after
  its first difference. A solo bot downed in round 4 has no revive, so the night ends there. Over seeds 1 to 50 (150 to
  330 s) that was 0 nights on main, 3 on the PR and 1 on the PR with the bots' aim off: a difference this size cannot
  tell a regression from the seeds moving, and the pinned four seeds were picked on the night they passed. The aim
  itself was not worse: shots at the nearest dead while it climbed hit flesh 78.0% of the time with the aim at the
  folded body against 74.9% at the upright one (40 seeds, 150 s each).
- **Fix:** none in the code; the check that tells a regression from a seed moving is a sweep over fifty seeds with
  the change and without it (the weapon bought, the bot downed, the share of shots that hit), not the four pinned
  seeds. A red seed after an unrelated change gets the sweep before it gets a fix or a skip.
- **Docs:** none beyond this lesson; the sweep is the pinned test run over seeds 1 to 50 in a scratch copy.
