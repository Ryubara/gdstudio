---
areas: [gameplay, tests]
---
# A weapon retune held the damage a second and lost the weapon pick

2026-11-03

- **Saw:** The pump shotgun became a double-barrel (2 shells, 21 a pellet, 2.0 s reload) with the damage a second
  with reloads kept at the pump's (129 against 127). `test_sim_weapons` failed: against round 10's health the
  submachine gun now out-ranked it, and the balance simulator's average four-player round-15 reach fell from 91% to 64%.
- **Cause:** The number we matched was the flat rate at zero health. The weapon pick (`WeaponWorth.sustained_dps` with a
  health) counts whole shots: a pull that overkills wastes the rest, so a magazine of two is worth two zombies per
  cycle however hard it hits, and a longer reload costs it all the more.
- **Fix:** Match the kills a second against the round's health, not the flat rate (22 a pellet, 1.8 s reload gives
  the pump's), then run the simulator again. Documented in the game's `docs/research/balance-simulator.md`.
- **Check next time:** after changing a weapon's magazine or reload, run `tests/rules/test_sim_weapons.gd` before the
  long simulator run: it is the fast signal.
