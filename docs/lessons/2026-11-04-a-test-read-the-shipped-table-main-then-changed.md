---
areas: [tests, ci]
---
# A test read the shipped data table, main changed the table, and CI ran the merge

2026-11-04

- **Saw:** Deadnight's popup pull request (#1136) passed every suite I ran, then `godot (1)` failed with four
  failures: three in `test_popup_lane.gd` (holes counted toward "the next unlock" of the shipped ladder) and one in
  `tests/tuning` (the new tuning fields had no row in `default_values.gd`).
- **Cause:** CI tests the merge with the current `main`. Another pull request had meanwhile made levels 18 and 19
  `available` in `unlocks.json`, so the next unlock after level 17 moved from 20 to 18; my test asserted numbers of
  the shipped table. And I ran only the suites of the folders I had touched: `tests/tuning` loops over every
  exported field of `HudTuning` and was never run.
- **Fix:** a test of arithmetic feeds its own table (`LadderUnlocks.from_text`) and checks a card against the
  function on the shipped table, never against numbers read off it; add a field to a tuning resource with its row in
  `tests/tuning/default_values.gd`. Before pushing, run `gds merge-main` and the whole `game/tests` tree (or CI's
  shard command), not the folders of the change.
- **Docs:** the game's `docs/research/popup-lane.md` (Deadnight, #1064).
