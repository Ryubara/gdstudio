---
areas: [gameplay, tests]
---
# A bot's look asked the lamp list about every zombie and a think cost 4 to 6 ms

2026-11-02

- **Saw:** the decision-cost test of the bot host (Deadnight #225) measured p99 4.4 to 6.1 ms a think with 46
  zombies in the frame, against a 0.5 ms budget; with 3 or 4 zombies the same code took 50 microseconds, so the
  soak never showed it.
  A downed bot also still sent a walk command; a unit test on the downed case caught that one.
- **Cause:** the sight range follows the light, and the light question (`NightWorld.is_lit`) walks the list of
  lamps. The first look asked it for every zombie in the frame before the cheap angle and distance tests.
- **Fix:** cheap tests first (distance, then a dot product against the view instead of `atan2`), sort the candidates with
  the engine's sort on `(distance, index)` pairs, and ask the light only of the nearest few until the ray budget is
  spent: p99 0.29 ms. Measure a per-tick cost at the largest crowd the rules allow (the alive cap), not at the crowd a
  soak happens to have, and scale a wall-clock budget by how fast the runner runs a fixed piece of GDScript.
- **Docs:** Deadnight `docs/research/bots.md` (Server cost, "Measured on the built host").
