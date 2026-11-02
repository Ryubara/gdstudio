---
areas: [tests, net]
---
# A bad-network bots test failed once on a loaded runner after waiting 8 wall-clock seconds

2026-11-02

- **Saw:** Deadnight's `test_two_bots_on_a_bad_network_stay_with_the_server_and_settle_when_they_stop` failed once in CI
  (`Expecting 'true' but is 'false'` at the settle check, 28 s in). The same run printed 484 and 210 corrections for the
  two bots where a quiet machine prints about 50 and 40. It never failed locally, alone or with four copies at once.
- **Cause:** two clocks in one test. The game (server, prediction, reconciler) runs in physics frames; the test's
  `LinkConditioner`s held packets for real milliseconds (`WebSocketLink` read `Time.get_ticks_usec`), and the test waited
  20 s and 8 s of wall time. A runner that gets fewer frames a second plays fewer frames of the same wall-time network
  and has fewer frames to settle in, so what the test saw depended on the machine, not on the code.
- **Fix:** one clock. `WebSocketLink.clock` (a Callable, the real clock when empty) is given the physics frame count
  over the tick rate by the test, and every wait counts physics frames. The same 20 s of network is then the same frames
  at any speed: with each frame slowed by 0, 40 and 100 ms the run printed the same worst gap (1.12 to 1.17 m), the
  same corrections (41 to 53) and a round trip of 234 to 250 ms; before, 100 ms per frame moved the round trip to 382
  ms and the corrections to 76.
- **Check for next time:** a test that mixes a network or timer in real milliseconds with a loop in frames is two
  tests on one clock too many; give the real-time part an injectable clock and drive it from the frame count, then
  slow every frame (`OS.delay_msec`) to prove the numbers do not move. A wait that counts seconds for something that
  happens in frames is a flake waiting for a slow runner.
- **Docs:** [Test speed](../godot/test-speed.md), and the game's `docs/research/testing-multiplayer.md`.
