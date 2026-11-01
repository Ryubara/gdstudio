# A test suite crashed the engine after printing PASSED

2026-11-01

- **Saw:** a GdUnit4 suite that bought a door printed PASSED, then the engine crashed.
- **Cause:** the door had started a navigation bake on a worker thread, and the suite freed the night while the bake was
  still running.
- **Fix:** a test that starts async work (a navigation bake, a thread, a resource load) waits for it before freeing its
  scene; give the fixture a `settle` helper that such suites call in `after_test`.
- **Docs:** [Zombie crowds](../godot/crowds.md); Deadnight `docs/lessons.md`.
