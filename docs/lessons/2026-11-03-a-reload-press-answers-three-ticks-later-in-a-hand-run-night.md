---
areas: [tests, gameplay]
---
# A reload press read on the same tick answered nothing

2026-11-03

- **Saw:** Deadnight #687: four night tests sent `reload = true` with `NightFixture.run(night, 1, command)` and read the
  `reload_started` or `shock_burst` event at once; the list was empty (`Out of bounds get index '0'`).
- **Cause:** a command goes through the loopback link and is used by the server on a later tick, and a pressed edge is
  used once; the event comes back through the link after that. One tick is not enough, however the rest of the test is
  written.
- **Fix:** press, then run three more neutral ticks before reading (`_reload(night)` in `test_night_perks.gd`); the
  neighbouring suite (`test_night_commands.gd`) already did the same.
- **Check for next time:** a test of a pressed key in the real night runs the press and three ticks, and reads the events
  after them; copy the nearest suite's way of pressing before writing a new one.
- **Docs:** [Test speed](../godot/test-speed.md#what-hand-stepping-needs).
