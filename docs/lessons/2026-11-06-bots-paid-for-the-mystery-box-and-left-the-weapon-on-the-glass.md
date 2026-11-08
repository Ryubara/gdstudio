---
areas: [gameplay, tests]
---
# Bots paid for the mystery box and left the weapon on the glass

2026-11-06

- **Saw:** the maintainer, playing: bots used the prize crane but never took the weapon, rolling again and again until
  they left (Deadnight #1322). In 46 hosted-bot offers over
  16 bot-nights, 12 were taken: a Rookie with the pistol only took 2 of 14 and rolled 16 times.
- **Cause:** two questions that should be one. The bot paid for a play when *any one* of the seventeen prizes was
  worth taking (`BotEconomy._crane`), then took only the prize it was dealt, and only when that one beat its hands by
  1.5 times (`BotErrands._crane_wait`). The draw is blind and most prizes fail the second test, so 30 of 34 offers
  were left on purpose, and nothing recorded a miss, so the bot paid again. A second fault sat behind it: the wait
  never walked the bot back to the glass, so a bot shoved off it by a teammate stood out of reach of the press for
  the whole window. The test of the errand was named "plays the crane and takes the prize it wants" and asserted
  only that a play was bought and nothing errored.
- **Fix:** Deadnight #1322. The bot pays only when the weighted share of the draw it would take is at least
  `BotProfile.crane_min_odds`, lets a prize go at most once a round with the same hands, and walks back to its stand
  while a play runs. A suite on the real server step (`test_bot_crane.gd`) fails on the old code. The same 16
  bot-nights after: 21 plays (from 51), 14 prizes taken (from 12), 5 left on the glass (from 34), 11,550 points into
  plays (from 28,050).
- **Check next time:** when a decision to spend and a decision to use what was bought are made in two places, make
  the first price in the chance the second says yes, and count paid, offered and used per bot in a real night
  before and after (`bots_crane_soak.tscn`). A test whose name promises an outcome asserts the outcome (the weapon in
  the arms), not the purchase. Whatever a bot waits for, it also walks back to.
- **Docs:** Deadnight's `docs/research/mystery-box.md`, section "The hosted bots at the crane (#1322)".
