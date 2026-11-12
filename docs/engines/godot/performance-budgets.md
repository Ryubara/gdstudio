# Performance budgets: profile the worst case from the first playable night

What Deadnight's issue #906 taught about knowing a game's limits. The game's own numbers are on
`docs/research/performance.md` there; this page is what every game should do, and the traps.

A maintainer playing round 12 at triple intensity with three bots said the game lagged, that nobody knew its limits,
and that "performance needs to be taken into consideration at all times ... this should've been something that was
done during the start". The earlier performance work had measured the web build and a bare crowd, never the whole
night at its harshest setting, and nothing in CI would have noticed a cost that grew.

## The rule {#the-rule}

From the first playable night a game has three things, and a change that breaks one does not merge:

1. **A worst-case run.** The harshest combination the game lets a player ask for: the latest round, the most
   players (bots count), the strongest intensity setting, the biggest crowd the platform's ceiling allows. It is a
   command (a bench scene or an autopilot argument), not a recipe in someone's head.
2. **A budget file** (counts and ratios, below) the run is held to in CI.
3. **A page of limits**: for each system the most it may hold on a desktop and on a phone, what it costs now, and
   what the game does past it (a cap, a pool that recycles, a level of detail). A system without a limit is a
   system whose limit nobody knows until a player finds it.

- **Approach:** Name the platform every performance cap was measured on, measure each shipped platform (desktop client,
  browser, headless server, network) and give each its own number. **Watch out for:** a crowd ceiling measured on the
  web build (40) became the one ceiling everywhere, so desktop, which should hold over 100 zombies on a fast machine,
  never had a budget of its own. **Seen:** Deadnight, 2026-11-01 (fix: a limit per platform on the page of limits).
- **Approach:** From the first playable night, measure, write down and hold in CI a game's limits (dead, lights, sounds,
  nodes, memory, a frame) at the worst combination of its own settings: one command for the worst case, a sampler of
  counts and labelled times, a budget file (counts tight, time as a ratio of a calibration loop) and a limits page.
  **Watch out for:** earlier work measured the web and a bare crowd, never the whole night at round 12, 3x, bots; a
  hosted bot capped a desktop night at 40 dead against 120 designed, and wall times on the shared machine ran 1 to 14
  times the code's cost. **Seen:** Deadnight #906, 2026-11-03 (fix: this page).

## What to sample {#what-to-sample}

One row a second, from the running night, in a node that costs nothing when it is off:

- Engine monitors: `Performance.TIME_PROCESS`, `TIME_PHYSICS_PROCESS`, `TIME_NAVIGATION_PROCESS`,
  `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`, `OBJECT_COUNT`, `OBJECT_NODE_COUNT`,
  `OBJECT_ORPHAN_NODE_COUNT`, `OBJECT_RESOURCE_COUNT`, `MEMORY_STATIC`, `RENDER_TEXTURE_MEM_USED`,
  `PHYSICS_3D_ACTIVE_OBJECTS`. (Draw calls read 0 headless.)
- What the game has standing: the dead, lights on, particles emitting, decals, sounds playing, skeletons, mesh
  instances. One walk of the tree a second.
- Labelled script time: `PerfProbe.begin()` / `end(&"label", began)` around each system (the server's tick, the
  client's apply, the bots, the views), added to the frame's total and written beside it. A label that nests in
  another is read as part of it, not added to it. Add a label before guessing which system is slow.

- **Approach:** Time one frame's work as the span from the frame's first `physics_frame` signal to the `_process` of a
  node whose `process_priority` is the highest (it runs after every other node), and take the median of a few hundred
  frames; the same code reads it headless and in a browser. **Watch out for:** in 4.7.2 `Performance.TIME_PROCESS` plus
  `TIME_PHYSICS_PROCESS` read every frame gave 0 to 189 ms for frames of 0.2 to 5 ms (they are not the frame's own
  times), `RenderingServer.frame_pre_draw` is never emitted headless, and a browser's frame-to-frame wall time is the
  display's 16.7 ms whatever the work. **Seen:** gdstudio #926, 2026-11-10 (`tools/bench/parts_cost_bench.gd`,
  `tests/gameplay/test_parts_budget.gd`).
