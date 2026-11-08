# Performance review

From the review of Deadnight #907, after the maintainer asked (Deadnight #906 and #907) for the places that would
clearly lag the game and for performance to be weighed at all times. The reviewer agent
reads this page for every pull request; an author reads it before adding work that runs every frame. The review's
findings are Deadnight #929 to #936 and #938.

Performance is reviewed in every pull request: by reading the diff for the cost it adds, and by measuring the cases the
diff could make worse. The author states the cost; the reviewer checks it.

## The rule {#the-rule}

A pull request that adds **per-frame or per-tick work, a run-time spawn, a light, a particle system, a shader, a draw
call, a sound or a network message** has a `## Cost` section in its description:

- what runs, how often (per frame, per tick, per event) and **what it scales with** (the dead, the players, the bots,
  the lamps);
- the number: a `PerfProbe` label or a count, before and after, at the platform ceiling (the most dead the platform
  allows, with the bots on);
- what frees or pools it, and the test that shows the node, object and resource counts flat after N events;
- the platform it was measured on (desktop, web, phone, headless server). A cap or a budget names the platform it holds
  for.

The reviewer opens one issue per finding, with file:line, the cost, how it scales, how sure, and the fix, and attaches
the probe output.

- **Approach:** State a change's cost when it is made (per frame, per spawn, per light, and what it scales with) in a
  `## Cost` section of its pull request, make every run-time spawn free itself or come from a pool, with a test that the
  node count is flat after N events, and measure one tick of the real night with the bots at the ceiling. **Watch out
  for:** the desktop ceiling was set from the server step and the client draw with no bots, HUD or client script, and a
  one-shot blast effect faded to alpha 0 and was never freed. **Seen:** Deadnight #906, 2026-11-03; Deadnight #907,
  2026-11-03 (fix: the checklist on this page (Deadnight #929, #930;
  [lesson](../../lessons/2026-11-03-a-one-shot-effect-from-the-range-was-never-freed-in-the-night.md))).

## Checklist (read the diff for each)

