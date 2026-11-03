---
areas: [gameplay, process]
---
# A design page's health table was two retunes old, and the roster was first fitted to it

2026-11-03

- **Saw:** Deadnight #785 (nine new weapons) fitted each weapon's hit to the health of round 10 (121), round 15 (170) and
  round 20 (239) from `docs/design/rounds.md`. The shipped curve in `default_tuning.tres` is `health_growth = 1.15`: round
  10 is 140, round 15 282, round 20 567, round 30 2,290. The "shots to kill" table of `weapons.md` carried the same stale
  121.
- **Cause:** the headshot retune (#745) moved the growth from 7% to 15% and said so in its own section, but the
  tuning table above it kept the 7% numbers; every later page copied that table.
- **Fix:** read the curve from the data before fitting anything: `RoundTuning.health_for(r)` (or the formula in
  `round_tuning.gd` with the values in `default_tuning.tres`), never a number copied into a page. The tables were
  corrected in the roster pull request; the baseline gate (`5 / 10 / 15 / 16 / 18 / 18`) was run first to confirm the
  model matched the code.
- **Docs:** [Rounds, the tuning table](https://github.com/Ryubara/deadnight/blob/main/docs/design/rounds.md#the-tuning-table)
  (the Deadnight repository), [the roster research](https://github.com/Ryubara/deadnight/blob/main/docs/research/weapon-roster.md).
