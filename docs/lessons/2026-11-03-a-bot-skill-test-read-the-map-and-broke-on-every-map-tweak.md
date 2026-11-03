---
areas: [tests, gameplay]
---
# A bot skill test read the map, and 20 added lamps broke it with no change to a bot

2026-11-03

- **Saw:** the maintainer's hand-placed map (20 more field lamps, Deadnight #719) failed `test_bot_bands.gd` on four
  checks with `main` at none: Regular head share 0.80 to 0.97, hit 0.56 to 0.77, shots 253 to 131 over the same seeds.
- **Cause:** the test measured a bot's aim and feet in a fight where the dead walked the lot to it, so where the dead
  came into view (cars, posts, lamps) was part of the number. The test comment said "open ground"; the field never was
  (rays west of home hit the car rows on both maps). Swapping the baked navigation meshes changed nothing (the fight
  does not read them); taking the new lamps out fixed two of three levels; shots at the dead 10 to 20 m west fell from
  51 of 79 to 5 of 22. Re-fitting the bands to the new map would break again on the next tweak.
- **Fix:** stage the dead (`SeatedNight.stage_the_dead`: each put once ahead of the bot, walking straight) so the
  route is fixed and the shipped map's solids still stand: `main` and the maintainer's map then read within 3 shots.
  Dodge needs the dead to reach the bot, which a bot that shoots never lets happen at any pace (0 blows, or a crowd
  with 1,583 on a Rookie), so it is read with the trigger up in a second, near fight (`hold_fire`) and has a band of
  its own.
- **Docs:** Deadnight `docs/research/bots.md`, "The bands test stages the dead (#783)". Check: a test that reads a
  rate off a bot in the real map is run once on the previous layout and once on the new one before its bands are set;
  if the two differ with no bot change, the route of the dead (or the thing measured) is fixed by the test, not
  re-fitted.
