---
areas: [gameplay, tests]
---
# The quick melee one-tapped the dead after round 1 because its sweep always crowned the blow

2026-11-03

- **Saw:** the maintainer: V "should not be one tapping zombies after round 1". The tables said the blow was 40 against
  50 health (two blows on round 1), the unit test agreed (two blows), and the balance simulator valued it at 40
  (Deadnight #897).
- **Cause:** the real blow was 60 on every hit. A melee sweep leaves the eye (1.55 m) with a 0.4 m thickness and a
  walker's head sphere is at 1.62 m, so the zone was the head at every reach (0.7 to 1.5 m) and every aim, and the head
  multiplier (x1.5) turned 40 into 60: one blow on rounds 1 and 2 (50 and 58 health). The tables, the unit test (a
  stub target at chest height) and the simulator (the body zone, or a zone rolled from a head rate) never met the
  sweep's real zone.
- **Fix:** measure the damage a real attack deals from the real night first (a probe through the real key, sweep, hit
  zones and rules, printing zone, damage and health left per round), not the table. Then make the number honest (the
  quick melee is 50 in every zone, so the head cannot hide a multiplier) and add a hits-to-kill-per-round table to the
  design page with a test through the real damage path (real eye height, fitted zones, the rules' health for the round)
  at several reaches and aim heights, so a retune of the health curve fails it. Every attack that is not a gun gets the
  same table.
- **Docs:** the game's `docs/design/weapons.md#hits-to-kill-by-round` and `docs/research/balance-simulator.md`.
