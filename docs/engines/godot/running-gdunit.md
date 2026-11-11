# Running GdUnit4 and long test runs

<!-- new section: the testing pages cover how fast a suite is and what leaks at exit; nothing held how to run a whole
GdUnit suite on a shared machine (fresh checkouts, time limits, logs, what to run before a push) -->

A whole Deadnight suite is about 3,400 cases and runs for most of an hour, on a machine that other agents share. CI
runs it headless, in shards (`godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a <suite> -c
--ignoreHeadlessMode`); a run that needs a window goes through `gds godot` ([No focus](no-focus.md)). What a leak at
exit means is in [Leaks at exit](test-exit-leaks.md), how to make a suite fast in [Test speed](test-speed.md), what a
window on a runner can judge in [Windowed GdUnit on a Linux runner](windowed-gdunit-on-linux.md).

## A fresh checkout {#fresh-checkout}

- **Approach:** Before the first GdUnit run in a checkout made by hand (a worktree, a baseline of `main`), copy
  `game/addons/gdUnit4` (and `godot_mcp`) from a started worktree, then run `godot --headless --path game --import` to
  the end, logged to a file with its exit code read. **Watch out for:** the addons are git-excluded and `gds issue
  start` installs them, so a hand-made worktree has none: `GdUnitCmdTool.gd` is "File not found", a windowed run exits
  1 with no test result and reads as a failing suite, and an import cut short by `| tail` looked done. **Seen:**
  Deadnight, 2026-11-01, 2026-11-03 (twice), 2026-11-05 (fix: copy and import once; "exit 1 and no `Overall Summary`"
  is a run that never started); gdstudio #952, 2026-11-10 (a kit worktree had no `godot/addons/gdUnit4`: unzip it
  from the cache's `gdunit4-<version>/src.zip`).
- **Approach:** After every merge of main or checkout that adds a `class_name` script, run `godot --headless --path
  game --import` before any test, capture or soak, give each windowed run a `--timeout` (or a `quit()` watchdog timer)
  and read the first minute of its log for `Parse Error`. **Watch out for:** the global class cache is rebuilt only by
  an import, so scripts naming the new class fail to compile (GdUnit: `Could not find type`); headless `-s` tools
  still work (they load by path), a windowed run waits instead of exiting (20 minutes, no PNG), and a soak counted its
  chunks that failed to compile as nights of round 1. **Seen:** Deadnight, 2026-11-01; Deadnight, 2026-11-03 (soak
  after `gds merge-main`); Deadnight, 2026-11-05 (`TouchStick`) (fix: import after the merge; a median of 1 is a
  crashed run; no `SHOT` line after a minute is stuck, not slow).

## The command line {#command-line}

<!-- new section: the page covers fresh checkouts, logs and what to run before a push; nothing covered the command
     line's flags or how a parse error ends a whole run -->

- **Approach:** Run GdUnit4 headless as `godot --headless --path game -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a
  res://tests -c --ignoreHeadlessMode`, without `-d`, under a short `timeout`, with the output sent to a file whose
  tail you read. **Watch out for:** GdUnit4 refuses a headless run without `--ignoreHeadlessMode` (exit 103); with the
  documented `-d` a script error or a parse error stops the engine at a `debug>` prompt nobody answers, so the log
  fills with `Debugger Break` (or, through a grep, with nothing) until the outer timeout and Godot processes stay
  behind; a run silent for a minute is a stuck debugger. A test of a symbol that may be missing reads it dynamically
  (`get_script_constant_map()`). **Seen:** Deadnight, 2026-11-01 (without `-d` script errors become failures);
  Deadnight #1323, 2026-11-06 (twice 3 minutes on a `get_script()` call in a suite).

