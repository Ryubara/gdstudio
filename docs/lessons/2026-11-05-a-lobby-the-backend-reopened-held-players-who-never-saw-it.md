---
areas: [net, backend]
---
# A lobby the backend reopened held players who never saw it, and every create said "you are in another night"

2026-11-05

- **Saw:** the maintainer left a match and tried to join another: "it says they're already in an existing night". Then:
  "Why aren't lobbies immediately disbanded and we clear player state whenever the lobby is empty? The lobby I left had
  bots in it" (Deadnight #1177). The words are the backend's `already_in_lobby`.
- **Cause:** three, found by writing the failing tests first over a real game server and the real backend, and none of
  them the issue's guess. (1) A finished night reopened its lobby and put every present user back in the "one open
  lobby per user" index, an entry the player never made. A player who went to the menu, or whose screen gave up
  waiting after ten seconds, or whose tab was closed, never read that lobby, so the index held them until the ten-minute
  idle timer. A solo night with bots is the lobby only its leaver is in, so nothing else dropped it (hence the bots in
  the report). (2) The Esc menu's "Leave night" popped the screen and never said `leave`, while the end board's Leave
  did: two buttons for one act. (3) Nothing told the backend a seat in a started night was empty, so a closed tab stayed
  in the member list of a night with others in it. What was **not** the cause: a room with only bots did end at once
  and tell the backend, and leaving by the button or closing the tab, then creating, joining or quick-joining, already
  worked; the hypothesis in the issue was the one thing the tests ruled out.
- **Fix:** a refusal for being "in" somewhere is only as good as every way out of it, and the player cannot see most of
  them, so the rule became a move: a player is in one lobby, open or started, and create, join and quick join take
  them out of the one they were in (no `already_in_lobby` at all). A lobby with no person is gone at once (a member who
  leaves, moves, or whose seat the game server reports empty with `POST /internal/matches/:id/left`); a reopened lobby
  nobody reads within a minute is dropped; both exits of a night say `leave`. The idle timer stays only as the backstop.
- **Check for next time:** for any "you are already in X" refusal, list every way the system puts a player into X
  (not only the ones the player does: a reopen, a rejoin, an adopted seat) and every way out of it from the player's
  view (the button, the menu, a closed tab, a dropped connection, a night that ended, an Activity that closed), and
  give each pair a test over the real stack, with the bots in the room. Prefer an action that moves the player over a
  refusal that holds them. When the issue names a suspect, write the failing test for each suspect and keep the ones
  that fail: here two of the three real causes were not in the issue, and the named one was innocent. Two buttons that
  mean "leave" are one function.
- **Docs:** the game's `docs/design/lobby.md#leaving-and-moving-every-state-and-what-ends-it` (every state of a lobby
  and a player, and what ends it) and `docs/research/platform-backend.md#lobby-and-match-lifecycle`.
