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
  arguments, with `taskset -c 0-3` for a four-core runner. A soak seed that broke only on CI's Linux runner broke the
  same way, at the same tick, under WSL (gdstudio #1326); write the commands into a script and run it with
  `wsl -d Ubuntu -- bash <script>` from PowerShell (Git Bash rewrites the script's path, and `$` in an inline
  command is expanded before WSL sees it).

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
- **A list of only GdUnit4's and the autoloads' scripts is not yet a cause.** Cut the suite until two names remain:
  a fixture that extends a game class and keeps a static variable gives the same list
  ([A subclass that keeps a static variable](#a-subclass-with-statics)).
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
- **Approach:** In a kit template, judge a new suite's leak lines by the whole `gds template test` run (one process,
  CI's condition), not by a `--suite` run of it alone; bisect only a leak the whole run shows. **Watch out for:** a new
  suite of 3D Third Person leaked 196 objects run alone, the same with every test turned off, and main's
  `test_commands_only.gd` leaks alone too; rewriting the suite's lambdas into methods changed nothing, and in a run of
  nine suites, and the whole run, it left nothing. **Seen:** gdstudio #901, 2026-11-10 (part 3, an hour of bisecting
  a leak CI never sees); gdstudio #887, 2026-11-10 (`test_prone_aim.gd` alone: 195 GDScript objects with every test
  but one turned off, none in the whole run; the RID lines beside them were real, next entry); gdstudio #1026,
  2026-11-11 (the player scene loaded alone).
- **Approach:** When a typed `@export var x: MyResource` makes `godot --headless --import` end with `resources still in
  use at exit` (CI fails an import with any `^ERROR`), put each changed script back to `main`'s, one at a time, and
  declare it `@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "MyResource") var x: Resource`, the same slot in the
  inspector. **Watch out for:** the leak named the template's old scripts (the spawn point, `gds_ui`, Phantom Camera: 15
  resources), not the new code; it came with the typed export in `Weapon` or `ImpactSurface` alone, never in a minimal
  project or with `Resource`, and removing `@tool` or the exports' ranges changed nothing. **Seen:** gdstudio #888,
  2026-11-10 (`EffectDef`; Godot 4.7.2's cause not found).
- **Approach:** When a leak at exit shows only in CI, get CI's own evidence before changing code: run the failing
  step with `--verbose` (it names each script still in use) and add a temporary step that runs it earlier in the job,
  before the tests. **Watch out for:** CI's `--export-release Web` of 3D Third Person ended with 17 scripts in use
  (`gds_ui`, Phantom Camera, the audio settings), none of them changed, while every local replay was clean (Windows,
  the same Ubuntu 24.04 in WSL, tmpfs, 4 cores, CI's exact test command); writing the mask defaults as numbers, a guess
  from the entry above, changed nothing. The next run of the same code passed, an early export included: this leak
  comes and goes, so one red export is not proof a change caused it; rerun before bisecting. **Seen:** gdstudio
  #954, 2026-11-10.
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

- **Approach:** When a capture scene (a `tools/capture/*_tour.tscn`) ends with `17 resources still in use at exit`,
  run an existing tour on the same game as the control and bisect the new tour against a bare one that only waits and
  quits (each run about a minute at `--fps 10`); have the tour learn what it labels from signals (`weapon_changed`),
  read once, rather than from a resource it fetches every physics frame. **Watch out for:** the fire-zoom tour read the
  held `WeaponDef` (its `display_name`) every physics frame for its label and left 17 scripts (the UI, Phantom Camera
  and shake addons) and the variant pools alive at exit in five runs in a row, with no input at all; the same label fed
  by `weapon_changed` exited clean twice. The engine-side cause was not found. **Seen:** gdstudio #1255, 2026-11-11.
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
  captured, disconnect in `after_test`); gdstudio #964, 2026-11-10 (a lambda on the emitter's own signal).
- **Approach:** Give a `RefCounted` test helper that listens to an object it owns (a client and its link) a
  `release()` that disconnects its handlers, and call it from the fixture's `_exit_tree`. **Watch out for:** nothing
  frees two `RefCounted` that hold each other: a test client's lambda on its own link's `closed` left 4 instances and
  7 scripts in use at exit while both cases passed. **Seen:** gdstudio #904, 2026-11-10 (`HandClient.release()`).

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
  gdstudio #903, 2026-11-10 (fix: weak references and a test that frees one end); gdstudio #1386, 2026-11-13
  (`ClientItems` kept the `ClientCombat` that owns it: 18 instances leaked; fix: the owner is an argument of each
  call, never kept).
- **Approach:** A scene's script makes its nodes in `_ready` (or adds them as children at once), never in a member
  initializer (`var _dummy := Node3D.new()`) that only `_ready` adds to the tree. **Watch out for:** a test that
  `instantiate()`s every scene and frees it outside the tree (the layer check) frees the children, not a node held
  only in a member, so the run ended with `1 orphans` and `1 ObjectDB instance was leaked at exit` (exit 101) from
  the minimap bench. **Seen:** gdstudio #954, #926, #966, 2026-11-10 (the minimap and parts benches, the senses
  tour); #1075, 2026-11-11 (a probe: green locally, only CI's exit 101 named it; grep a new bench or tour for
  `:= .*\.new()` on a `var` line before the push); #1408, 2026-11-13 (the burst tour's caption `Label`).
