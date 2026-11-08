# GdUnit tests

<!-- new section: the Godot pages cover test speed, leaks at exit and windowed runs; none held how the GdUnit4
     command line, a parse error or the state between tests fails a run -->

How a GdUnit4 run fails without telling you, and what a test inherits from the ones before it. Speed is in
[Test speed](test-speed.md), leaks at exit in [Leaks at exit](test-exit-leaks.md), a window that is minimized in
[A minimized window](minimized-window.md), and the language traps a test hits in [GDScript](gdscript.md).

## The command line {#command-line}

- **Approach:** Run GdUnit4 headless as `godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a
  res://tests -c --ignoreHeadlessMode`, without `-d`, under a short `timeout`, with the output sent to a file whose
  tail you read. **Watch out for:** GdUnit4 refuses a headless run without `--ignoreHeadlessMode` (exit 103); with the
  documented `-d` a script error or a parse error stops the engine at a `debug>` prompt nobody answers, so the log
  fills with `Debugger Break` (or, through a grep, with nothing) until the outer timeout and Godot processes stay
  behind; a run silent for a minute is a stuck debugger. A test of a symbol that may be missing reads it dynamically
  (`get_script_constant_map()`). **Seen:** Deadnight, 2026-11-01 (without `-d` script errors become failures);
  Deadnight #1323, 2026-11-06 (twice 3 minutes on a `get_script()` call in a suite).

- **Approach:** Select a suite by its file (`-a res://tests/x.gd`), and read the summary's count of test cases (and
  `grep -c STARTED`) as well as the exit code. **Watch out for:** `-a res://tests/x.gd::test_y` is not GdUnit's form
  of a filter here: nothing ran and the exit code was 0 in 2 s, and no failure reads as a pass. **Seen:** Deadnight,
  2026-11-04 (fix: run the suite and read the count).

- **Approach:** When a run ends with no failure and no tests, read the top of the log for a `Parse Error` first, fix
  the one script, and check that the executed-suite count matches the folder; before moving constants into a resource,
  grep the tests for `^const .*<MovedClass>\.`. **Watch out for:** one test script that does not parse stops the scan
  of the whole run, not only its suite (exit 105, no `STARTED` line): gdformat rewrote a multi-line lambda inside a
  call into a form Godot refuses, and `const TOTAL := HudFuel.IN_TIME + ...` became a call once the constants moved
  into a `.tres`, so the whole `tests/ui` folder did not run and no test was red. **Seen:** Deadnight, 2026-11-01 (a
  named helper in place of the lambda); Deadnight #415, 2026-11-02 (the `const` became a function).

- **Approach:** After adding or renaming a `class_name` script, run `godot --headless --path game --import` before the
  tests or any `-s` script; CI imports first and a report script that launches Godot does too. **Watch out for:** the
  global class list (`.godot/global_script_class_cache.cfg`) is rebuilt only by the editor or an import: a headless
  run reads the stale cache, so GdUnit printed `Could not find type "ZombieState"` and `Failed to compile depended
  scripts` for every suite. **Seen:** Deadnight, 2026-11-01 (fix: an import after the new class, in CI and in report
  scripts).

- **Approach:** Read the first failure of a test and fix that: only the first failing assertion of a test is evidence;
  guard the line after an assertion that can fail (`continue` on an empty path). **Watch out for:** once an assertion
  fails the later ones in the test are reported as failing too, even when the values match ("Expecting 'x' but was
  'x'"), and a failed assertion does not stop the test, so the next line read `points[-1]` of an empty path and raised
  an engine error that hid the cause. **Seen:** Deadnight, 2026-11-02 (a scoreboard suite); Deadnight, 2026-11-03 (a
  navigation test).

- **Approach:** In a test that sets `get_tree().paused = true`, wait with `await get_tree().create_timer(seconds,
  true).timeout` (the second argument ignores pause) and reset `paused = false` in `after_test`. **Watch out for:**
  GdUnit4's `await_millis` timer is not an always-processing node, so it stops with the tree and the test never
  finishes; the headless run sat until the outer timeout. **Seen:** Deadnight, 2026-11-01 (fix: a pause-proof timer
  and the reset in `after_test`).

## State a test inherits {#state-a-test-inherits}

- **Approach:** Reset every per-test member in `before_test` (`_backdrop = null`); "not set" must never mean "not set
  by an earlier test". **Watch out for:** a suite is one object for all its tests: an `auto_free` node an earlier test
  stored in a member was freed after it, and a later test that skipped the backdrop passed the stale reference on
  ("previously freed" in `setup`) while the tests that built it first passed. **Seen:** Deadnight, 2026-11-03 (fix:
  the reset in `before_test`).

- **Approach:** To settle a failure or hang that depends on suite order, run a throwaway suite (never committed)
  between each two suites of the real shard order (`tools/ci_test_shards.py --shard N`) that appends what changed
  since the last one: the public `static var` lines of every global class (from `script.source_code`, then
  `script.get(name)`), `Engine.time_scale`, `paused`, mouse and window mode, the root's children and held actions.
  **Watch out for:** GdUnit runs a shard in one process, so every static, held action and node under the root is
  inherited by the next suite, and "the pair passes" proves only that the pair is clean; reading suites for leaks
  found one by luck. **Seen:** Deadnight, 2026-11-05 (fix: nine shards, about 150 entries each, named every leaker by
  position).

- **Approach:** A test that reads node names reads only the names someone chose: skip names that start with `@` (the
  engine's `@<Class>@<counter>`), and make a real engine name by adding an unnamed child, since setting `node.name =
  "@..."` by hand does not keep the `@`. **Watch out for:** the counter counts every node the process made before, so
  a short word or a number in a word list will one day meet it: a check for words from another game's setting failed
  on `@MeshInstance3D@31945` ("1945") only when earlier suites left the counter passing it. **Seen:** Deadnight #878,
  #896, 2026-11-03 (fix: the check skips engine names and still reads every authored name and `Label3D` text).