- **Approach:** Profile a per-character step by module with a copy of the step cut into its parts, each part run over
  the whole crowd before the next and timed once, beside the real step in alternating blocks (its sum should match),
  and serve the web export with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy:
  require-corp` so `performance.now()` steps 5 µs (the single-threaded export runs the same). **Watch out for:** one
  module of one body is 0.5 to 12 µs in Chrome, under the page's 100 µs clock step when it is not cross-origin
  isolated, and the copy drifts from the real step when the step changes: print both. **Seen:** gdstudio #1059,
  2026-11-11 (`tools/bench/ai_step_profile.gd`: the sum read 40.4 µs against a real 42.3).

## A timed function must not hold what it is handed {#a-timed-function-must-not-hold-what-it-is-handed}

A reference to an event kept between calls (the last frame, a snapshot) makes the *next* call release the old one, and
that release (a tree of dictionaries, arrays, vectors) is charged to the label that happens to be running. Deadnight
1172: storing the last frame in the challenge tracker raised `server.challenges` by about a quarter and failed the
late-round budget while the work itself had not grown. Keep no event; read what is needed in the call that is handed
it, or from state the system already owns. Test a change to a timed system with the budget's own case, three or more runs
interleaved with the change off.

## Reading a timing on a shared machine {#reading-a-timing-on-a-shared-machine}

The machine that builds a game is never quiet: other agents' Godot processes, builds, a browser. Deadnight's
measurements ran at 88 to 100 % of 16 cores with 20 to 46 Godot processes up. Two runs of the same code in the same
arm differed 14 times (8 ms and 115 ms a frame at 45 dead). What helped:

- **Count what does not depend on load**: nodes, objects, resources, orphans, draw calls, bodies, memory. They are
  the same on every machine at the same seed, so they are what a budget holds tight and what a leak is read from.
- **Measure time as a ratio.** Time a fixed piece of script (a loop of arithmetic, array and dictionary work, the kind
  the game does) in the same process, again every few seconds, and hold a frame to a multiple of it. A slow runner and
  a busy machine both scale the frame and the loop. It catches a regression; it is not a frame rate.
- **Take a median, not a mean**: a frame the machine took the processor away from moves a mean and not a median.
- **A headless run's wall time under load means nothing** (it was slower than the windowed run of the same night, and
  14 times worse in the worst of three). Run headless at `--fixed-fps 60`, which makes each frame one tick, and read
  the labelled script times, or the process's CPU seconds a tick (polled from outside: `Win32_Process` kernel plus user
  time), which stay near the cost of the work.
- **To judge a code change, put the old code beside the new in one process.** Copy the old script under another class
  name (`git show HEAD:path | sed 's/class_name X$/class_name XOld/'`), feed both the same scripted input, alternate
  which goes first each step, and compare the *median of the per-step times* and the state after every step. Deadnight
  #947: the same 15 % cut read -11 %, +9 % and -18 % across separate processes and 0.82 to 0.85 in every repeat this
  way. Nights differ in what the crowd is doing, so a real night gives counts, not a before and after.
- **Record the load beside the run**: Godot processes at the start and end, machine CPU % every 5 s, GPU %. A number
  without them cannot be compared with another day's.
- **Interleave before and after** (one, the other, one, the other), so a busy hour falls on both. Report the spread of
  all repeats, not the best.

- **Approach:** Hold a wall-clock tick budget on a shared machine at a percentile below the scheduler's share of lost
  ticks (the 95th), print the 99th and the worst without judging them, and compare medians to tell the code from the
  machine. **Watch out for:** a "worst tick under 1.5 ms" passed alone and read 3 to 70 ms with other jobs running, and
  a 99th percentile failed too: bots think one tick in six, so it lands on preempted think ticks. **Seen:** Deadnight
  (bot server cost), 2026-11-02 (fix: the 95th judged, with the reason in the test's header); gdstudio #1111,
  2026-11-11 (`test_net_server_cost.gd` read 10.3 ms against its 6 ms budget in a full template run while the same
  agent ran eight Movie Maker captures beside it, and passed alone: start captures after the full run ends).
- **Approach:** Before putting a slower page on the machine's load, compare it with a control in the same page (a cell
  the change cannot touch, measured in the same rounds) and with a run where the machine was quieter. **Watch out
  for:** browser pages whose every skinned body read twice its cost were put down to 100 % processor load for an
  hour; the same pages on a quieter machine still read twice, and the cause was a GL buffer state the bench set in
  some pages and not others ([the buffer hint](web-export.md#skin-buffer-hint)). **Seen:** gdstudio #1260,
  2026-11-11.

## A leak is read as a count at the same crowd, round after round {#leak-count}

Run the night for as long as a player would (30 minutes), sample every second, and compare rounds, not times:

- Nodes, objects, resources and orphans at the **same number of dead** must stay flat. A pool that fills to its limit
  and stops (Deadnight parks up to 12 bodies of each look: skeletons grew 24 to 65 and then stayed) is not a leak;
  growth after the pools are full is.
- **The harness leaks too.** A per-frame list of `[ms, round, dead]` (108 000 frames in 30 minutes) and the sampler's
  own rows grew the static memory about 1 MB a minute, which looked exactly like a leak in the game. Run the long
  night with the per-frame rows off and keep the sampler's rows small; only then does `MEMORY_STATIC` say anything
  about the game.
- A round that does not end (one dead left that nobody finds) makes a long soak useless after it: stop at a stalled
  round and report it.

## Budgets: counts tight, time loose {#budgets-counts-tight-time-loose}

`tools/perf/budget.json` (Deadnight) holds for the worst case: the most of each count while the crowd stands, how much
a count may grow a minute over the steady rows, and the ratio of the frame to the calibration. `check_budget.py` reads
the run's report, prints every number it judged and exits 1 with the ones over. Set a limit from three measured runs
plus a margin, say what the margin is, and write the *target* beside it on the limits page when they differ: the
limit stops a regression, the target is what the game should reach.

**The ruler must follow the thing measured.** A fixed loop of arithmetic follows a frame (many thousands of
microseconds of mixed work) but not a section of a few microseconds that runs cold once a frame: across 46 CI runs a
timed section went with the frame at a slope of 1.0 and with the calibration at 0.35, and a limit as a ratio of the
calibration swung 2.1 times between runners that ran the same code (a false red, and a section twice as slow that
passed). Hold such a section as a *share of the frame* the same rows took.

- **Approach:** Test a loop held by a count and a time budget on the count it promises per frame, and wait for the
  slowest pace the time budget allows (one item a frame), never for the pace the count alone gives. **Watch out for:**
  `AiReplica` makes up to 4 puppets a frame and stops after 4 ms; the test waited 12 frames for 40 puppets, and a CI
  runner where one dressed character takes 4 ms made one a frame, so main went red on unchanged code. **Seen:**
  gdstudio #1230, 2026-11-11 (fix: the wait is one frame per puppet; `most_made` still checks the count).
- **Approach:** Divide a section of a few microseconds by the frame the same rows took, not by the calibration loop:
  fit the log of the timing on the log of each candidate divisor over the last runs (slope near 1 cancels the host), put
  the limit between the highest share seen and twice the lowest, and test the checker on made-up reports of every kind
  of runner, unchanged (passes) and twice as slow (fails). **Watch out for:** over 46 CI runs the section followed the
  frame at slope 0.98 and the calibration at 0.35; runners come in three kinds the loop tells apart (3.1, 4.5, 6.0 ms)
  where the section costs the same, so a ratio of the calibration swung 2.1 times: a false red on unchanged code, and a
  section twice as slow that passed. **Seen:** Deadnight, 2026-11-05 (fix: the spread fell from 2.1 to 1.36 times; a
  unit test of the checker fails a moved limit).
- **Approach:** Fix every input of a count bench: the seed, the step, the crowd and whatever the measured code reads
  from the machine (the date, the time of day, a system seed), through the seam a test already uses; set the limit from
  the pinned run, and before trusting it run the bench with the date moved by a day. **Watch out for:** accounts were
  dealt daily challenges from the machine's clock, which three are dealt decides how often a challenge advances, and a
  limit set one day (0.13) failed every pull request the next (0.23 against 0.18); raising the limit hides it.
  **Seen:** Deadnight, 2026-11-07 (fix: `ChallengeClock.fixed` set before the first account; a test deals one account
  three machine dates and expects the same dailies).
- **Approach:** Read a rate limit on a fixed-step run in the run's own time (frames stepped at the budget's
  `fixed_fps`), never the wall clock; before a limit moves for a red rate, print the rate over two other nights and the
  wall seconds of the same window (seconds differing by 1.5 times or more make the unit the suspect). **Watch out
  for:** the leak check fitted its line through the sampler's wall-clock `t`: the same 1,079 steady rows took 280 to 553
  s on different machines, so the same growth read 1.0 to 2.2 MB a minute and a limit was wrongly raised to 2.5, while
  per minute of the night it was 0.4 to 0.6 on all six nights. **Seen:** Deadnight #1319, 2026-11-06 (fix:
  `leak_budget.json` has `fixed_fps: 60` and the limit is back at 1.5; `tools/perf/test_check_budget.py` runs a flat
  night and 1.2 and 0.5 times each limit on a fast and a slow runner).
- **Approach:** In a cost gate, time the calibration loop several times inside the measured window, hold the median
  of the section over the median of the loop (a few-microsecond section as a share of a frame-sized one on the same
  ticks), and set each limit between the highest ratio seen with a second suite beside it and twice the lowest; prove a
  2x wait fails. **Watch out for:** one calibration and means read the AI step at 3.2 one day and 4.5 the next on the
  same code; a 2-microsecond record swung 2.7 times against the loop; a 0.12 ms ruler timed every tick did not follow
  load at all; a `sin` loop ran 1.65 times faster on the Linux runner while the AI cost the same, and CI failed.
  **Seen:** gdstudio #1248 (`test_ai_cost_gate.gd`), 2026-11-11 (fix: medians, a ruler of vector, array and
  dictionary work, a 2x wait failing every row).

- **Approach:** Make a part that only some characters use (a weapon's model in the hand) when it is first needed (a
  `WeaponDef.view_scene` the loadout instances on `give()`), not as a node of the shared character scene. **Watch out
  for:** the rifle's hold put in `character_dressed.tscn` added 32 nodes (the two levels of the rifle, its sockets,
  the markers) to every living character, rifle or not, and `test_parts_budget.gd` refused 78 against 46. **Seen:**
  gdstudio #889, 2026-11-10 (fix: `rifle.tres`'s `view_scene`).

## In the editor {#in-the-editor}

The pinned Godot is a debug build, so a game run from the editor costs about what a run with `godot --path` costs (a
release export was not measured: do that before promising a frame rate). The editor adds the debugger link and, with its
Remote scene tree open, a walk of every node of the running game each time it refreshes (a night at round 12 holds 5 000
to 5 800 nodes; one walk of them in script took 8 to 10 ms on a loaded machine). To judge lag, close the Remote tab or
run the game outside the editor.
