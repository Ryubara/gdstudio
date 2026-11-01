# Simulated players that never vary make every night end in the same round

2026-11-01

- **Saw:** the first balance runs had 100% of nights reaching round 11 and 0% reaching round 12, for every seed: a
  cliff that looks like a wall and says nothing about balance.
- **Cause:** the modelled players had fixed skill, and the rules are deterministic for a seed, so only the zombie rolls
  varied.
- **Fix:** each night draws its own skill from the level's average with a spread (20%), so a level is a spread of
  nights. Measure difficulty as how close a round came to downing someone (lowest health reached), not damage taken,
  which is zero in most rounds and then everything.
- **Docs:** Deadnight `docs/design/rounds.md` ("The balance simulator").
