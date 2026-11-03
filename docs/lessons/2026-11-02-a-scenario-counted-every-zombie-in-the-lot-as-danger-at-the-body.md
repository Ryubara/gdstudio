---
areas: [tests, gameplay]
---
# A "no zombie alive when the hold begins" check counted the two at a gate sixty metres away

2026-11-02

- **Saw:** Deadnight #229, scenario 5: the bot cleared the three zombies at the body and began the hold, and the test
  failed with "2 standing" at the start of the hold.
- **Cause:** the check read `ZombieSim.standing_count()`, every zombie of the round, and the round had sent two more that
  stood tearing boards at a gate 60 m off; the bot was right to start.
- **Fix:** count the zombies standing within 14 m of the body (`_standing_near`), and put the pack where the scenario
  says so; a scenario's assertion names the zombies it is about, never the whole lot.
- **Docs:** Deadnight `tests/night/test_bot_revive.gd`.
