---
areas: [net, backend, tests]
---
# Two reporters of one leave made the second answer an error, and an older test asserted the first

2026-11-05

- **Saw:** after the game server began telling the backend that a person's seat is empty (Deadnight #1177), the older
  end-of-night test `test_the_host_who_leaves_during_the_intermission_hands_the_reopened_lobby_on` failed on
  `assert_bool((await ann.api.leave(ann.lobby))["ok"]).is_true()`, though the host did leave.
- **Cause:** the same fact now had two reporters, the client's `leave` and the game server's `/left`, sent over two
  connections with no order between them. The test closed the socket and then called `leave`; the game server's report
  arrived first, so the backend answered the client's `leave` with `not_member`. The test had encoded "my request is
  the one that did it".
- **Fix:** both reporters stay, because each covers a path the other cannot (a button press that the game server cannot
  see, a closed tab that the client cannot send). The backend treats the second as a no-op that names the end state
  (`not_member`), and a test of a leave asserts that the player is out, accepting either answer.
- **Check for next time:** when a second source starts reporting a fact an existing request already carries, find the
  tests that assert the request's own answer, and make them assert the end state. Say in the docs which source covers
  which path, so nobody removes one as a duplicate.
- **Docs:** the game's `docs/research/platform-backend.md` (`POST /internal/matches/:id/left`).
