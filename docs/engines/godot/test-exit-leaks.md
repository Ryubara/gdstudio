# Leaks at exit in a GdUnit run: what a folder scan loads, and how to find the script

A GdUnit run that passes every test can still fail CI's `leaked at exit|still in use` gate. Besides the audio and
lambda causes ([Audio](audio.md#leaks-at-exit-in-a-test-run)), there is one that depends on **which scripts the
runner loads, and in what order**.

## A folder scan loads every script in the folder, in the filesystem's order {#folder-scan}

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

## What to do {#what-to-do}

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

- **Approach:** Clear a handler stored on an object that the handler itself names in that object's dispose method, not
  in each test, and run a new suite alone and grep its log for `leaked at exit|still in use` before the pull request.
  **Watch out for:** a test set `night.on_event` to a lambda that named `night`, a RefCounted cycle that kept the night,
  its server and every bot script alive: 207 objects leaked and a shard failed with every test green. **Seen:**
  Deadnight #597, 2026-11-02 (fix: `SeatedNight.dispose()` clears the handler first).

## A test that only needs a number from a scene {#a-test-that-only-needs-a-number-from-a-scene}

A suite that `instantiate()`d the lot's greybox to read the size of one floor passed every case and ended with `2 RID
allocations ... FontAdvanced were leaked at exit` and GdUnit4's own scripts as `Resource still in use`; reading the
scene's text (`FileAccess.get_file_as_string` and a `RegEx` over the node's `transform` and `size`) made the same
assertion with a clean exit (Deadnight #1172). A check that a data line agrees with a scene reads the `.tscn`; a test
that needs the scene running instances a small one of its own.

## A suite that only names a class {#a-suite-that-only-names-a-class}

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
  (`ScriptWarmup`, `tools/ci/warm_GdUnitCmdTool.gd`) took a five-suite list from 911 objects to none (same 55 cases),
  for a few seconds. Keep `GdUnitCmdTool.gd` at the end of the wrapper's name: GdUnit finds its arguments after the
  argument that contains it, and a wrapper named otherwise prints the usage and runs nothing.
- **Why `main` stayed clean:** it did not; its shards held the leaking suites in a mix that cures them. Deadnight's
  runs 42011482212 and 42016360272 put both leaking suites in shard 3 with 72 others, and it passed the leak check.
  A leak follows the deal of suites, so a green `main` shard is evidence for that deal only. A red `main` run that
  failed an earlier step (the late-round budget, runs 42004177635 and 42004654168) skipped the tests step, and says
  nothing about leaks either way.
- **A real leak still fails through the wrapper:** a throwaway suite with a two-object `RefCounted` cycle and a `Node`
  in a static variable printed `3 ObjectDB instances were leaked at exit` and exited 101; a failing assert exits 100.

- **Approach:** Find a leak that follows the shard and not the pull request by running each suite alone, then a
  ten-line `-s` probe per script; fix it by loading every game script first, in name order, through a wrapper of GdUnit's
  command line tool, and keep `GdUnitCmdTool.gd` at the end of the wrapper's file name. **Watch out for:** a suite that
  only names a class makes Godot read its scripts as dependencies, and a script never loaded as itself stays in use at
  exit with all it reaches: 996 objects with every test green, cured by other suites that load the classes
  properly, so a green `main` shard proves only its own deal; a wrapper named otherwise prints the usage and runs
  nothing. **Seen:** Deadnight #1231, 2026-11-05 (fix: `tools/ci/warm_GdUnitCmdTool.gd` took 911 objects to none on the
  same 55 cases; a test runs two suites through it in a child Godot and fails on a leak line).
- **Approach:** When a typed `@export var x: MyResource` makes `godot --headless --import` end with `resources still in
  use at exit` (CI fails an import with any `^ERROR`), put each changed script back to `main`'s, one at a time, and
  declare it `@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "MyResource") var x: Resource`, the same slot in the
  inspector. **Watch out for:** the leak named the template's old scripts (the spawn point, `gds_ui`, Phantom Camera: 15
  resources), not the new code; it came with the typed export in `Weapon` or `ImpactSurface` alone, never in a minimal
  project or with `Resource`, and removing `@tool` or the exports' ranges changed nothing. **Seen:** gdstudio #888,
  2026-11-10 (`EffectDef`; Godot 4.7.2's cause not found).
- **Approach:** Before editing the game for a guess about a leak or a stall, run the suite alone with and without the
  edit; run one shard at a time, its log in a file. **Watch out for:** a type cycle between two classes, guessed from one
  probe, was "fixed" in the game's scripts and changed nothing, while two shards run at once on shared net ports stalled
  for 25 minutes (alone: 8) behind a `| sed | grep` summary that hid whether anything ran. **Seen:** Deadnight #1231,
  2026-11-05 (fix: the edit was reverted when the counts did not move).
- **Approach:** Before pushing a new test, run the shard's own command and then CI's gate, `! grep -E "leaked at
  exit|still in use" tests.log`, whatever the exit code; a test that needs only a script's text reads its source rather
  than loading it. **Watch out for:** the shard's last line fails on those lines, not Godot's exit code, so a log ending
  in `ObjectDB instances were leaked` exits 0 locally and fails in CI; a test that only named `WarmupManifest` (which
  loads `PlayerAnimation` and the scripts under it) left them in use, and the lines had been read in the author's own
  log and called usual. **Seen:** Deadnight #1100, 2026-11-04 (fix: bisect with a prefix of the test file, then one line
  at a time; the test reads the source).

