---
areas: [net, tests, gameplay]
---
# A player limit was a literal in many places, and a modulo hid the rows that were missing

2026-11-03

- **Saw:** raising a room from four seats to eight (deadnight #690). The limit lived in `NightHost.MAX_PLAYERS`,
  but also as `NightBots.SEATS`, `LookServer.SEATS`, a backend default and schema (`maxPlayers = 4`), three fallbacks in
  the lobby screen, `for seat in 4` in the HUD's free-seat search, a hue-gap test of four armband colours, a lobby test
  that filled a room with four people, and a test fixture that said "full" at four. Changing the constant alone
  changed none of them. Worse, some did not fail when the limit rose: `NightWorld.player_spawn(index)` is
  `markers[index % markers.size()]`, so the fifth player stood in the first one's spot with no error, and a bot's name
  was `NAMES[(id - 1) % 3]`, so seven bots would have shared three names.
- **Cause:** a number that means "how many seats" was copied wherever it was needed, and a wrap-around (`%` over a list)
  made data that was too short look fine. The tests that did notice (the full-room ones) only noticed the places that
  counted people; nothing counted the rows of data (spawn markers, colours, names) against the limit.
- **Fix:** one constant that the others are held equal to by a test (`test_night_bots.gd` pins `NightBots.SEATS`,
  `LookServer.SEATS` and `MatchSettings.MAX_BOTS` to `NightHost.MAX_PLAYERS`); every list indexed by seat is checked to
  be as long as the limit (`test_player_spawns.gd`, the armband colours, the bot names); a distinctness test that was written
  for four items (hue gap) is rewritten for the new count (a colour distance in Lab, since a white band has no hue).
  Run every suite that builds a room or a HUD (`net`, `rules`, `ui`, `night`, `world`), not only the ones that name the
  limit: fixtures hold the old number.
- **Check next time:** before changing a count, `grep` for the literal in code, tests and fixtures, and for every `%`
  over a list; after it, assert that each list indexed by that count has that many rows.
