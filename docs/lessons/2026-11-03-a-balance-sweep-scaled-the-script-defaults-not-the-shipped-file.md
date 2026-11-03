---
areas: [gameplay, tests]
---
# A balance sweep scaled the script's defaults, not the shipped tuning

2026-11-03

- **Saw:** a sweep of "health x1.0" with head multipliers cut to a third gave an average solo median of 15 in one run and
  8 to 9 in another that was meant to be the same thing; seven sweeps, hours of runs, and a conclusion ("health, not
  the multipliers, is the lever") that did not survive the next run (Deadnight #745).
- **Cause:** the sweep script computed `rounds.health_base` and `health_step` as a scale of the numbers in
  `round_tuning.gd` (60 and 18). The shipped values live in `default_tuning.tres` (50 and 8); the `@export` defaults
  of a tuning script are not what the game runs. So "x1.0" was a curve with 20% more health at round 1 and more than
  twice the step, and every cell with it was far harder than the game.
- **Fix:** read the numbers a sweep scales from the file the game loads (`RulesFixture.tuning()` or
  `default_tuning.tres`), and run the unchanged baseline through the same script first: it must reproduce the gate's
  medians before any change is believed. Once the probe used the shipped tuning, the same sweeps made sense.
- **Docs:** Deadnight `docs/research/balance-simulator.md`, "The headshot retune (#745)". Check: a sweep's "x1" cell
  equals the baseline cell to the digit, or the script is not measuring the game.
