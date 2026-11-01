# A balance simulator on a stand-in weapon table passed its gate and was wrong

2026-11-01

- **Saw:** the gate said an average solo player reaches round 11 and the design doc repeated it. With the weapons the game
  already had (damage times pellets, fire interval, magazine, reload) the same seeded nights ended at round 4: the stand-in
  rifle did 210 damage a second, the real one 85 sustained. The model also gave tonics effects the game does not have and
  slowed the dead on lit ground without ever lighting a circuit, so light never cost fuel.
- **Cause:** the model's numbers were typed in beside the game's data instead of read from it, and "free" effects
  (no cost, no reload) never show up as a failing test.
- **Fix:** read every number a model uses from the game's own definitions and functions (`WeaponCatalog`, `DamageModel`,
  `NightTuning`, the generator's circuits), model only what the game does not own, drop what the game does not do, and
  say in the report where each number comes from. Then retune from the honest report.
- **Docs:** the deadnight research page `docs/research/balance-simulator.md`.
