---
areas: [tests, gameplay]
---
# A scene change reshuffled a bot night and a solo bot met round 3 with the revolver

2026-11-04

- **Saw:** a pull request that only removed three wall spots (markers and plaques, no collision) failed the second
  map's solo bot night on CI (seed 1: bought `door_side`, no weapon) and, after merging main, failed on a developer
  machine every time (seed 1 again: round 3, one down, 800 points unspent, revolver only). `origin/main` passed the same
  test 27 times out of 27 (Deadnight #910, #952).
- **Cause:** not the removed spots. The night is chaotic: three fewer nodes shift the first fight (kills at tick 800
  instead of 600), so the same seed plays a different night. That night showed a weakness that was always there: the
  team link rule (`BotErrands._link`) runs ahead of the shop list, so a solo bot with 540 points bought the second and
  third stairs (450 each) before the shotgun (540) and reached round 3 with the start revolver. The earlier flake
  (#890) was the same weakness, answered by a longer night.
- **Fix:** on a map whose bots buy the links as a team, a bot with only its start gun is offered nothing after the
  first gun it can pay for (`BotEconomy.candidates`), and the map's overlay names what its bots save for
  (`bot_saves_for`: the shotgun), so a link that costs less never puts the first gun off. The first gun now comes
  by 107 s on 12 of 14 seeds, and on all 14 within 225 s (it came at 140 s and later). The test's bar and seeds are unchanged.
- **Check:** a change that only moves scene content can move a seeded bot night: when such a test goes red on an
  unrelated change, reproduce on `origin/main` many times and on the branch, print the purchase log with ticks for
  both, and look for the choice the bot makes (what it buys first) before blaming the data or lengthening the run.
- **Docs:** Deadnight `docs/design/smallmap.md` ("Bots on the map"); see also
  [a solo night bought its weapon in one break](2026-11-03-a-solo-night-bought-its-weapon-in-one-break-and-missed-it-on-ci.md).
