---
areas: [gameplay]
---
# Per-line cooldowns of 20 to 60 s still let a bot say 1.4 lines in ten seconds

2026-11-02

- **Saw:** Deadnight #229: the callout test, a bot in every kind of trouble at once for 15 minutes, counted 1.39 lines
  per ten seconds against the done line "under one".
- **Cause:** twelve lines each with its own cooldown, and a short gap (5 s) before an urgent one, add up: the cooldowns
  limit each line, not the bot.
- **Fix:** a window as well (`BotCallouts.WINDOW_LINES` lines in `WINDOW` seconds), so the rate is bounded by
  construction (0.8 per ten seconds), and the test holds the worst case, not a typical night.
- **Docs:** Deadnight `docs/research/bots.md`, phase 5 part 2.
