---
areas: [tests, gameplay]
---
# A bot test passed on a field the real frame does not carry

2026-11-03

- **Saw:** 20 GdUnit cases of the new bot play states passed, but the film of the bot read "AGGRESSIVE 300%" at 300 health
  and a bot with a health tonic would have judged itself healthy at 120 of 300.
- **Cause:** the brain read `max_health` from the frame's player entry. The test rig (`BotRig`) builds its own frame and
  I had put `max_health` in it, so every test saw the field; the real server frame (`NightServer`) carries only `health`.
  The field is in the events (`player_added`, `player_hurt`, `player_healed`) instead. A rig that writes the frame by hand
  can invent a key, and a test cannot tell.
- **Fix:** read what the server sends (the bot keeps `max_health` from those events), make the rig send the same event
  instead of the field, and look at one capture of the real night before reporting: the label on the film showed it.
- **Check next time:** before a brain reads a key, grep the server code that builds that frame or event for the key; a
  fake frame in a test gets only the keys the real one has.
- **Docs:** none beyond this page; the game's page `docs/research/bots.md` names where a bot reads its full health.
