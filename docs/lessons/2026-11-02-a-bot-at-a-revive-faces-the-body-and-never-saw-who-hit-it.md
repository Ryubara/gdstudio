---
areas: [gameplay, tests]
---
# A bot holding a revive never let go under blows, because it only counted the zombies it could see

2026-11-02

- **Saw:** Deadnight #229, scenario 6: two zombies hit a bot while it held the revive, its health went 100 to 45, and
  the abort rule (more than one attacker on it and 20 health lost in a second) never fired.
- **Cause:** the rule counted the believed zombies within 2.5 m, and a bot at a revive faces the body, so the ones at
  its back were out of its view cone and never believed; they were only *heard* (`BotBeliefs.heard`).
- **Fix:** the count of zombies on the bot is the larger of the believed ones within 2.5 m and the ones heard very near;
  scenario 6 hits the bot with real zombies and asserts the abort, the release one tick later, and the retry.
- **Docs:** Deadnight `docs/research/bots.md`, phase 5 ("What shipped in part 1").
