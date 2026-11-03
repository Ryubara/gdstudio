---
areas: [gameplay, tests]
---
# The bots kept their own copy of the headliner's health and a tuning change left it behind

2026-11-03

- **Saw:** Deadnight #688 raised the headliner's `health_multiplier` from 13 to 16.25 in `default_tuning.tres`. The
  rules suite passed, but `test_bot_revive_risk.gd > test_the_numbers_are_the_games` failed: `BotReviveRisk.HEALTH_BY_LOOK`
  still said 13.0, so the bots would have judged a revive against a boss a quarter weaker than the real one.
- **Cause:** a bot table mirrors the roster (`HEALTH_BY_LOOK`, `SPEED_BY_LOOK`) as constants, held in step by a test,
  not by reading the tuning. Searching the tuning file for the number found one place; the copy had to be found by
  searching the code for the old value and for the type's id.
- **Fix:** change the copy with the tuning, in the same commit, and run the bots' folder (`tests/bots`) as well as the
  rules' when a roster number moves.
- **Check for next time:** before changing a roster, weapon or round number, grep the game for the old value and the
  type's id (`headliner`, `13.0`) and run the test folder of every file that mentions them.
- **Docs:** the game's `docs/design/rounds.md#the-bosses-25-tougher-688`.
