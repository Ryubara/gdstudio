---
areas: [tests, godot]
---
# Cells run on worker threads crashed the engine on first use of shared state

2026-11-04

- **Saw:** CI `godot (4)` on a pull request that touched nothing near it: `handle_crash: Program crashed with signal 11`,
  exit 134, no test failed, after `Loading resource: res://gameplay/zombies/zombie_tuning_default.tres` and
  `ERROR: /root: The caller thread can't call the function propagate_notification() on this node` from two threads.
  Locally the same suite (`test_xp_pace.gd`) died silently, exit 127, in 4 of 7 runs; a child Godot playing the nine
  cells died in 39 of 50.
- **Cause:** the nine cells were started on `WorkerThreadPool` with only the weapon definitions loaded. The first night
  of each cell filled `MapRegistry._maps` (a lazy `static var`, `is_empty()` then `append`) from several workers at once
  (18 of 30 runs with only this cold), and the first load of the zombie tuning's resource ran on several workers (3 of
  70). The `/root ... propagate_notification()` error did not reproduce locally.
  The GDScript backtrace names a line of `SimSkill.named` that is not the cause.
- **Fix:** play one night of every cell on the calling thread before the workers start (`ShippedCells.warm`, 0.7 s of 29);
  a test runs the cells in a cold child Godot and fails when a worker is first to load any project file (it fails with the
  warm-up taken out). Completed runs: 40 of 40 child runs and 8 of 8 suite runs after, against 11 of 50 and 3 of 7 before.
- **Docs:** [Worker threads](../godot/worker-threads.md). Check for next time: before a job goes to `WorkerThreadPool`,
  list what its first run loads or fills (`ResourceLoader.has_cached` before and after one run, `static var`s with an
  `is_empty()` guard) and do that on the main thread.
