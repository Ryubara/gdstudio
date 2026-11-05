# Leaks at exit in a GdUnit run: what a folder scan loads, and how to find the script

A GdUnit run that passes every test can still fail CI's `leaked at exit|still in use` gate. Besides the audio and
lambda causes ([Audio](audio.md#leaks-at-exit-in-a-test-run)), there is one that depends on **which scripts the
runner loads, and in what order**.

## A folder scan loads every script in the folder, in the filesystem's order

`GdUnitCmdTool -a res://tests/art` opens every `.gd` file under the folder to ask whether it extends
`GdUnitTestSuite`. The scanner skips a script only when it has a `class_name` and extends a Godot class (it reads the
global class list); a dev tool without a `class_name` (a `-s` probe, a capture, a solver) is **loaded**, and its
whole chain of `class_name` references is compiled with it. The order is the directory listing's, which is the
filesystem's (hash order on ext4), not alphabetical: two runners with the same checkout scan the same folder in
different orders.

On Linux, some scripts left behind a few of their dependencies' scripts as `Resource still in use` when they were the
first thing loaded: loading `solve_grips.gd` and quitting leaves 12 objects and four scripts alive
(`ObjectDB instances were leaked at exit`, `4 resources still in use`). Nothing in the script is wrong by itself: each
class it names loads clean alone, and the leak needs the combination (`GripSolver`, `HandGrip`, `WeaponHold`,
`PlayerAnimation`). The same scripts loaded later, after others had pulled the same classes in, left nothing, so a runner
whose order loaded them last passed, and one whose order loaded them first failed with 250 to 1,200 leaked instances
(fonts, shaped text, textures, audio banks: everything the leaked scripts' statics reach). It never reproduced on
Windows, nor on a Linux machine with another directory order.

## What to do

- **Keep dev tools out of the folders a test run scans.** Probes, solvers, measuring scripts and captures that are not
  suites go under `tools/` (Deadnight: `game/tools/art`, `game/tools/captures`), not under `tests/`. A helper class that
  tests use (`class_name`, extends `RefCounted`) can stay: the scanner skips it.
- **Hand GdUnit script paths, not folders.** `-a res://tests/x/test_a.gd -a ...` loads the suites and only what they
  use, in a fixed order, so the run is the same on every runner.
- **Find the script by loading it alone.** A ten-line `-s` script that does `load(path)` from `PROBE_PATH` and
  `quit()` shows the leak for one script in a second; sweep the non-test scripts of a folder with it. On a CI-only
  leak, a temporary workflow that skips the runners that do not leak and runs the folder, then removes files while the
  leak stays, names the minimal set in about ten minutes; the runner type is in `/sys/devices/virtual/dmi/id/sys_vendor`
  (`Microsoft Corporation` did not leak, `Amazon EC2` did).
- **Run Linux on the machine you have.** The pinned Linux Godot (`tools.toml`, hash-checked) runs under WSL on
  Windows; copy the project (without `.godot`), import twice (the first import can crash on a font), and run the same
  arguments, with `taskset -c 0-3` for a four-core runner.

See the [lesson](../lessons/2026-11-04-dev-scripts-in-scanned-test-folders-leaked-at-exit-on-some-runners.md).

## A test that only needs a number from a scene

A suite that `instantiate()`d the lot's greybox to read the size of one floor passed every case and ended with `2 RID
allocations ... FontAdvanced were leaked at exit` and GdUnit4's own scripts as `Resource still in use`; reading the
scene's text (`FileAccess.get_file_as_string` and a `RegEx` over the node's `transform` and `size`) made the same
assertion with a clean exit (Deadnight #1172). A check that a data line agrees with a scene reads the `.tscn`; a test
that needs the scene running instances a small one of its own.

See the [lesson](../lessons/2026-11-05-a-test-that-instanced-the-greybox-leaked-at-exit.md).

## A suite that only names a class

A GdUnit shard leaked 996 objects and 432 resources at exit with every test green, on pull requests that changed
nothing related, and a new test file elsewhere made it come and go (Deadnight #1231). The scripts a suite only *names*
(`HeldWeapon`, a scene's classes) are read as its dependencies; one that is never loaded as itself is still in use at
exit, with the statics, fonts, textures and banks it reaches. `weapons/test_recut_skin.gd` leaked 243 objects alone,
`world/test_drive_in_greybox.gd` 257, and the shard's mix 996; other suites that load the same classes first cure it.

- **Find it by running the suite alone** (`-a <one suite>`, `--verbose`), not by reading the shard's log: a suite that
  leaks alone is the cause, and it reproduced on Windows with the shard's own list. A single test case of it leaks the
  same count (the suite's script), so do not read its tests.
- **Probe scripts:** `extends SceneTree`, `load(OS.get_environment("PROBE_PATH"))` in `_init`, `quit()`: a second a
  script; a sweep of every game script lists the ones that leak alone.
- **Load every game script first, in name order.** A command line tool that does so before GdUnit's own
  (`ScriptWarmup`, `tools/ci/warm_GdUnitCmdTool.gd`) took the shard from 996 to none for 7 seconds. Keep
  `GdUnitCmdTool.gd` at the end of the wrapper's name: GdUnit finds its arguments after the argument that contains it,
  and a wrapper named otherwise prints the usage and runs nothing.
- **A shard that fails an earlier step never runs the leak check** (a failing test stops the step on `pipefail`
  before the grep; a failed budget step skips the tests), so a main run that is red for another reason says nothing
  about leaks.

See the [lesson](../lessons/2026-11-05-a-suite-that-only-named-a-class-leaked-the-shard-at-exit.md).
