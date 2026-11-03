---
areas: [gameplay, tests]
---
# A bot fit chased the shopping while the model's boss night was a different fight

2026-11-03

- **Saw:** Rookie bots in teams reached round 9 to 10 where the simulator's weak players die in round 5 (Deadnight
  #767). The first causes found were real differences in the model's shopping: its players fill up with 6 magazines
  before a special round, and refuse a shotgun in the early rounds (a free hand is weighed against the quick melee at
  the round's zombie health, `NightSim._worth_taking`: 59 shotgun prizes shown at the crane in 40 nights, none taken).
  After the bots did both, the kit at the boss night matched (pistol only for 62 to 77% of bots, 78% in the model) and
  the boss night was still passed in 23 of 24 nights (the model: 27%).
- **Cause:** the model's loss is the boss: its `hurt_by` is 222 of 226 points a night from the headliner, and a loss
  needs about 5.5 blows landed. The bots took 2 to 3, because they killed it on the way in. Counting the headliner in the
  real server (hits by zone, seconds in each mode, first-hit range, time to kill) found a difference in the world, not
  the kit: 60% of the hits on the boss landed on its lens (the model: 20%), because the lens sits on the chest and a ray
  past it counts (`Hitbox.WEAK_SLACK`); aiming at the middle of the body hit it anyway (`weak_spot_rate` 0 still gave
  59%).
- **Fix:** read the cheap number that decides the fight before tuning anything: `bots_soak.tscn --max-round=6` is the
  first boss night in a minute or two a night, and the soak now prints the boss's zones, modes, range and time to kill
  and each round's blows by zombie type. A bot that is not going for the lens aims at the hips (`aims_off_weak_spot`),
  which took the Rookie's share of boss-night passes from 65% to 40% of 20 harness nights. Try a lever on a setting of
  the same checkout with `--tune field=value` instead of editing the code between runs.
- **Docs:** Deadnight `docs/research/bots.md#rookie-parity-767`.
