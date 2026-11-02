---
areas: [tests, godot]
---
# A threaded load in the dummy renderer left one mesh leaked at exit, once in a few dozen runs

2026-11-02

- **Saw:** Deadnight #603 and #608. Shard 1 of CI passed every case and then failed the leak gate on
  `1 RID allocations of type 'N13RendererDummy9DummyMeshE' were leaked at exit`, on two runs of one tree (and once
  more on its re-run, which passed). It was taken for a result of the new `stage_the_dead` in a test; twelve runs of that
  test and of the rules tests before it, here, were clean.
- **Cause:** the first failing log, searched from the top and not the end, had `ERROR: Initializing already initialized
  RID` and `Parameter "m" is null` in the dummy `mesh_storage.h` while a night's warm-up staged its zombie views
  (`night_warmup.gd`, `_stage_row`). The warm-up loads every model with `ResourceLoader.load_threaded_request`, and the
  loader's threads build meshes in the dummy renderer's storage at the same time as the main thread does: a race
  that is rare, silent most of the time, and leaves a mesh RID behind.
- **Fix:** a headless run loads on the main thread (`NightWarmup.loads_in_threads()` is false there); the displayed game
  still loads in threads. Found by reading the whole log for the first engine `ERROR`, not by guessing from the last
  suite or the last change.
- **Check for next time:** a leak at exit with passing tests: search the full log for the first line that starts with
  `ERROR:` or `SCRIPT ERROR:` before blaming the newest test; a mesh made from a thread in a headless run is a race.
- **Docs:** [The headless renderer](../godot/headless-renderer.md).
