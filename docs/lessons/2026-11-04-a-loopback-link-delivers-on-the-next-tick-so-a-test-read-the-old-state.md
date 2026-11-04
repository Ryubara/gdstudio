---
areas: [tests, net]
---
# A test ended a night through the rules and read the old state

2026-11-04

- **Saw:** a test that applied `set_downed` to the server's rules in a single-process night and asserted
  `night.state.over` straight away read `false` (and `end_camera` null); the same assertions passed after a tick.
- **Cause:** the events a rules action causes outside a step go to the client through the loopback link, which delivers
  on `pump()`, at the start of the next tick. Nothing is "applied to the client" at the moment the server changes.
- **Fix:** `broadcast` the events and run one tick (`NightFixture.run(night, 1)`) before asserting what the client
  knows; a capture script awaits a frame the same way. Over a real socket the same holds, so wait on the client's state
  (`_until`), never on the call.
- **Docs:** [Multiplayer: events reach a client only through its command loop](../godot/multiplayer.md).