- **Approach:** Add `--fixed-fps 60` to the command of a game whose tests step physics ticks (the template job, a
  game's `ci.yml` and `templates/repo/AGENTS.md` have it). **Watch out for:** it makes each frame one tick and removes
  the wait for the clock, so a suite that loops on `Time.get_ticks_msec()` times out; the reason and the numbers are in
  [Test speed](test-speed.md#what-makes-a-suite-run-at-the-clocks-speed). **Seen:** gdstudio #916, 2026-11-10.

- **Approach:** Never name a local variable or parameter of a test `before` or `after` (nor any other function of
  `GdUnitTestSuite`: `assert_*`, `auto_free`, `await_*`). **Watch out for:** the project turns a shadowed name into a
  parse error, so four suites did not load, `gds check scripts` named them and a GdUnit run would have stopped at the
  first. **Seen:** gdstudio #881 (four menu suites; `was`), #924 (a camera distance), #887 (a health read before a
  shot), #1013 (a helper's parameter, written after reading this entry), #904 (`ticks_before`, `later`), #965
  (`next_up`), #1047 (both, after reading this), all 2026-11-10; #906, 2026-11-11 (byte counters named `before` and
  `after` in a helper), #907 (`after`): grep a new suite for `before` and `after` as names, and for a local named like
  one of the script's own exports, before its first run; `gds template test` names them at parse.

- **Approach:** Wrap the call that makes a script error on purpose (a watchdog test) in
  `await assert_error(func() -> void: <the call>).is_runtime_error("<Godot's exact message>")`, then assert what the
  code under test did after it. **Watch out for:** GdUnit4 6.2 reports any `SCRIPT ERROR` raised during a test as a
  failure of that test ("Godot Runtime Error !"), even when the code under test caught it and carried on as designed;
  the assert takes the entry out of the error monitor. **Seen:** gdstudio #965, 2026-11-10 (the task watchdog's tests:
  a task's `update()` calls a method on `null`).

- **Approach:** Check that an assertion exists on GdUnit's assert class before using it; for "not approximately equal"
  write `assert_bool(is_equal_approx(a, b)).is_false()`. **Watch out for:** `assert_float(x).is_not_equal_approx(...)`
  does not exist: the case ends in a runtime error ("Nonexistent function") at that line, not a failed assertion, and
  everything after it in the case is skipped. **Seen:** gdstudio #1046, 2026-11-11 (the throttle suite's catch-up case).

- **Approach:** Select a suite by its file (`-a res://tests/x.gd`), and read the summary's count of test cases (and
  `grep -c STARTED`) as well as the exit code. **Watch out for:** `-a res://tests/x.gd::test_y` is not GdUnit's form
  of a filter here: nothing ran and the exit code was 0 in 2 s, and no failure reads as a pass. **Seen:** Deadnight,
  2026-11-04 (fix: run the suite and read the count).

- **Approach:** After a full run, find each new suite by name in its list (`gds template test` prints one line a
  suite), and write a new test file with LF line ends. **Watch out for:** two new suites written with CRLF ends ran and
  passed when named with `-a`, but the folder scan (`-a res://tests`, what CI and `gds template test` run) skipped both
  without a word: 193 suites passed and neither was among them. Git stores them with LF, so a fresh checkout scans
  them; the working tree that `gds template test` copies does not. **Seen:** gdstudio #1073, 2026-11-11 (`file` named
  the two; converted to LF).

- **Approach:** When a run ends with no failure and no tests, read the top of the log for a `Parse Error` first, fix
  the one script, and check that the executed-suite count matches the folder; before moving constants into a resource,
  grep the tests for `^const .*<MovedClass>\.`. **Watch out for:** one test script that does not parse stops the scan
  of the whole run, not only its suite (exit 105, no `STARTED` line): gdformat rewrote a multi-line lambda inside a
  call into a form Godot refuses, and `const TOTAL := HudFuel.IN_TIME + ...` became a call once the constants moved
  into a `.tres`, so the whole `tests/ui` folder did not run and no test was red. **Seen:** Deadnight, 2026-11-01 (a
  named helper in place of the lambda); Deadnight #415, 2026-11-02 (the `const` became a function).

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

## Time limits, logs and summaries {#logs}