- **Approach:** A fixture that owns sounding bodies (`OnlineRig`) stops their players and waits on the mixer
  (`AudioDrain.stop_all(self)`) in its `NOTIFICATION_PREDELETE`, only when one plays; `AudioStreamPlayback*` in the
  `Leaked instance:` list is a voice. **Watch out for:** on `--fixed-fps` the last ticks pass in milliseconds while
  headless audio mixes every 70 to 90 ms, so a swing outlived the run (6 instances, one to three runs in four);
  `_exit_tree` runs after the players stopped, so it cannot tell one played; `assert_object(playback)` keeps it alive.
  **Seen:** gdstudio #1495, 2026-11-14 (`test_net_rig_voices.gd`; [details](audio.md#leaks-at-exit-in-a-test-run)).
- **Approach:** A cache of resources shared by every instance of a class (`static var _meshes: Dictionary[float,
  SphereMesh]`) is emptied when the last instance goes: count instances in `_init` and `NOTIFICATION_PREDELETE`, and
  clear the dictionaries at zero. **Watch out for:** a static holds its resources until the script unloads, after the
  servers have shut down, so a run that fired one pooled projectile ended with `RID allocations of type JoltShape3D,
  DummyMesh, DummyMaterial, DummyShader were leaked at exit`, one of each cached look. **Seen:** gdstudio #887,
  2026-11-10 (`Projectile`'s shared mesh, shape and paints).

## The export leak is intermittent on CI {#the-export-leak-is-intermittent-on-ci}

<!-- new section: the earlier sections cover leaks a test run makes; the template job's headless web export failed
     with the same message on one run and passed on the next with the same code -->

The template job's `--export-release Web` sometimes ends with `N resources still in use at exit` and passes on a rerun
of the same commit (gdstudio #954 saw it on one run and not the next two; #888 the same). The lines come from the
editor process after the pack is written (the add-ons unload, then the leak report), so they say nothing about the
build, which the steps after the export judge (the pack's contents, the browser boot). The export step fails on any
other `ERROR:` line and on Godot's own failure, and prints the at-exit lines as a warning (gdstudio #1236).

The retry that #998 added never ran. A leaking editor also prints `Pages in use exist at exit in PagedAllocator` (an
`ERROR:` line the leak filter did not name) and, with `--verbose`, a list of orphan names, some of which hold the word
`ERROR` (`Orphan StringName: REPORT_ASSERT_ERRORS`). The step read those as "another error", printed every `ERROR`
line and exited 1 at once: runs 43022827198 (#1194) and 43044822252 (#1223) both failed in the export step with every
test green and no line other than the leak, and neither reached the retry.

- **Approach:** Classify a Godot log by `ERROR:` lines (with the colon) that do not contain `at exit`, and test the
  classifier against the failed run's own log before trusting it (`gh run view <id> --log --job <job>`, cut to the
  step). **Watch out for:** `grep ERROR` also matches verbose orphan names, and the leak brings a
  `Pages in use exist at exit` line besides the two the filter knew; a job that "failed with every test green" was the
  export step, not the tests step (`Exit code: 0`, `0 orphans` in its summary): read which step carries
  `##[error]Process completed` before looking at the tests. **Seen:** gdstudio #1236, 2026-11-11 (runs 43022827198,
  43044822252).

- **Approach:** Tell a flake from a real leak by rerunning the job, then by exporting early in the job (before the
  tests) with `--verbose`: a leak that names the same script on every run and in the early export is real and is fixed
  in that script; one that comes and goes with the same code is the flake, which the retry absorbs. **Watch out for:**
  a retry hides a leak that happens one run in two, so read the warning's script names in the log when it shows.
  **Seen:** gdstudio #998, 2026-11-10 (retry in the template job's export step); gdstudio #1194, 2026-11-11 (237
  scripts from the add-ons and gdUnit4, none of them the change's; the retry did not run, see above).

## An exported typed array and a cast to the script's own class {#typed-array-export-and-self-cast}

<!-- new section: the sections above find which suite or script leaks; none names an engine pattern in a game
     script that leaves other scripts (GdUnit4's, the autoloads') in use at exit -->

Under Godot 4.7.2 a script that has **all three** of these leaves scripts in use at exit when the class its array holds
was loaded as itself first: an `@export var x: Array[Other]` of a `class_name` class, a cast or type test against its
own class in a function (`node as Self`, `node is Self`, `var s: Self = node`, a `-> Self` that returns a `Node`), and a
GdUnit4 run in the same process. The scripts left are not the two named: they are GdUnit4's, the autoloads' (`gds_ui`,
Phantom Camera, the audio settings, the camera shake) and whatever their statics hold, about 190 objects and 120
scripts. Taking away any one of the three cures it (a single typed export, `return self`, an array that is not
exported, `Array[Resource]`). A ten-file project shows it: GdUnit4, `def.gd` (`class_name Def extends Resource`),
`emitter.gd` (`@export var arr: Array[Def] = []` and `static func find(n: Node) -> Emitter: return n as Emitter`), a
one-assert suite, and a wrapper of `GdUnitCmdTool.gd` that loads `def.gd` then `emitter.gd` first; loading them the
other way round, or without GdUnit4, is clean. Godot's tracker has the same family, closed unfixed
(godotengine/godot#122601, #123883 and #122022); 4.8's shutdown clean-up does more.

The cast is not always needed: `WeaponLoadout` (`@export var slots: Array[WeaponDef]`, no cast to `WeaponLoadout`
anywhere in it) left the same 188 objects and 117 resources when a suite ran a player and held a `WeaponDef` it got at
run time (`var hold := animation.held_definition()`), or gave its weapon a duplicated `WeaponDef`. The same suite that
only *named* `WeaponDef` (the call compiled, never run) was clean. So read every exported `Array[Other]` of a
`class_name` class on the suite's path as a candidate, with or without a cast.

- **Approach:** Export such an array as `@export_custom(PROPERTY_HINT_TYPE_STRING, "24/17:Other") var x:
  Array[Resource] = []` (the inspector still offers only `Other`) and cast each item where it is used. Find the script
  with a wrapper of `GdUnitCmdTool.gd` that loads a list of scripts before `super()`, a one-assert suite, and a greedy
  cut of the list while the leak stays. **Watch out for:** loading every game script first (the Deadnight cure above)
  made every 3D Third Person suite leak, since name order loads `effect_def.gd` before `effect_emitter.gd`, as the
  export does; an array that tests or scenes assign typed breaks as `Array[Resource]`, so change only the one the cut
  names. **Seen:** gdstudio #1081 (PR #1103), 2026-11-11 (`SlideRack.fits`); gdstudio #1236, 2026-11-11
  (`EffectEmitter.warm_up`; `Hotbar` and `AiRelations` have the shape
  and did not leak in any order tried).
- **Approach:** When a suite leaks alone and not in the whole run, cut it to the smallest set of its cases that still
  leaks (each case in a file of its own with the suite's head, then one body a line at a time; a case turned off by a
  rename still compiles, so cut bodies out), then put the exported `Array[Other]` the last line reaches to
  `Array[Resource]`. **Watch out for:** `test_player_step.gd` (a duplicated `WeaponDef` after `CommandCodec`) was
  first filed as the engine family with no script to change; it and `test_prone_animation.gd` (the case that calls
  `held_definition()`) were both `WeaponLoadout.slots`, which has no self-cast. **Seen:** gdstudio #1236, 2026-11-11
  (four other suites of #1138 already clean alone at 9ebaa690); gdstudio #1249, 2026-11-11 (fix: `slots` as
  `Array[Resource]`: prone 188 objects and 117 resources to none, player step 191 and 120 to none).

## A subclass that keeps a static variable {#a-subclass-with-statics}

<!-- new section: the sections above name a suite that only names a class and an exported typed array; neither
     covers a test fixture whose own static variable leaves GdUnit4's scripts in use when its base is named first -->

Under Godot 4.7.2 a script that **extends a game class and reads a static variable of its own in a function** leaves
GdUnit4's scripts and the autoloads' (`gds_ui`, Phantom Camera, the audio settings, the camera shake, decoded sounds)
in use at exit when a suite names the base class before the subclass: 213 objects and 118 resources for a suite of
one assert, and, in 3D Third Person's `test_net_ai_online.gd`, 779 objects, 553 resources and RID lines (JoltShape3D,
DummyMesh) from everything those statics reach. The suite's own script and the two classes are not in the list.

What the probes showed (a one-assert suite whose unused helper only names the classes, each run alone):

| Suite names | Subclass body | At exit |
| --- | --- | --- |
| `Character`, then `CountingAi` | `static var` read in a function | 213 objects, 118 resources |
| `CountingAi` only, or `CountingAi` first | the same | clean |
| `Character`, then `CountingAi` | `static var` never read, or a plain `var` | clean |
| `Character`, then `CountingAi` | counts in a `RefCounted` class of their own | clean |
| `CharacterController`, then `PlayerInput` | `static var _key_holders` | 213 objects, 118 resources |
| a ten-line base in `tests/`, then its subclass | `static var` read in a static function | 213 objects, 118 resources |

Loading the base script first through a wrapper of `GdUnitCmdTool.gd` leaked the same; loading the subclass first
cured it. Some bases did not show it (`Health`, `Hotbar`, `AiDirector`), so a clean probe of one base proves nothing
about another. A `-s` script that loads the two scripts and quits, without GdUnit4, was clean.

- **Approach:** Keep the shared counters of a test fixture that extends a game class in a `RefCounted` class of their
  own (`AiCallCounts`) and have the fixture add to it; the fixture keeps no `static var`. Find such a leak by running
  one case alone (`-i <suite>:<case>` for each other case), then copies of the suite with one case's body, then with
  its lines cut, until two names remain. **Watch out for:** the lead was the class-loading family of the sections
  above, since the list held only GdUnit4's and the autoloads' scripts, and even the suite's one-assert case leaked
  683 objects; the cause was `CountingAi`'s three static counters, read by `new_counts()`, once the suite had named
  `AiCharacter`. **Seen:** gdstudio #1499, 2026-11-14 (`test_net_ai_online.gd` alone: 779 objects and 553 resources
  to none, the same 7 cases); #1502, 2026-11-14 (`PlayerInput`, now `RagdollKeyHolders`).
