# Test speed

How to keep a GdUnit4 suite from running at the speed of the clock, from Deadnight's CI job that took 20 minutes
(Deadnight #524). The numbers and the suite-by-suite list are in the game's `docs/research/ci-time.md`.

## Measure first

The job log has a timestamp per line. A suite's time is the gap between its `Run Test Suite:` line and the next one
(its `before()` and `after()` included). Sort the gaps; the top twenty are the work. Run the whole suite locally the
same way only when nothing else is loading the machine: a loaded machine doubles unrelated suites.

## What makes a suite run at the clock's speed

| Cause | What to do |
| --- | --- |
| `await get_tree().physics_frame` per hand-stepped tick | switch the node's `_physics_process` off once and call its tick by hand, back to back; one `process_frame` per measurement |
| `create_timer(s)` to let an animation finish | wait the same game seconds at `Engine.time_scale = 10` and set it back to 1 before the next step (restore it in `after_test` too) |
| a batch of seeded runs bigger than the case needs | keep the full count where it is the gate; a case that proves the gate can fail needs a wall, not a statistic |
| a test about the engine's own callback, a socket or a freeze | leave it on the clock and say so in its first comment |

## What hand stepping needs

- **One physics step for new bodies, and `physics_frame` is emitted before it.** The physics server indexes a body on its
  next step, and the signal fires at the start of an iteration, before that iteration's step. After loading a room and
  after adding a collider or a body, `await get_tree().physics_frame` **twice**; then tick by hand. With none, a
  hand-ticked body falls through the floor; with one, it may stand but `move_and_slide` still costs ten times what it
  does once indexed (lessons: [ten times the cost](../lessons/2026-11-04-a-hand-ticked-body-cost-ten-times-more-until-a-physics-step-had-run.md),
  [falling through the floor](../lessons/2026-11-02-a-hand-ticked-player-fell-through-a-floor-no-step-had-seen.md)).
- **The same code path.** Call what the engine calls (`_physics_process`, or the node's public `tick`), with the same
  delta, so a faster suite plays the same game. A node whose `_physics_process` is switched off is not ticked twice.
- **Delta-sensitive comparisons stay in one kind of frame.** `move_and_slide` steps an idle frame by its wall-time
  delta; a recording made in a physics callback and replayed in an idle frame can differ by millimetres under load
  ([lesson](../lessons/2026-11-02-a-replay-in-an-idle-frame-missed-by-millimetres-on-a-loaded-machine.md)).
- **A changed tick rate is waited for by its delta, not by a frame count.** After `Engine.physics_ticks_per_second = hz`,
  await `physics_frame` until `get_physics_process_delta_time()` is `1 / hz`: a loaded machine runs several steps in one
  iteration with the old step
  ([lesson](../lessons/2026-11-03-a-tick-rate-test-read-the-old-delta-after-two-physics-frames.md)).
- **Prove it still tests.** Break the behaviour once, locally, and see each sped-up suite fail.

See also [a physics frame per tick](../lessons/2026-11-02-a-physics-frame-per-hand-stepped-tick-ties-a-test-to-the-clock.md)
and [Engine.time_scale](../lessons/2026-11-01-time-scale-also-scales-the-physics-step.md).

## Split the suite by seconds, not by folder

When a suite is too long for one CI job, split it over parallel jobs by the measured seconds of each test script, not
by folder: keep a file of seconds per script (the `Statistics:` line of each suite in the job log carries it), deal the
scripts longest first to the lightest shard, and let a script with no time yet count a default, so a new test lands in
a light shard by itself. Size the shard count from the total (`total / 480 s`, rounded up, plus a margin: runners vary
by 1.5x from job to job), have a self-test compare the shard count with the workflow's matrix, and end every shard with
a check that warns past 60 % and fails past 80 % of the job's time limit, so drift is red before the limit cancels a
job with no failing test (Deadnight #1015, `tools/ci_test_shards.py` and `tools/ci_shard_time.py`;
[lesson](../lessons/2026-11-04-a-hand-balanced-shard-list-went-stale-within-a-day.md)).

## Night suites: where the seconds go, and what may be cut

From Deadnight's ten slowest suites (#1017). All are hand-ticked already, so the time is compute; the numbers are from
one machine with 16 threads, and a shared machine moves a suite by 1.5x to 2x between two runs, so a before and after is
run interleaved, twice, and a change of waiting is counted in frames beside the seconds.

- **Look at what a tick spends before cutting ticks.** A night of four players and a crowd ran 3.7 ms a tick: 64 % in
  `server.move` (`move_and_slide` of the players, 0.24 ms for a body standing still), 15 % in the server's frame and the
  players' actions, 11 % in the bots' thinking, 4 % in the dead's. The 64 % was bodies the physics server had not yet
  indexed: after two physics frames it was 1.6 ms a tick and 0.02 ms a call, and every bot suite halved with no cut
  ([lesson](../lessons/2026-11-04-a-hand-ticked-body-cost-ten-times-more-until-a-physics-step-had-run.md)). Cut seconds
  and seeds only after that.
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
  and 12 failed one run in three
  ([lesson](../lessons/2026-11-03-a-fixed-frame-wait-for-a-navigation-mesh-failed-one-run-in-three.md)).
- **A sweep may stop a hop when the state is a fixed point, exactly.** The simulation reads only the state and the
  still world, so a tick that leaves the state unchanged under an unchanged command leaves every later tick unchanged.
  Prove it on the real sweep before relying on it: run all ticks, note the first fixed tick, and count the hops whose last
  state differs from it (0 of 19,667 on the midway sweep). Do not coarsen a sweep's grid instead: a trimmed grid passed
  on the map it was written to catch
  ([lesson](../lessons/2026-11-03-a-trimmed-sweep-test-passed-on-the-unfixed-map.md)).
- **Break it once, with a mutation that the cut test must still see.** For a seed cut, give a profile another profile's
  skill (a Rookie with the Veteran's reaction) and see the band fail on the fewer seeds; for a soak, take the safety
  constants out of the code and see the shorter night fail.

## Seat bots as the host does

A test that makes a `BotClient` by hand copies `BotHost.seat`: the shared `bot_ids` table and team, not only what compiles.
Without the table each bot takes its neighbour for a person and a team order (Hold, a ring about a spot) collapses; a
flake of 3 cm over a bound was the symptom
([lesson](../lessons/2026-11-03-a-bot-test-seated-its-bots-without-the-host-s-table.md)).

## One clock per test

A test that holds packets for real milliseconds (a `LinkConditioner`, a ping) while its loop counts physics frames has
two clocks, and a slow runner pulls them apart. Give the real-time part an injectable clock driven by the frame count
(Deadnight's `WebSocketLink.clock`), count every wait in frames, and prove it by slowing each frame with
`OS.delay_msec`: the numbers of the run must not move
([lesson](../lessons/2026-11-02-a-bad-network-test-waited-in-wall-seconds-while-the-game-ran-in-frames.md)).
