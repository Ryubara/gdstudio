---
areas: [gameplay, tests]
---
# A pack parked at a downed body walked away to the bot

2026-11-03

- **Saw:** Deadnight #646: a scenario put eight of the dead round a downed person and a bot 15 m off; within seconds
  the pack was streaming toward the bot and the body was clear, so "the dead are at the body" was never true when the
  bot decided, and a first assertion that the hold began with the dead gone from the body passed or failed by chance.
- **Cause:** `ZombieSim` is given only the players who stand (`targets` leave out the downed), so the dead near a body
  walk to the nearest player who is up, which is the reviver. A body draws nobody. What threatens a revive is the dead that
  are coming for the reviver, wherever they started.
- **Fix:** the scenario's checks are outcomes about the bot (a flare fired by it, burst far from every player, the dead
  come nearer the flare, no blow on the bot during the hold, the person raised; the control without the flare gun does
  not raise them), and the risk check treats the dead that arrive inside its window, not the ones near the body.
- **Check for next time:** before a test parks the dead somewhere, ask whom the simulation lets them chase; assert on
  what the dead do to the thing under test, not on where they were put.
- **Docs:** the game's `docs/research/flare-lure.md#bots-fire-it-646`.
