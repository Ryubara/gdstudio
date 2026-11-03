---
areas: [gameplay, tests]
---
# Three bots with rounds stood still 5 to 8 s with the boss in view because a person was aiming at it

2026-11-03

- **Saw:** the nightly soak's Hold cell (Deadnight #769): a holder with a pistol and rounds stood 5 to 8 s with a
  headliner at 6 to 8 m, no shot and no step. The soak's idle sample said `target_id: -1` with the boss believed and in
  sight, so it was not aim, ammo or the stance.
- **Cause:** kill courtesy (`BotCombat.courtesy_holds`) leaves a zombie 6 m or more off to a person who is aiming at it.
  The boss takes the whole team's rounds, so the person (the soak's stand-in, or anyone) aims at it for many seconds and
  the bots hold fire on it the whole time.
- **Fix:** the boss is never a person's alone (a test that offers the courtesy rule a headliner at 8 m with a person
  aiming at it, failing first). To find it, put what the bot decided (`target_id`, and the courtesy answer) in the idle
  sample next to what it could see, not only where it stood.
- **Docs:** [Hold and a boss](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md#hold-and-a-boss-769).
