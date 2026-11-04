---
areas: [tests, godot, ci]
---
# A capture script's const preload kept the whole lot scene alive at exit

2026-11-03

- **Saw:** Deadnight #837 (wall weapons as silhouettes). Every test passed, and CI shard 6 still failed with
  `ObjectDB instances were leaked at exit` and `resources still in use`, naming the lot scene's scripts and statics.
  Main's shard 6 was clean. It never reproduced locally in about 15 runs.
- **Cause:** three older capture scripts (`door_stand_mesh.gd`, `zombie_chase.gd`, `zombie_door.gd`) held the lot
  scene in `const LOT := preload("res://...tscn")`. The test scan loads every script under `tests/` and keeps them
  loaded to the end of the run, so each const kept the scene, the scripts it uses and their statics in use at exit. The
  leak appeared only when the branch added a script and a material to that scene. Narrowing, by CI runs that each
  excluded one folder: it needed the `captures` or `tours` folder in the run, and removing the branch's own suite or
  its two new capture scripts did not clear it.
- **Fix:** the three scripts keep the scene path as a `const` string and call `load()` inside the function that runs.
  Shard 6 passed on the next run. Narrowing by bisecting folders and scripts in a temporary CI step took five pushes;
  a local grep for `preload(".*\.tscn")` under `tests/` finds the candidates in seconds.
- **Check for next time:** a test or capture script never `preload`s a scene or a heavy resource into a `const`: the
  script stays loaded for the whole run, and so does everything it names. Use `load()` where it runs. When a shard
  leaks and nothing locally does, list the `preload` lines of the scripts in the folders the shard scans before
  bisecting in CI.
- **Docs:** related: [a test handler that named its
  night](2026-11-02-a-test-handler-that-names-its-night-leaked-the-whole-bot-code.md) and [a run that printed leaks no
  test reported](2026-11-01-a-gdunit4-run-printed-leaks-at-exit-that-no-test-reported.md).
