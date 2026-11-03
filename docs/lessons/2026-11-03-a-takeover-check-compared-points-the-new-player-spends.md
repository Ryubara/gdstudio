---
areas: [tests, gameplay]
---
# A seat-takeover check failed because the person who took the seat spent its points

2026-11-03

- **Saw:** the ten-minute room soak (Deadnight #230) failed once with "the person at seat 4 did not get the bot's seat as
  it stood". The seat was handed over correctly.
- **Cause:** the check compared the seat's points before and after the takeover, 120 ticks apart. The person in the
  soak is an autopilot client, which buys at once, so its points were lower than the bot's.
- **Fix:** compare what the new player cannot change in the settle window: the body is the same object, the seat is no
  longer a bot's, kills and downs are not lower. Points are compared only on the tick of the handover, before anyone has
  acted (the unit test does that). A check on a stand-in for a person must assume the stand-in acts.
- **Docs:** the game's `docs/research/bots.md` (the room soak) and `docs/research/testing-multiplayer.md`.
