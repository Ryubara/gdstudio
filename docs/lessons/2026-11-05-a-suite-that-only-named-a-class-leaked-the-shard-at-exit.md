---
areas: [tests, ci, godot]
---
# A shard leaked 996 objects at exit with every test green, by the mix of suites it held

2026-11-05

- **Saw:** Deadnight #1231. `godot (1)` failed five unrelated pull requests with `996` to `1042 ObjectDB instances were
  leaked at exit` and `432 resources still in use` (scripts, fonts, textures, audio banks), every test passing. Main's
  shards passed their leak check; a pull request's new test file moved the split and the leak came and went with
  merges of main. Two
  guesses did not hold: a named suite (it runs in clean shards), and a fix that landed in between (#1234 does not touch
  it).
- **Cause:** a suite that names a class (`HeldWeapon`, the lot's silhouettes) makes Godot read that class's scripts as
  its dependencies, and a script that nothing loads as itself is still in use at exit with everything it reaches.
  `test_recut_skin.gd` leaked 243 objects alone and `test_drive_in_greybox.gd` 257, on Windows, on `main`; in the shard
  they added up to the 996, and 13 other suites (player, lobby, menu) that run first load the scripts properly and
  cure it. Every test case of the suite leaked the same count: the suite's script, not a test.
- **Find it:** the shard's exact list run locally with `--verbose` (it reproduced on Windows, no Linux needed); bisect
  by chunks (four runs in parallel), then each suite alone, then one file per test case, then a ten-line `-s` probe
  that loads one script and quits (a sweep of all 582 game scripts: six leak alone). A run that goes quiet for 25
  minutes on a loaded machine was parallel net suites on the same ports: run one, log to a file.
- **Fix:** CI runs the tests through a copy of GdUnit's command line tool that first loads every game script as itself,
  in name order (`tools/ci/warm_GdUnitCmdTool.gd`, `ScriptWarmup`): a five-suite list went from 911 objects to none with
  the same 55 cases, a few seconds a shard. The wrapper's file name keeps `GdUnitCmdTool.gd` (GdUnit finds its
  arguments after the argument that names it). A test runs the two suites in a child Godot through it and fails on any
  leak line, and the shard self-test fails if the workflow goes back to the plain tool. The leak check is unchanged.
- **Check for next time:** a leak that follows the shard and not the pull request is a load-order fact, not a
  regression: run each suite alone (`-a <suite>`) before reading any log, and a suite that leaks alone is the
  cause. Main's green shards were not proof of anything else: they held the leaking suites in a mix that cures them
  (shard 3 of runs 42011482212 and 42016360272), so check which suites a green run held before saying a leak is new.
- **Docs:** [Leaks at exit in a GdUnit run](../engines/godot/test-exit-leaks.md#a-suite-that-only-names-a-class); Deadnight
  `docs/research/test-exit-leaks.md`.
