---
areas: [gameplay, tests]
---
# A bot's hit rate stayed at 0.9 whatever its aim noise, until the shots were counted by range

2026-11-02

- **Saw:** calibrating three bot skills to the balance simulator's hit rates (0.45, 0.65, 0.82), the measured rate was
  0.9 to 0.95 for every setting of the tracking noise, and 0.7 to 0.8 even with a very loose trigger.
- **Cause:** a bot that fires only when its view is inside the hit cone hits nearly every shot it fires, and most of its
  shots were at point blank (it let the dead come to it), where the body is so wide that any aim lands. Noise only
  delays the trigger; it does not make misses.
- **Fix:** read the skill from the shots at 5 to 20 m only (`CombatProbe.range_hit_rate`), and make misses with the
  trigger: `fire_slop` (fire when the view is within several times the cone) and large tracking error, tuned per profile
  by a lab run of six seeds (`tests/night/test_bot_bands.gd`). The same lab showed the dodge needs a retreat margin of
  about 1 m, not the 5 to 9 m of the design table (those gave 0.7 to 0.8, stronger than the strong level).
- **Docs:** [bots research page, phase 3](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md).
