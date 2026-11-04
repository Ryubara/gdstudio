# Performance budgets: profile the worst case from the first playable night

What Deadnight's issue #906 taught about knowing a game's limits. The game's own numbers are on
`docs/research/performance.md` there; this page is what every game should do, and the traps.

A maintainer playing round 12 at triple intensity with three bots said the game lagged, that nobody knew its limits,
and that "performance needs to be taken into consideration at all times ... this should've been something that was
done during the start". The earlier performance work had measured the web build and a bare crowd, never the whole
night at its harshest setting, and nothing in CI would have noticed a cost that grew.

## The rule

From the first playable night a game has three things, and a change that breaks one does not merge:

1. **A worst-case run.** The harshest combination the game lets a player ask for: the latest round, the most
   players (bots count), the strongest intensity setting, the biggest crowd the platform's ceiling allows. It is a
   command (a bench scene or an autopilot argument), not a recipe in someone's head.
2. **A budget file** (counts and ratios, below) the run is held to in CI.
3. **A page of limits**: for each system the most it may hold on a desktop and on a phone, what it costs now, and
   what the game does past it (a cap, a pool that recycles, a level of detail). A system without a limit is a
   system whose limit nobody knows until a player finds it.

## What to sample

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

## Reading a timing on a shared machine

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

## A leak is read as a count at the same crowd, round after round

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

## Budgets: counts tight, time loose

`tools/perf/budget.json` (Deadnight) holds for the worst case: the most of each count while the crowd stands, how much
a count may grow a minute over the steady rows, and the ratio of the frame to the calibration. `check_budget.py` reads
the run's report, prints every number it judged and exits 1 with the ones over. Set a limit from three measured runs
plus a margin, say what the margin is, and write the *target* beside it on the limits page when they differ: the
limit stops a regression, the target is what the game should reach.

## In the editor

The pinned Godot is a debug build, so a game run from the editor costs about what a run with `godot --path` costs (a
release export was not measured: do that before promising a frame rate). The editor adds the debugger link and, with its
Remote scene tree open, a walk of every node of the running game each time it refreshes (a night at round 12 holds 5 000
to 5 800 nodes; one walk of them in script took 8 to 10 ms on a loaded machine). To judge lag, close the Remote tab or
run the game outside the editor.