- **Approach:** Give a long run `gds godot --timeout 3500 -- ...` with a shell timeout above it, in the background, or
  split the suites into chunks that each fit; read the log for `did not finish within` before its summary. **Watch
  out for:** `gds godot` stops Godot after 900 s by default, apart from the shell's `timeout`; a helper that keeps
  only `PASSED` and `FAILED` lines cannot tell "all passed" from "stopped half way" (150 suites had not run).
  **Seen:** Deadnight #683, #690, 2026-11-03 (fix: `--timeout`; the helper prints the stop line and compares the
  `Run Test Suite` count with the `test_*.gd` files asked for).
- **Approach:** Give each run its own raw log at an absolute path in the scratch folder, end it with a `FINISHED`
  line, wait on that same path, and read `Overall Summary` from the raw log after the run (exactly one); keep any outer
  `timeout` longer than the run. **Watch out for:** two overlapping runs wrote one fixed log (a pass and a failure, no
  way to tell which code); an outer `timeout 590` killed Godot while `| grep | head` still exited 0 and left an empty
  log; a relative log name landed in the worktree; `| tail` and `| sed` hide the exit code and buffer. **Seen:**
  Deadnight #991, 2026-11-04; Deadnight, 2026-11-04 (fix: `grep -c "Overall Summary"` must print 1, else the run is
  repeated alone; `git status` after a killed command).
- **Approach:** Read the log above the exit line before judging a GdUnit run: 100 is failed tests, 101 warnings, 103
  headless not supported, 104 Godot version not supported, 105 a script error while discovering the tests (a test or a
  script it loads does not parse). **Watch out for:** exit 105 was filed as "a crash or a stop, not measured further"
  though nothing had run; the errors are in the log above `Abnormal exit with 105`. **Seen:** Deadnight, 2026-11-05
  (fix: the script was repaired and the suite rerun; on `main` the suite exited 100 with the real failures).
- **Approach:** Quote each suite's own `Statistics` line (`2/10/5 test cases, 0 failures`), say what a number counted
  (`287 fault lines`, not `287 faults`), keep the logs, case lists and `results.xml` of a measurement until the pull
  request has merged, and have a sentence about "main" or "CI" name the run ids it rests on (`gh run view <id> --json
  jobs`). **Watch out for:** a runner cut with `head -8` showed one suite's summary for three, and the raw logs were
  deleted for disk before CI passed; a page said main's shard failed a step it had passed, from two red runs and none of
  the green, and the list behind two case counts (596 against 595) was gone. **Seen:** Deadnight #987, 2026-11-04;
  Deadnight #1231, 2026-11-05 (fix: compare runs by their case lists; `SCRATCH.md` `Can go:` names a log after the
  merge).
- **Approach:** For orphan nodes, run `gds template test <t> --keep` and read the `N orphans` count under each
  `Statistics:` line in the kept folder's `gdunit.log`. **Watch out for:** the per-suite `ok` lines print cases,
  failures and seconds only, and the log is kept only when the run fails, so a green run says nothing of the orphans
  it left. **Seen:** gdstudio #924 (PR #954), 2026-11-10 (read again in `template_test.py` for gdstudio #1003).

## Before the push {#before-the-push}

