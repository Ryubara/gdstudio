# Test speed

How to keep a GdUnit4 suite from running at the speed of the clock, from Deadnight's CI job that took 20 minutes
(Deadnight #524). The numbers and the suite-by-suite list are in the game's `docs/research/ci-time.md`.

## Measure first {#measure-first}

The job log has a timestamp per line. A suite's time is the gap between its `Run Test Suite:` line and the next one
(its `before()` and `after()` included). Sort the gaps; the top twenty are the work. Run the whole suite locally the
same way only when nothing else is loading the machine: a loaded machine doubles unrelated suites.

## What makes a suite run at the clock's speed {#what-makes-a-suite-run-at-the-clocks-speed}

| Cause | What to do |
| --- | --- |
| `await get_tree().physics_frame` per hand-stepped tick | switch the node's `_physics_process` off once and call its tick by hand, back to back; one `process_frame` per measurement |
| `create_timer(s)` to let an animation finish | wait the same game seconds at `Engine.time_scale = 10` and set it back to 1 before the next step (restore it in `after_test` too) |
| a batch of seeded runs bigger than the case needs | keep the full count where it is the gate; a case that proves the gate can fail needs a wall, not a statistic |
| a test about the engine's own callback, a socket or a freeze | leave it on the clock and say so in its first comment |

- **Approach:** Speed a hand-stepped suite by calling the node's tick back to back with the constant step; leave
  `Engine.time_scale` at 1 and, in a headless bot, run several fixed ticks per physics frame. **Watch out for:**
  `time_scale` scales the delta each `_physics_process` gets, so the step is no longer fixed (a bot at 10x started
  round 1 after 1 s of ticks instead of 12 s, a different night); a `physics_frame` await per tick keeps 2,200 ticks
  at 60 a second (a 38 s suite cancelled the 20-minute CI job). **Seen:** Deadnight, 2026-11-01 (fix: about 1,500
  ticks a second headless); Deadnight #524, 2026-11-02 (fix: 38 s to 1.7 s, same poses and limits).

- **Approach:** Run a game's GdUnit4 suites at `--fixed-fps 60`: each frame is exactly one physics tick and the engine
  never waits for the clock. Wait in ticks (`InputSim.ticks`; 3 s is 180), read game time as `Engine.get_physics_frames()
  / Engine.physics_ticks_per_second`, and start a suite that must read the real clock with `# On the clock: <why>`
  (`gds check layout` refuses `Time.get_ticks_msec()`, `get_ticks_usec()` and `create_timer()` in `tests/` without it).
  **Watch out for:** GdUnit4's timeout counts game time, so a loop on `Time.get_ticks_msec()` never ended (6 of 444
  cases); a test that teleports a body and clears its log one frame later heard a stray step the wall-clock frame order
  had hidden: let the state settle first. **Seen:** gdstudio #916, 2026-11-10 (five slow suites 166 s to 18 s with no
  test changed; the whole 3D Third Person suite FIXED_NUMBERS).

## What hand stepping needs {#what-hand-stepping-needs}

