---
areas: [gameplay, tests]
---
# A scenario that took a bot's grenades away got them back at the round start

2026-11-03

- **Saw:** Deadnight #646: the flare capture set `beliefs.grenades = 0` on the bot, and at 5.4 s four of the eight dead
  at the body died together. The bot had thrown a grenade; the flare was never fired and the scene proved nothing. The
  scenario test, which set the same belief a moment later, was right.
- **Cause:** a bot's grenade count is a belief the server corrects (`grenade_count_changed`), and the round start refills
  it. The capture set the belief before `skip_break`, so the round-start event put the two grenades back.
- **Fix:** set the belief after the round has started (and the bots have heard it), as `SeatedNight.start_round()` and the
  scenario test do; a scene that needs a bot without grenades checks the first `zombie_removed` for a blast.
- **Check for next time:** a scenario that takes something away from a bot (grenades, ammunition, a weapon) does it after
  the events that refill it, and the proof of the scene is the thing it was built to show (here: a `lure_started` from
  the bot), not that the night ended well.
- **Docs:** the game's `docs/research/bots.md` (phase 5, part 3).
