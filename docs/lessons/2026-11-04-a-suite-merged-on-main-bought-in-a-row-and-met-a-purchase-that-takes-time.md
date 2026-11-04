---
areas: [tests, gameplay]
---
# Suites that landed on main bought perks in a row and met a purchase that now takes 2.5 s

2026-11-04

- **Saw:** Deadnight #959 (a perk is drunk for 2.5 s before it is had; a buy meanwhile is `DRINKING`) went red after
  main gained the perk-limit suites (#913): `expected 4, read 0` in `test_perk_limit.gd`, `test_night_perk_limit.gd` and
  `test_perk_limit_online.gd`, then `Invalid access to 'limit' on a Dictionary` as a follow-on. The branch had
  already made its own suites drink down (`RulesFixture.buy`, `NightFixture.drink_down`); the new suites did not use
  them.
- **Cause:** the new suites buy four or six perks in a row and read the count at once, and one drove the balance
  simulator's `_shop` in round one (an active phase), where the simulator does not drink (it shops in breaks). A merge
  of main is textually clean when the new suites sit in other files, so only a run of the new files shows it. In the
  simulator case the first break is `rounds.intro_seconds` (not the settings' break), and a short break ends the
  shopping: 6 drinks take 15 s.
- **Fix:** tests, not the rules: each press drinks down the way the other suites do, the simulator test starts the
  night (a break) and gives the intro room for every drink, the online test waits for the server to be done drinking.
  The rule itself was right (a full-handed buy is refused before the limit), but the limit now also counts the bottle
  in the hand (`PerkPlay.held`) so the machine's card tells the full player so, and two tests hold the order and a spill.
- **Check for next time:** when a branch gives a purchase (or any action) a duration, grep `origin/main` for every
  suite that performs it after each `gds merge-main` (`rg "RulesAction.buy|_press_use|buy_at" game/tests`) and run
  those files, not only the ones the branch touched; put the "finish it" step in the shared fixture so a suite
  that lands later has one name to reach for.
- **Docs:** this lesson.
