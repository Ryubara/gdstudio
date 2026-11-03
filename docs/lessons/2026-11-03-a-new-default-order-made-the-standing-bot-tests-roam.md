---
areas: [gameplay, tests]
---
# A new default stance for the bots turned the tests that stood still into tests of roaming

2026-11-03

- **Saw:** Deadnight #641 (orders: Roam by default). With the default moved from "follow the people" to "roam", eight
  suites that had passed for weeks failed: the bands (head share 0.16 against 0.30), a lone bot that never saw the zombie
  behind the wall, the errand turns (the bot that was nearer at the start was not nearer a minute on), the crawler
  hit rate, and the rig tests of the aim, where a bot shot nothing in 240 ticks.
- **Cause:** those tests never said "this bot stands and fights". They stood because a bot with no person near had
  nowhere to walk to, which was an accident of the old default. A roaming bot turns to where it walks (the view follows
  the legs), so it left the zombies behind its back and the cone; and one that walks changes who is "nearest" to a thing.
- **Fix:** a bot of the parts' tests is built with `BotProfile.follows = false` (`BotRig`, and `SeatedNight.stand_still`
  for a night); a test of following gives the order it measures (`SeatedNight.give_order(&"follow", 1, at)`) instead of
  leaning on the default. The golden hash did not move once the rig stood still.
- **Check for next time:** when the default behaviour of a bot changes, run every bot suite before writing the new
  tests, and make each old test say what it stands for (a stance, an order) in its set-up; a test that works because
  "nothing gave the bot a reason to move" is one change from failing.
- **Docs:** the game's `docs/research/bots.md` (Orders).
