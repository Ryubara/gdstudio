---
areas: [net, tests]
---
# The join notice said PLAYER 3 because the name arrived after the join

2026-11-02

- **Saw:** after player names (Deadnight #542) met the lobby tests, `test_two_players_meet_the_host_starts_and_a_third_joins_mid_match`
  waited for the notice `PLAYER 3 LEFT` and never saw it. The notice `PLAYER 3 JOINED` did show, so it looked like the
  leave event was lost.
- **Cause:** the server sent `player_added` and then `player_named` in one tick. The HUD's "joined" notice is made
  when `player_added` arrives, so it read the placeholder; by the time the player left, the name had arrived and the
  notice said `CY LEFT`. The test had been written before names existed and asserted the placeholder. The product
  was inconsistent, not a lost event.
- **Fix:** send an event that names a thing before the event that announces it (`NightHost._name_seat` before the
  `JOIN`), so the first notice already reads `CY JOINED`; the test asserts the names. When a test waits for a string
  that never appears, print what the notice list did contain before suspecting the event path.
- **Check next time:** a change that adds data to an existing event flow (a name, a look) changes every text built
  from the earlier event; list those texts and their tests, and order the events so no text is built from a
  placeholder.
