---
areas: [gameplay, godot]
---
# A grid that allocated every step, and a replacement hash table that was four times slower

2026-11-03

- **Saw:** the performance review of Deadnight #907 found `ZombieSim._separate` making an `Array` and a hash node for
  every occupied cell of its grid 30 times a second, and `zombies.values()` copies in the step (#933). My first
  replacement, a hash table in packed arrays written in GDScript, held 0 bytes but took 2.3 ms a step spread over
  30 m, against 0.56 ms for the old pass.
- **Cause:** allocation does not show in a time on a shared machine, and GDScript is slow where the engine is not: a
  probe loop and a function call per lookup cost more than the engine's native `Dictionary.get`, and there were as many
  lookups (nine for each lonely zombie).
- **Fix:** no table: one `int` per zombie (`cell key * 65536 + index`) in a `PackedInt64Array` the engine sorts, and
  three `bsearch` calls per zombie for the three columns of cells it reads. Same sums in the same order, so the
  positions are bit for bit the old ones (the old pass kept in the tests as the oracle, with a mutation that reorders
  the columns failing it). 6,224 B held to 0; `sim.separate` 385 to 334 us spread, 1,365 to 1,170 us piled.
- **Check for next time:** measure the replacement in the same bench as the original before writing the tests, in
  bytes held and in time, both arms interleaved; a loop of your own over a hot path has to beat a native call, and when
  floats are summed the order of the sum is part of the behaviour.
- **Docs:** [Performance review](../engines/godot/performance-review.md), counting allocations.
