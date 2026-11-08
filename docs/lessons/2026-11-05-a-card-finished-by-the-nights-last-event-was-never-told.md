---
areas: [net, gameplay, tests]
---
# A challenge finished by the night's last event was counted and never told to a client

2026-11-05

- **Saw:** Deadnight #1172's online test for *Dead on arrival*: the server's board held the stat (`deaths:round_one` 1)
  and the night was over, but no client ever heard `challenge_done` for the seat (`ChallengeAward._out` still held 14
  events 6 s later). The back rooms case of #1074 had passed, so the gap showed only for a night that ended with the
  clients down and the last event making the finish.
- **Cause:** `NightServer.step` hands the challenge events out (`challenges.take_events()`) in the live step and in
  `apply`, but not in `_step_over`, the step that runs once the night is over. What `game_over` finishes waited for
  an `apply` (a look or arrival packet from a client), which a client whose player is down stops sending.
- **Fix:** `_step_over` drains `challenges.take_events()` too. Check for next time: a stat that is counted at or after
  `game_over` (a night's end, a death) is tested as *told to every client* (`challenge_done` heard), not only as a
  number on the board; the number was right while the client heard nothing.
- **Docs:** [Multiplayer](../engines/godot/multiplayer.md#what-the-last-event-of-a-night-makes).