1. **Per frame and per tick**
   - New `_process` / `_physics_process`, or a signal handler that runs on every `frame` event? Count the listeners; a
     `match` that returns is cheap, a loop over the crowd is not.
   - A `Dictionary`, `Array`, `String` or `Callable` made every frame (`str()`, `%`, `"a" + b`, `.filter()`,
     `.values()`, `.keys()`, a literal `[]` in a loop)?
   - `find_children`, `find_child`, `get_nodes_in_group`, `get_node`, `get_node_or_null` or `load()` inside something
     that runs every frame? Cache it at setup.
   - `queue_redraw()` every frame? Redraw when a key of what is drawn changes (the step of an animation, the held
     buttons), never on the clock. Each `draw_circle` / `draw_arc` is a polygon the renderer rebuilds (#834).
   - Work done **at a higher rate than the data changes** (60 Hz tick, 30 Hz sim)? Work done **once per consumer** that
     could be done once per process (every `ClientState`, every bot decoding the same bytes)?
   - Anything O(n) over the dead per tick per listener, and anything O(n^2): a pair loop needs a grid or a cap.
   - A list or table built from the dead and **cached on a version number** (a sim revision)? Every writer of what it
     is built from bumps the number, test rigs that move a body by hand included, and a test compares the cached list
     with a fresh one on every tick of a seeded run (Deadnight #931).
2. **Queries**
   - A physics ray, shape cast or `get_rest_info` per dead, per bone or per frame? Budget them per second with a
     staggered timer (the repath of the dead, `QUERY_BUDGET` of the bots, the audio occlusion ray per start).
   - A navigation path or closest-point query per entity per frame? The same: an interval, far entities slower.
3. **Spawns and lifetime**
   - Every `.new()`, `instantiate()`, `create_tween()`, `Timer` and `add_child` at run time has a **free** (`queue_free`
     after the last tween, a tween callback) or a **pool with a cap**. "It fades to alpha 0" is not freed: the draw
     call, the node and the light stay (#929).
   - Pooled things return to the pool; a pool past its cap takes over the oldest; nothing is made while the night is
     played (prewarm).
   - A signal connected to a lambda or a `Callable` of a longer-lived object is disconnected when the owner goes.
   - Resources made per spawn (`Mesh`, `Material`, `Shader`) are shared unless each really needs its own. A
     `SphereMesh` defaults to 64 x 32 segments (4,224 triangles); a dot or a small orb is 8 to 12 segments.
   - Many identical short-lived things that fade (a trail of dots, sparks, markers) are **one `MultiMesh`**, not a
     node each: one shared low-poly mesh, one shared material with `vertex_color_use_as_albedo` and alpha
     transparency, the fade in each instance's colour alpha, a ring with a cap that takes over the oldest, aged by the
     simulation's step. Write the instances as one `PackedFloat32Array` (16 floats an instance with colours: the 3 x 4
     transform rows with the origin as the fourth column, then the colour) and set `multimesh.buffer` once a step; hide
     the node when none is alive and give it a `custom_aabb`. Measured in Deadnight #936: 166 objects and 27 draw
     calls at the peak of a 3 s flight became 2 objects (1 per throw) and 1 draw call, flat over 12 throws. The class
     holds the shared mesh and material and the warm-up draws it once.
4. **Rendering (Compatibility)**
   - Draw calls the change adds, and whether the batching of the lot still holds. A transparent mesh at alpha 0 still
     costs its draw call.
   - Lights: each `OmniLight3D` / `SpotLight3D` counts against the **8 per mesh** and the per-frame renderable cap; a
     light at energy 0, or one nobody hides, still counts. A fight has two slots (flash, blast) in the light cap test.
   - Fill: quad size on screen x the per-pixel work of the shader (loops, `sin`, `atan`) x how many are alive at once;
     additive and alpha-blended overdraw; `hint_screen_texture` and `hint_depth_texture` (a back-buffer copy).
   - A new shader or material variant needs a draw in the warm-up, so its programs are not linked in the middle of a
     night ([First-use hitches](first-use-hitches.md)).
   - Particles: a program of their own on the web; cap the amount.
   - UI drawn in `_draw`: count the draw calls (hide a node, count again). Every polygon, polyline, circle and arc is a
     call and ends the batch around it, and a label with an outline and a shadow is four
     ([Canvas draw calls](canvas-draw-calls.md)).
5. **Audio**: new sounds go through the voice budget and `starts_per_frame`; long ones are deferred-decoded, not decoded
   on first play.
6. **Network**: a message per entity per frame is a message per entity per tick per player; send at the rate the data
   changes, in deltas, inside the interest radius.
7. **Web and phone**: no per-frame JavaScript bridge read or write in the shipped build (probes only under `?probe`);
   redraw by key (heap); measure fill with SwiftShader and CPU with a throttle, interleaved, never one setup once
   ([frames on the web and the phone](web-phone-frames.md)).

## How to measure it (counts first)

- **A tick of the real night, with the bots on, at the platform ceiling**, headless, `--fixed-fps 60`: `PerfLog` rows
  (`dt`, `objects`, `resources`, `nodes`, `orphans`, `usec`, `counts`) and `PerfProbe` labels summed over the ticks
  where the crowd is at 85 % of the cap. Report the sum against 16.7 ms and the share of each label. Give anything new a
  label (`PerfProbe.begin` / `end` / `count`).
- **Counts over timings** on a shared machine: nodes, objects, resources, orphans, draw calls, decode calls per tick,
  `queue_redraw` calls, rays per second. A time is a ratio between two arms run together.
- **A test that counts objects** reads `Performance.get_monitor(Performance.OBJECT_COUNT)` (and the node, resource and
  orphan counts) before and after, and asserts afterwards: a GdUnit assertion is an object of its own, so one inside the
  counted loop adds to the number it checks.
  The counts are the whole process's: assert growth (`is_less_equal(before)` or `before + SLACK`), never `is_equal`, or
  an earlier suite's free fails a test that leaked nothing.
  A count taken across `await process_frame` also starts from a quiet `Audio` service: the deferred sounds an earlier
  suite queued decode a few milliseconds a frame and each is objects. Deadnight's `AudioSettle.until_idle` waits for
  the queue, and a warm item (one label, one effect) is made and freed before the first reading
  ([lesson](../../lessons/2026-11-04-a-count-test-that-skipped-the-audio-queue-failed-on-main.md)).
  A live fight or menu holds objects of its own that come and go (a Tween with its tweeners is 3 to 5 objects, a
  sound that plays 2, the last playback of every voice stays until it is used again, the main menu loads every sound in
  the background), so never take the peak over frames against a start: stand the source still and read at a quiet
  moment before and after (Deadnight `QuietCount.settle`; `AudioSettle.until_idle` also ends the background load)
  ([lesson](../../lessons/2026-11-04-a-count-test-read-a-peak-while-the-fight-and-the-menu-kept-moving.md)).
  A count that only *falls* by a few objects is the suite before's sounds ending (each frees its playback in a frame
  of its own): call `QuietCount.settle` as well as `AudioSettle.until_idle`, and find the suite by running the shard's
  list in CI order and halving it
  ([lesson](../../lessons/2026-11-04-a-count-fell-while-the-last-night-s-sounds-ended.md)).
  The same fall hides a leak from a test that bounds the count only upwards: settle in every suite that reads the
  object count across frames (a scan test fails the one that does not), and inject a leak to see a count test fail
  ([lesson](../../lessons/2026-11-04-a-count-bounded-upwards-passed-a-leak-under-the-fall.md)).
  `OBJECT_RESOURCE_COUNT` counts only resources that have a path: what code makes (`StandardMaterial3D.new()`,
  `BoxMesh.new()`) shows in `OBJECT_COUNT` alone.
- **Leaks**: nodes, objects, resources and memory sampled every second over five minutes from the worst round (flat once
  the pools fill), and over four nights back to back (each returns to the baseline node count). Count the grenades,
  blast kills, hits and doors in the same run.
- **Spikes**: the largest single tick after an event (cripple 20, buy a door, a blast kills 20), not the mean.
- **Free disk first** (`df -k /c`): an import on a full disk writes truncated files and tracked `.import` files with
  `valid=false`, and the run then fails with "corrupt" errors far from the cause
  ([lesson](../../lessons/2026-11-04-an-import-on-a-full-disk-left-truncated-files-that-read-as-corrupt.md)).
- **Stop a run by its own process id, never by program name**, on a shared machine.
- An editor run is a debug build with the debugger; take the budget from headless runs and from an export.

## Standing questions for any review

What does this cost with 120 dead and 7 bots? What frees it? What did the diff not measure?

## Counting allocations in a pass (a bench, not a guess)

A per-step `Array`, `Dictionary` or `values()` copy is invisible in a time on a loaded machine (the saving is a few
percent) and plain in bytes. In a build that tracks memory (the pinned editor build, a debug template) count the most a
call holds at once:

1. Allocate a ballast, a `PackedByteArray` of `OS.get_static_memory_peak_usage() - OS.get_static_memory_usage() + 4096`,
   so the live memory stands at the old peak (the peak only goes up, and never comes down to measure from).
2. Read the peak, run the call, read the peak again. The difference is what the call held above where it began; free
   the ballast. A pass that makes nothing prints 0.

Deadnight's `tools/bench/separation_cost.gd` does it (6,224 B before, 0 after for the separation pass of 120 dead) and
`test_zombie_separation.gd` asserts it, skipping when the peak reads 0 (a build that does not track memory). Run the
same bench file on a detached checkout of the commit before and on the branch, alternating, and give the medians.

Faster in GDScript: what the engine does natively. A hash table written in GDScript (probing, stamps) lost four to one
to `Dictionary.get`; a `PackedInt64Array` of `key * 65536 + index` that the engine `sort()`s, with `bsearch()` for the
run of a cell, beat the dictionary and allocates nothing. A `for id in dict` walks a dictionary without the copy that
`.values()` and `.keys()` make; a packed array handed round in GDScript is shared, not copied.
