# Worker threads: warm what they share before they start

A GDScript game can run its simulation on `WorkerThreadPool` (Deadnight's balance cells do: one cell a worker, a group
task, `tests/rules/shipped_cells.gd`). The workers are safe while they only read. What is not safe is **the first use
of anything shared, started from several workers at once**: the engine does not make that first use thread safe for
you, and the result is not an error you can read but a silent death or a signal 11.

## What was first-used from the workers

Found in Deadnight #1149, where `ShippedCells` crashed the engine in CI (`handle_crash: Program crashed with signal 11`,
exit 134, no test failed) and on a Windows machine (the process vanishes, exit 127, no summary).

| First use | Why it races | Runs that died (a child Godot playing the 9 cells on 16 threads) |
| --- | --- | --- |
| A lazily filled `static var` (`MapRegistry._maps`: `if _maps.is_empty(): _maps.append(load(...))`) | two workers both see it empty and append to one array: `Parameter "mem" is null` in `cowdata.h`, or a segmentation fault | 18 of 30 with only this cold |
| The first load of a `.tres` whose script has not been instantiated yet (`ZombieTuning.shipped()`) | the engine's own first-use work runs on several threads at once; CI named this load just before the crash, and the `/root ... propagate_notification()` error beside it did not reproduce locally | 3 of 70 with only this cold |
| Weapon definitions, element definitions (`load()` through a lazy cache) | the same, per file | the existing `SimWeapons.warm()` covers the weapons; the elements were found by the probe below |
| Both cold (the cells as they were) | | 39 of 50; once `FATAL: Index p_index = 2 is out of bounds (size() = 1)` in `crane_play.gd`, not isolated |

The real suite showed it too: `test_xp_pace.gd` alone died in 4 of 7 runs before, and in none of 8 after.

## What to do

- **Play one night of every kind on the calling thread first**, then start the workers. This reaches the lazy statics,
  the resource loads and the scripts that a hand-listed warm-up would miss; the cost was 0.7 s for 9 cells
  (nine nights, in a suite that runs for 29 s on 16 threads).
- Do not fill a shared `static var` lazily on a path a worker can reach; fill it at first use on the main thread or put
  the whole check-and-append behind a `Mutex`.
- **Test it in a cold child process**, because the suites before yours load things and a check in the same process can
  pass without ever being able to fail. Deadnight's `test_shipped_cells_workers.gd` starts a child Godot
  (`shipped_cells_probe.gd`), snapshots `ResourceLoader.has_cached()` over every project resource before the workers run,
  and fails when the workers were first to load any file; a second case (`--cold`: the cells one worker at a time, no
  warm-up) must see the zombie tuning and the maps, which proves the probe can see a load.
- Reproduce a race of this kind in a loop of **child processes** (`OS.execute` or a shell loop, 30 to 40 runs), not
  by repeating the suite in one: the first use happens once a process. Count completed runs against exits, and give the
  rate before and after.

Lesson: [a worker crashed the engine on first use](../lessons/2026-11-04-workers-first-using-shared-state-crashed-the-engine.md).
