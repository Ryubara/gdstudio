---
areas: [gameplay, tests]
---
# A bot was about to be given the zombie's health through the hit marker

2026-11-02

- **Saw:** wanting a "finish the wounded one" term in the target choice, the bot's own `zombie_damaged` events (the hit
  marker a person sees) were added to the allow-list; the allow-list test for dropped events failed.
- **Cause:** `zombie_damaged` carries the zombie's health left and its maximum, which the bot plan says a client never
  knows (bots research page, perception: "Never: a zombie's health"); the event was guessed to be harmless because a
  hit marker is on screen.
- **Fix:** reverted before any code used it. The target utility has no term for a zombie's health; the hurt terms are the
  bot's own and its teammates' health, which the frame shows. Read the dropped list in `test_bot_events.gd` before
  widening `BotEvents`.
- **Docs:** [bots research page, phase 3](https://github.com/Ryubara/deadnight/blob/main/docs/research/bots.md).
