---
areas: [gameplay, tests]
---
# A solo night had one fixed seed, so the prize crane rolled the same prizes every night

2026-11-03

- **Saw:** Players said the crane gave the shotgun first too often and not every weapon (Deadnight #685, after #461
  "every weapon in the crane" was closed). The pool held all eight weapons and 10,000 first rolls from random seeds
  matched the weights.
- **Cause:** The menu's Solo started every night from the constant `Night.SEED`, so every stream of the night (the
  crane's included) was the same each time: for a buyer with the revolver the first eight plays were shotgun, rifle,
  SMG, rifle, flare gun, shotgun, SMG, flare gun. The odds test drew from consecutive seeds 0..N, so it checked the
  dice and never the seed the game starts a night with. A server drew a fresh seed, so only solo play showed it.
- **Fix:** A solo night draws a fresh seed (`NightScreen.start_seed = -1`, `Night.fresh_seed()`); benches that must
  repeat set `Night.SEED`. The test draws its 10,000 first rolls from the seed the screen would take, and failed first
  with the shotgun in 10,000 of 10,000. A check for a chance-based feature: find the seed the player's route really
  uses and put it in the test, not a seed the test makes up; and look at a fixed seed constant in any route a person
  plays.
- **Docs:** Deadnight `docs/research/mystery-box.md` (the first roll was always the shotgun) and
  `docs/design/weapons.md` (the roster).
