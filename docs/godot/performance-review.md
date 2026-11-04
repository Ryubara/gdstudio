# Performance review

From the review of Deadnight #907, after the maintainer asked (Deadnight #906 and #907) for the places that "will
definitely lag the game" and said performance "needs to be taken into consideration at all times". The reviewer agent
reads this page for every pull request; an author reads it before adding work that runs every frame. The review's
findings are Deadnight #929 to #936 and #938.

Performance is reviewed in every pull request: by reading the diff for the cost it adds, and by measuring the cases the
diff could make worse. The author states the cost; the reviewer checks it.

## The rule

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
   - Resources made per spawn (`Mesh`, `Material`, `Shader`) are shared unless each really needs its own.
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
- **Leaks**: nodes, objects, resources and memory sampled every second over five minutes from the worst round (flat once
  the pools fill), and over four nights back to back (each returns to the baseline node count). Count the grenades,
  blast kills, hits and doors in the same run.
- **Spikes**: the largest single tick after an event (cripple 20, buy a door, a blast kills 20), not the mean.
- **Stop a run by its own process id, never by program name**, on a shared machine.
- An editor run is a debug build with the debugger; take the budget from headless runs and from an export.

## Standing questions for any review

What does this cost with 120 dead and 7 bots? What frees it? What did the diff not measure?
