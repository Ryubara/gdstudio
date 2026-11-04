---
areas: [gameplay, net, tests]
---
# A hosted bot counted as a browser and cut the desktop crowd from 120 to 40

2026-11-04

- **Saw:** on a desktop, any night with a bot stood at most 40 dead (99 with the bots told they are not browsers), though
  the design says a desktop with no browser stands up to 120. Found by a profile run, not by a test.
- **Cause:** the join took one flag for "is this seat a browser": `OS.has_feature("web") if local else true`. A hosted
  bot is not `local`, so it fell into the remote branch, whose default is the safe one for a client that has not said what
  it is. A bot has no screen and no platform; the ceiling must follow the people. No test seated a bot on a desktop
  host, and the seat changes (a person takes a bot's seat, a bot inherits a leaver's) kept the old flag as well.
- **Fix:** a bot's seat is never registered in the crowd's table; a person who takes a bot's seat registers as a browser
  until it says otherwise; a bot that inherits a seat drops the leaver's flag. A table of "who counts" gets a test for
  every kind of seat (person local, person remote, bot) and every change of seat, not only the people.
- **Docs:** [Crowd budget](https://github.com/Ryubara/deadnight/blob/main/docs/research/crowd-budget.md) in the game
  (section "A bot is not a client").