- **One physics step for new bodies, and `physics_frame` is emitted before it.** The physics server indexes a body on its
  next step, and the signal fires at the start of an iteration, before that iteration's step. After loading a room and
  after adding a collider or a body, `await get_tree().physics_frame` **twice**; then tick by hand. With none, a
  hand-ticked body falls through the floor; with one, it may stand but `move_and_slide` still costs ten times what it
  does once indexed. The same order means a value a node sets in its `_physics_process` is read after the **second**
  await following the cause: after one, the tick that sets it has not run (a jump buffer pressed and read after one
  await read 0, gdstudio #831). A node that moves an `AnimatableBody3D` with `sync_to_physics` (a door, a platform)
  also shows the new transform only on the next step, so read it after a `physics_frame` or two.
- **The same code path.** Call what the engine calls (`_physics_process`, or the node's public `tick`), with the same
  delta, so a faster suite plays the same game. A node whose `_physics_process` is switched off is not ticked twice.
- **Delta-sensitive comparisons stay in one kind of frame.** `move_and_slide` steps an idle frame by its wall-time
  delta; a recording made in a physics callback and replayed in an idle frame can differ by millimetres under load.
- **A changed tick rate is waited for by its delta, not by a frame count.** After `Engine.physics_ticks_per_second = hz`,
  await `physics_frame` until `get_physics_process_delta_time()` is `1 / hz`: a loaded machine runs several steps in one
  iteration with the old step.
- **Prove it still tests.** Break the behaviour once, locally, and see each sped-up suite fail.

- **Approach:** Step both halves of a record-and-replay test through one helper with the same arguments, taken from
  constants (`PlayerSimulation.simulate(..., TICK)`) and not from the engine (`get_physics_process_delta_time()`,
  `Engine.time_scale`, the wall clock); inject the difference you suspect (the tick rate) into a copy of the old test
  and see it fail. **Watch out for:** the recording went through `Player.tick`, which steps by the engine's physics
  delta, and the replay used `TICK`: one number only until a suite changes the tick rate, so the replay ended 5.6 mm
  from the recording (limit 1 mm) in two full runs and never alone. **Seen:** Deadnight, 2026-11-02 (probable cause,
  found by reading and shown by injecting the difference, never seen in a real run).

- **Approach:** Animate anything a hand-stepped test must move from the delta the view is given each step, not with a
  Tween, which runs on idle frames a hand-stepped suite never draws. **Watch out for:** a prop that slid with a Tween
  stayed where it was however many simulated seconds the night was ticked. **Seen:** Deadnight, 2026-11-01 (fix: the
  crane's view counts `delta` per frame event; Tweens are kept for what no test steps).
- **Approach:** In a hand-run night, press an input and run a few neutral ticks before reading its events, the way the
  nearest suite presses: a command crosses the loopback link and the server uses it on a later tick. **Watch out
  for:** four tests read `reload_started` on the tick of the press and found an empty list. **Seen:** Deadnight #687,
  2026-11-03 (fix: a press, then three ticks, as `test_night_commands.gd` already did).

## Split the suite by seconds, not by folder {#split-the-suite-by-seconds-not-by-folder}

When a suite is too long for one CI job, split it over parallel jobs by the measured seconds of each test script, not
by folder: keep a file of seconds per script (the `Statistics:` line of each suite in the job log carries it), deal the
scripts longest first to the lightest shard, and let a script with no time yet count a default, so a new test lands in
a light shard by itself. Size the shard count from the total (`total / 480 s`, rounded up, plus a margin: runners vary
by 1.5x from job to job), have a self-test compare the shard count with the workflow's matrix, and end every shard with
a check that warns past 60 % and fails past 80 % of the job's time limit, so drift is red before the limit cancels a
job with no failing test (Deadnight #1015, `tools/ci_test_shards.py` and `tools/ci_shard_time.py`;
[CI and deploys](../../studio/ci.md#shards)).

## Night suites: where the seconds go, and what may be cut {#night-suites-where-the-seconds-go-and-what-may-be-cut}

From Deadnight's ten slowest suites (#1017). All are hand-ticked already, so the time is compute; the numbers are from
one machine with 16 threads, and a shared machine moves a suite by 1.5x to 2x between two runs, so a before and after is
run interleaved, twice, and a change of waiting is counted in frames beside the seconds.

- **Look at what a tick spends before cutting ticks.** A night of four players and a crowd ran 3.7 ms a tick: 64 % in
  `server.move` (`move_and_slide` of the players, 0.24 ms for a body standing still), 15 % in the server's frame and the
  players' actions, 11 % in the bots' thinking, 4 % in the dead's. The 64 % was bodies the physics server had not yet
  indexed: after two physics frames it was 1.6 ms a tick and 0.02 ms a call, and every bot suite halved with no cut.
  Cut seconds and seeds only after that.
- **A built night costs 0.5 s** (0.85 s the first time in a process: the lot's scene instantiates in about 0.35 s and
  its navigation in 0.1 s). A suite that builds one per trial (40 trials of the boss's telegraph) pays a third of its time
  there; the world cannot be reused between servers today (it binds to the rules and keeps doors, boards and the mesh).
- **Size a seeded statistic by its seeds' spread, not by its pooled shots.** The tolerance band is read against the
  *seed-to-seed* standard error: for each statistic take the per-seed values of one full run, `s` their spread, `d` the
  distance of the pooled value to the nearer edge of its band, and `d / (s / sqrt(k))` for `k` seeds. A seed count may
  fall only where the margin stays above the one the statistic has now, and never below 4 standard errors; a statistic
  that is already at 2 to 3 keeps every seed (Deadnight's Veteran head share sits at 2.6). A level whose value is the same
  in every seed (a Rookie that never dodges: 99 blows of 99 due, eight times) needs two.
- **A "the gate can fail" test runs the cells that show the miss.** The gate's cells cost what their players cost (the
  8 player cell is half of a batch); a drift in the tuning is a whole round off in the solo and duo cells, which
  together cost a sixth. The checker reports `no cell X` for a cell it was not given: filter those out, or the test
  passes on its own absence.
- **Stop an event-shaped test when the event has happened, and not a state-shaped test.** A night whose test asks that a
  link was bought, round 4 began and a weapon was bought can stop 30 s after the last of them: each stays true. A test
  that reads where a bot is at the end of a wait (after a ping's mark runs out, "away from the mark") is true early for
  a trivial reason, so its wait is the subject and stays.
- **Wait for the engine's answer, not for a count of frames.** `SeatedNight.settle_doors` polls until the map has taken
  in the doors bought (2 to 3 frames on a quiet machine, 8 to 12 under load), where 60 frames cost a second of real time
  and 12 failed one run in three.
- **A sweep may stop a hop when the state is a fixed point, exactly.** The simulation reads only the state and the
  still world, so a tick that leaves the state unchanged under an unchanged command leaves every later tick unchanged.
  Prove it on the real sweep before relying on it: run all ticks, note the first fixed tick, and count the hops whose last
  state differs from it (0 of 19,667 on the midway sweep). Do not coarsen a sweep's grid instead: a trimmed grid passed
  on the map it was written to catch.
- **Break it once, with a mutation that the cut test must still see.** For a seed cut, give a profile another profile's
  skill (a Rookie with the Veteran's reaction) and see the band fail on the fewer seeds; for a soak, take the safety
  constants out of the code and see the shorter night fail.

## Seat bots as the host does {#seat-bots-as-the-host-does}

A test that makes a `BotClient` by hand copies `BotHost.seat`: the shared `bot_ids` table and team, not only what compiles.
Without the table each bot takes its neighbour for a person and a team order (Hold, a ring about a spot) collapses; a
flake of 3 cm over a bound was the symptom.

## One clock per test {#one-clock-per-test}

A test that holds packets for real milliseconds (a `LinkConditioner`, a ping) while its loop counts physics frames has
two clocks, and a slow runner pulls them apart. Give the real-time part an injectable clock driven by the frame count
(Deadnight's `WebSocketLink.clock`), count every wait in frames, and prove it by slowing each frame with
`OS.delay_msec`: the numbers of the run must not move.

- **Approach:** Give the real-time part of a network test an injectable clock (`WebSocketLink.clock`, `NightHost.clock`,
  `GameServer.clock`) driven by the physics frame count over the tick rate, count every wait in physics frames, and slow
  each frame by 0, 40 and 100 ms to show the numbers do not move. **Watch out for:** a bad-network test held packets for
  real milliseconds and waited 8 wall seconds while the game ran in frames, so a loaded runner played fewer frames of
  the same network (484 corrections where a quiet one prints 50) and failed once; a `--fixed-fps 60` run with no game
  clock on a `GameServer` lost its client in seconds. **Seen:** Deadnight, 2026-11-02 (fix: one clock; the worst gap
  stayed 1.12 to 1.17 m at every slowdown); Deadnight #1059, 2026-11-04 (`GameServer.clock`); gdstudio #903,
  2026-11-10 (a socket rig on the real clock: lingers never ended at `--fixed-fps 60`).

- **Approach:** Switch off a node that eases or animates in `_process` (`set_process(false)`,
  `AnimationTree.callback_mode_process = MANUAL`) and step it by hand with a fixed delta in the test's tick helper;
  give a delta-driven animation its time by hand (`animation._process(seconds)`) and assert relative to the start;
  hold an action until its last event, not the rounded clip length. **Watch out for:** a test that waits N
  `physics_frame`s and reads a node that runs on the frame delta drifts under load (one or two cases in about one
  loaded run in ten), and a 0.7 s sweep awaited for 90 real frames read 0.934 on a fast headless runner (0.65 s) and
  1.0 on a desktop; never count frames, or read `get_process_delta_time()`, for something that runs on a delta.
  **Seen:** Deadnight, 2026-11-01 (player suite; reproduced with busy-loop headless Godots, killed by PID); Deadnight
  #802, 2026-11-03.

## Reading a value that time drives {#time-driven-values}

<!-- new section: One clock per test covers a network test; the springs, eases, gates and waits of UI and input tests
failed the same way and had no home -->

A value stepped by `delta` (a spring, an ease, a pulse, a smoothing window) has no fixed answer after N frames: the
answer depends on how long a frame took, which is the machine, the window and the renderer.

- **Approach:** Read such a value after it has run its course, in time and not in frames: wait for
  `UISpring.is_settled()` (with a cap in seconds), or sum `get_process_delta_time()` over one full period, then assert
  the exact end value, and sweep the suite with `--fixed-fps 1000 480 240 60 10` (headless and through `gds godot`).
  Fix the siblings by searching every read of the value, not by the list in the issue. **Watch out for:** `UISpring.step`
  integrates one step per whole 1/240 s, so a frame under 4.17 ms moves nothing and a test that asserted a movement one
  frame after the change failed; a pulse read after 60 frames was a quarter of its turn in a window with no frame cap;
  all passed headless and at 60 Hz. **Seen:** Deadnight #1202, #1219, 2026-11-05 (fix: waits in time; the sweep at
  1000 fps fails any frame-count read).
- **Approach:** Assert a range the tuning allows, or a relation between two measures taken at the same moment, not one
  value at a place the clock chose; before blaming timing, list every time-stepped value between the input and the
  asserted number and read the first failing number back through them, then prove the test with a mutant that turns
  nothing. **Watch out for:** a drag test expected 0.148 and got 0.112 to 0.125 because the aim button eases the look
  scale between 0.7 and 1 with a damped spring, and a slide test looked three frames into a tween driven by real frame
  time (4.7% of the way at 145 fps, 75% with 100 ms frames). Reproduce a load flake with `OS.delay_msec(100)` after
  each `await process_frame`. **Seen:** Deadnight #576, #582, 2026-11-02 (fix: the range `hip_turn *
  aim_sensitivity_scale` to `hip_turn`; the position and the colour ride one tween, so assert they match).
- **Approach:** Give a rule that reads time an injectable clock (a `Callable`, real `Time` in the game), hand every
  suite the layer's own stepped time plus an offset, use a pure test clock only for the boundary cases, and run each
  suite that plays a drag with the rule on. **Watch out for:** a double-tap gate (under 250 ms, inside 10 CSS px) read
  `Time` while three look tests played time by hand with `_process(1/60)`, so a real 250 ms never passed and the drag
  sat in the gate for its whole run; a test wanting millisecond edges has the opposite need. **Seen:** Deadnight #1288,
  2026-11-05 (fix: `TouchControls.clock` and `TouchFixture.pass_time`).
- **Approach:** Wait for the state a test asserts inside a bound (a tick a frame, at most 30, then the same assertion),
  never for a count of frames, and when a suite a pull request did not touch goes red, run it six to eight times alone
  on the branch and on main before deciding whose fault it is; a new suite that reads the client runs ten times alone
  before it is called green. **Watch out for:** the test moved the dead away, ran two ticks and waited two frames, but
  the client's frame and the layer's read of it each land a frame later, so it failed 4 of 8 runs on main and landed
  green by chance; ten awaited `physics_frame` signals were nine or ten ticks of a pickup's spin. **Seen:**
  Deadnight #1296, 2026-11-05 (fix: Deadnight #1302, 0 of 12 runs failed); gdstudio #774, 2026-11-07 (the
  `pickup-feature` eval's own spin test).
