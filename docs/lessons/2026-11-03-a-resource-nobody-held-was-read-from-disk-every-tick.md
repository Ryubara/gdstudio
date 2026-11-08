---
areas: [godot, gameplay, tests]
---
# A resource nobody held was read from disk on every tick

2026-11-03

- **Saw:** Deadnight's `test_bot_server_cost.gd` (three bots, 40 zombies, under 5% of a 60 Hz tick) failed on `main`
  at 1.3 to 1.5 ms mean against 0.65 to 0.8 ms two days before, on a machine that was no busier. The bots' think
  numbers (`bots_move_soak.tscn`) had not moved, so the cost was elsewhere.
- **Cause:** a fix gave a bot with an empty gun the quick melee, and the bot's motor asked
  `WeaponCatalog.quick_melee().melee_range` on every tick it had a target. `get_def` is a `load()` of a `.tres`; the
  definition was held by nobody until the server's first quick melee, so the resource was freed after each call and
  the next call parsed the file again: 797 microseconds a call unheld, 2.7 held. Found by commit bisection (a run is
  ten seconds), then by timing each part of the bot's tick: the motor's 95th percentile was 1,036 microseconds, every
  other part under 250.
- **Fix:** the motor reads the reach once (`_quick_reach`). Cost 0.65 to 0.7 ms, the 95th percentile 1.0 ms. A test
  checks the strike and the cached value.
- **Check for next time:** a number read from a catalogue resource in code that runs every tick is read once and kept;
  a cost test that regresses is bisected by commit on the same machine in the same session, and its parts timed,
  before its budget is touched.
- **Docs:** [First-use hitches](../engines/godot/first-use-hitches.md#what-the-engine-does).