## What a test leaves alive {#what-a-test-leaves-alive}

<!-- new section: the page covers the folder scan and a suite that only names a class; the causes a test creates
     itself (cycles, nodes never freed, a preloaded scene) were only in one-problem files -->

- **Approach:** Ask `ResourceLoader.exists(path)` before `load_threaded_request(path)` and treat a missing path as the
  failure it is. **Watch out for:** a request for a scene that is not there printed two engine errors and left one
  `RefCounted` behind at exit (`1 ObjectDB instance was leaked`), which the suite's summary does not carry and CI's
  grep fails; found by splitting the 15-test suite into 15 files of one test each. **Seen:** gdstudio #881, 2026-11-10
  (the loading screen's failure path).
- **Approach:** Connect methods, or callables made with `Callable(self, &"method")` or `.bind(id)`, not lambdas that
  name `self` or the object they listen to: a test captures the id (`var player_id := state.player_id`) and
  disconnects before it frees the night; a rig passes its own methods to what it owns. Run a new suite alone with
  `--verbose` and grep its log for `leaked at exit|still in use` before the first push. **Watch out for:** an object
  that holds the connection and a lambda that holds the object is a cycle nothing frees: every test passes and CI
  fails on `resources still in use at exit`, which the summary line does not carry (576 tests green, 6 instances and 3
  resources leaked). **Seen:** Deadnight #207, #225, #432, 2026-11-01..02; Deadnight #1074, 2026-11-05 (fix: ids
  captured, disconnect in `after_test`; the leak count reproduces exactly alone with `--verbose`).

- **Approach:** Free what a test makes or removes: `remove_child(node)` then `node.free()`,
  `auto_free(SomeNode.new())` (even for a node made only to read `get_property_list()`), or leave the node in the
  `auto_free`d host; read the orphans column of every run (`grep -E "[1-9][0-9]* orphans"`) and fix any number above 0
  before the pull request. **Watch out for:** the host frees only the children it still holds: a HUD taken out of the
  tree had no owner left (298 orphans, 1,529 instances at exit) while the summary read `0 errors | 0 failures` and the
  run was reported green; CI's leak gate failed the shard. **Seen:** Deadnight #746, 2026-11-03; Deadnight, 2026-11-03
  (a node made for its property list, 1 orphan and 2 resources).

- **Approach:** A test or capture script never `preload`s a scene or a heavy resource into a `const`: keep the path as
  a string and `load()` inside the function that runs; when a CI shard leaks and nothing leaks locally, grep
  `preload(".*\.tscn")` under `tests/` before bisecting in CI. **Watch out for:** the folder scan keeps every script
  it loads until the end of the run, so each const kept the whole lot scene, its scripts and statics in use at exit;
  the leak showed only in one shard, never in 15 local runs, and bisecting by CI runs took five pushes. **Seen:**
  Deadnight #837, 2026-11-03 (fix: the three capture scripts load in the function that runs).
- **Approach:** Two `RefCounted` objects that must know each other (the two ends of a loopback link) hold each other
  through `weakref()`, and an end whose other is gone treats it as closed; grep a new suite's log alone for `still in
  use` before the pull request, even when the full run is green. **Watch out for:** `LoopbackLink.pair()` made ends
  that held each other strongly, so every pair a test made stayed alive: 526 template tests passed with one line `4
  resources still in use at exit`, which only a run of each suite alone traced to the loopback suite. **Seen:**
  gdstudio #903, 2026-11-10 (fix: weak references and a test that frees one end).
