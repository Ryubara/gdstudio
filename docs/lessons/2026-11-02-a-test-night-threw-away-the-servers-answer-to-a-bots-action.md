---
areas: [tests, gameplay]
---
# A bot's callout never reached the test, because the seated night dropped what `apply` returned

2026-11-02

- **Saw:** Deadnight #229: a bot sent a `say` action, the server accepted it, and no `bot_say` event was ever heard in a
  `SeatedNight`.
- **Cause:** `NightServer.apply` answers an action with its events (the game server broadcasts them); `SeatedNight._send`
  called it and discarded the answer, so a ping's mark or a line only ever existed on a real server.
- **Fix:** the seated night keeps the answers that are everyone's business (`bot_say`, `ping_placed`) and hears them with
  the next step's events, as a broadcast would. A new action that the server answers with an event needs the same.
- **Docs:** Deadnight `tests/night/seated_night.gd`.
