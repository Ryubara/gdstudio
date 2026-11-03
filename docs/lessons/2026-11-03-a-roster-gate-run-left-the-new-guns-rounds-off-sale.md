---
areas: [gameplay, tests]
---
# A balance run of new weapons without their ammunition on sale read two rounds too low

2026-11-03

- **Saw:** the research for six new firearms (#785) ran the balance gate with draft definitions and read medians
  5 / 12 / 15 / 17 / 18 / 18. The build (#793), with the same numbers but the guns' rounds sold at the locker,
  read 5 / 15 / 15 / 17 / 18 / 18 (average solo over its 14), and the headliner's time to kill 31.5 s (limit 30).
- **Cause:** the draft run registered definitions and crane weights but no `ammo_<id>` shop rows, so a weapon ran
  dry at its reserve and the players could not buy more. Rounds on sale are most of what a weapon is worth in the
  model.
- **Fix:** a roster run registers everything a player can reach: the definition, the wall and crane rows, the
  ammunition rows and the re-cut list. Compare with a control (the new guns defined and left out of the pool must
  give the baseline exactly) from a detached checkout of `main`. A median is two humps wide: read the mean and the
  shape with it. The gate's headliner time is the mean of about 60 kills and moves a second either way with one
  gun, so retune with the tuning's own levers (`health_growth`, the headliner's health) and say which sample each
  number came from.
- **Docs:** the game's `docs/research/balance-simulator.md`, "The six firearms (#793)".