A change to a kit template is pushed only after the template's own proof has run, not just the kit's `pytest`:
`templates/<t>/game` has no GdUnit4, so its suites run with `gds template test <t>`, which makes a game from the
working tree in a throwaway workspace of its own, parses every script and runs the suites ([Proving a new
game](new-game.md#proof), gdstudio #830 and #917).

- **Approach:** Before pushing, run `gds merge-main`, then every folder of `game/tests` on the merged branch (or CI's
  own shard command), read the logs for `ERROR`, and ignore any earlier summary; before taking over a branch, list the
  processes whose command line names its worktree and stop the runner script first, then its `timeout` and Godot
  children, by PID. **Watch out for:** a hand-over said "tests passing" and was green only on the folders its author
  guessed: `tests/world` (light cap) and `tests/tuning` (sound tables) read the whole project and failed on a new light
  and sound field, and the old runner script kept moving to the next shard and overwrote the summary. **Seen:**
  Deadnight #1057, 2026-11-04 (fix: all folders on the merged branch, four loops at most, one log folder per run);
  gdstudio #901, 2026-11-10 (a test edited after the run).
- **Approach:** To see a new test fail first, save the diff (`git diff origin/main -- <paths> > file.patch`), run the
  revert, the test and the restore as separate commands with the test under its own `timeout` (or run it in a worktree
  of `main` with the new test copied in), and read `git status` after any killed command. **Watch out for:** revert,
  run and restore in one command: the timeout killed it between the first and the last and the worktree held main's
  files with the fix gone. **Seen:** Deadnight #987, 2026-11-04 (fix: the saved patch restored the work).
- **Approach:** When a change renames a method or changes its signature, search the tests for its callers (`git grep
  -n "<name>(" -- '*.gd'`) and run the full suite once, not only `--suite` on the files you changed. **Watch out
  for:** GDScript finds a wrong call only when the calling script loads, so the changed suites passed and the callers
  in other suites failed in the full run. **Seen:** gdstudio #901 part 2 (PR #997), 2026-11-10.

## Change nothing a run reads {#inputs-of-a-run}

- **Approach:** Commit first, then start the long suites, soaks and measuring arms, and change nothing they read while
  they run (a generator's output, baked meshes, the tests, a merge of main); to go on working, run them in a detached
  worktree of the commit (`git worktree add --detach <dir> <sha>`, one `--import`). **Watch out for:** suites read the
  scene and baked meshes as each suite starts, so a run begun on one scene finished on another ("the way ends 8.6 m from
  the hall"); `gds merge-main` during a soak brought a new `class_name` and every later chunk failed to compile; a
  "before" arm started after the edit measured the new code. **Seen:** Deadnight #994, #917, 2026-11-04; Deadnight #764,
  2026-11-03; Deadnight, 2026-11-03 (soak) (fix: the runs were stopped by PID and rerun on the commit).
- **Approach:** To compare two trees, name both behaviours in the run's arguments (`--ray=body`, `--ray=walls`) so the
  code under test no longer decides what is measured, add a control that must come out equal in both arms (a place the
  change cannot reach), run each arm once by hand and see its success line before looping, and print the first error
  line of every dead run. **Watch out for:** one probe run against both trees called a function the old tree lacked and
  a loop that counts "no done line" as a death read "died 30 of 30" before the change as a perfect-looking result (the
  real before rates were 2, 3 and 0 of 100). **Seen:** Deadnight #764, 2026-11-03; Deadnight, 2026-11-04 (cold loop)
  (fix: a separate probe for the old tree; the lot, where the ray is never asked, matched in both arms).

## Running more than one {#parallel}

- **Approach:** Before filing a flake, reproduce it with nothing else of the same project running and ask whether the
  failing test touches a path, port or temp file another run shares; name test files by process id
  (`QuietSettings.test_path`), give servers port 0, and run one net shard at a time, its log in a file. **Watch out
  for:** every run of a project shares `user://`, and a suite's setup and cleanup delete its fixed file name: one run
  removed it between another run's write and read (3 of 6 concurrent pairs failed, alone never) and a flake issue was
  filed; two parallel full-shard runs of net suites with fixed ports
  printed nothing for 25 minutes (alone: 8). **Seen:** Deadnight #594, 2026-11-02; Deadnight #1231, 2026-11-05 (fix:
  6 of 6 concurrent pairs passed).

- **Approach:** Name every file a suite writes under `user://` by process id (the 3D Third Person template's
  `TempUserFile.path` in `tests/fixtures/`) and delete it in `before_test` and `after_test`. **Watch out for:** every
  game `gds template test` makes has the same name and so the same `user://`, so a fixed name is never harmless on a
  machine many agents share. **Seen:** gdstudio #1043, 2026-11-10 (two settings suites with fixed names: 8 of 10
  concurrent rounds of two copies had a failing run; with `TempUserFile`, 20 of 20 runs passed).

## State a test inherits {#state-a-test-inherits}

<!-- new section: the page covers how a run is started and read; nothing covered what a test inherits from the
     suites before it -->
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
