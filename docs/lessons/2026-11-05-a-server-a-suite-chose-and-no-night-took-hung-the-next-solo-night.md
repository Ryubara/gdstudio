---
areas: [tests, godot-ui]
---
# A server one suite chose and no night took hung the first test of a later suite for five minutes

2026-11-05

- **Saw:** `test_night_menu` > `test_escape_opens_and_closes_the_menu` ran into GdUnit's "Test timed out after 5min"
  on a pull request that added a lobby suite; the other twelve tests of the suite passed in under two seconds each. The
  log had one line before the silence: `Socket error: 111` (connection refused). Passed alone and on `main`.
- **Cause:** `NightScreen.join_url` (and `join_ticket`, `join_map`, `join_as_bot`) are statics that a lobby's Start
  fills and a night takes once, when it opens. The new suite stubbed `LobbyScreen.opener` and called Start, so nothing
  opened a night and the statics stayed set; the next solo night joined a server that was not there and never said
  `ready_to_play`, and `await screen.night.ready_to_play` has no timeout. Only the first test met it: opening a night
  takes the statics.
- **Fix:** a suite that opens a solo night forgets the join first (`RouterFixture.forget_join()` in `before_test`), and
  a suite that fills it clears it in `after_test`. Proof of the mechanism: a one-line suite that sets `join_url` ahead
  of `test_night_menu` timed out (exit 124) before and ran 14 of 14 after.
- **Check:** a test that hangs for the full limit, on its first test only, after another suite, has waited on
  something an earlier suite left half done: read the one log line before the silence, then list the statics the flow
  it stubbed fills. A stub that swallows the step which would consume a static leaves the static behind.
- **Docs:** the game's `docs/research/input-tests.md`, "A server chosen and never taken hangs the next solo night".
