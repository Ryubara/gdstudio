# Zombie crowds: animation, navigation and frame cost

**Spike** for [issue #9](https://github.com/Ryubara/gdstudio/issues/9): can a browser game run 20 to 40 animated
zombies that chase players? Measured in Godot 4.7.2 (Compatibility renderer) with the Quaternius "Zombie" (CC0).
The code is in `sandbox/crowds/` (throwaway; read it for the setup, do not copy it into a game).

**Recommendation in one paragraph.** Plan for **40 zombies on screen at most, 20 to 30 as the normal wave**, and
build them with the cheap setup below from the start (repath timer, animation throttle, 30 Hz physics, trimmed
bones, one mesh per zombie). On the machine measured, the browser then runs 40 zombies in 4 to 7 ms and 80 in about
5 ms. The same crowd with no care costs 17 to 19 ms at 40 and 37 to 44 ms at 80 in the browser: the naive version only
just holds 40 and only on a fast machine. Budget a player machine 2 to 4 times slower, which is why 40 is the ceiling
and not the target. In the browser the three techniques that matter are the **animation throttle, one mesh per
zombie (draw calls) and a 30 Hz physics tick**; trimming bones and repath timers help the desktop only.

## What was built {#what-was-built}

| Part | Setup |
| --- | --- |
| Model | `Zombie` by Quaternius, CC0: 7,570 triangles body plus a 252-triangle eyelid mesh, one skeleton of 50 bones, 16 clips |
| Per zombie | `CharacterBody3D` (capsule, collides with the floor only) + model + `AnimationTree` + `NavigationAgent3D` |
| AnimationTree | a blend tree: `Walk` and `Run` mixed by the zombie's speed (`Blend2`), `Punch` fired as a `OneShot` when in reach |
| Navigation | a navmesh baked in code from the static colliders (floor plus 6 boxes), RVO avoidance on, 2D avoidance |
| Chase | the target walks a circle of radius 12 m at 2.5 m/s; zombies start 8 to 26 m away at 1.6 to 4 m/s, then pack around the target, which is the worst case for avoidance |
| Camera | looks down at 11 m up and 10 m back; the crowd fills the view |
| Test mode | seeded (`seed 42`), `--fixed-fps 60` so the simulation does not depend on frame time; frame time is wall clock |

Each run waits 300 frames, then records 400. "Frame time" is the mean wall-clock time between frames with vsync off,
so it is the cost of one frame of work. **Baseline** is the plain setup: every zombie sets its target every physics tick,
default avoidance settings, every `AnimationTree` updated every frame, 60 Hz physics, full skeleton, both meshes.

## Numbers {#numbers}

Machine: Windows 11, RTX 5080, a fast desktop. Other agents were using the same machine while the runs went, so
single runs are noisy: three repeats of 40 zombies, baseline, gave 6.32, 6.48 and 6.55 ms, but the 80-zombie rows can
move by 1 ms or more. Read differences under 10 % as noise.

### Desktop, full frame (ms per frame, mean) {#desktop-full-frame-ms-per-frame-mean}

| Setup | 10 | 20 | 40 | 80 |
| --- | ---: | ---: | ---: | ---: |
| empty scene (0 zombies) | 0.72 | | | |
| baseline | 2.31 | 3.44 | 6.48 | 12.33 |
| avoidance off | 2.09 | 3.21 | 5.71 | 11.89 |
| repath every 0.25 s, staggered | 2.28 | 3.59 | 6.55 | 11.33 |
| avoidance tuned (`neighbor_distance` 3, `max_neighbors` 5) | 1.88 | 3.66 | 7.07 | 12.11 |
| animation throttle by distance and view | 1.93 | 3.12 | 5.23 | 10.53 |
| visibility range 32 m | 2.26 | 3.48 | 6.47 | 12.57 |
| fewer bones (see below) | 1.94 | 2.81 | 5.41 | 9.86 |
| no eyelid mesh | 2.11 | 3.14 | 5.29 | 12.53 |
| physics at 30 Hz | 1.77 | 2.87 | 4.68 | 10.18 |
| **all of the above** | **1.23** | **1.99** | **2.69** | **5.33** |
| baseline plus a shadow-casting sun | | | 7.04 | |

95th percentile at 80 zombies: baseline 15.3 ms, all techniques 9.0 ms. Draw calls at 80: 164 baseline, 81 with the
eyelid removed (two meshes per zombie become one). A shadow-casting sun takes 40 zombies from 84 to 338 draw calls.

### Desktop, script and engine work only (headless, no rendering; ms per frame) {#desktop-script-cost}

| Setup | 10 | 20 | 40 | 80 |
| --- | ---: | ---: | ---: | ---: |
| baseline | 1.11 | 2.00 | 3.87 | 7.76 |
| avoidance off | 0.95 | 1.88 | 3.39 | 6.75 |
| repath every 0.25 s | 1.08 | 1.99 | 3.65 | 7.37 |
| animation throttle | 0.95 | 1.64 | 3.27 | 6.13 |
| fewer bones | 0.98 | 1.53 | 2.91 | 5.82 |
| physics at 30 Hz | 0.73 | 1.34 | 2.56 | 5.69 |
| all | 0.42 | 0.73 | 1.47 | 3.11 |

Headless is about two thirds of the full frame: **a zombie costs roughly 0.1 ms of animation, navigation, physics and
script, and 0.05 ms of rendering** on this machine, so both sides matter. Cost grows linearly with count in every row.

### Browser (the real target: web export, single-threaded, Chrome, same machine) {#browser-cost}

Exported with the pinned templates (`variant/thread_support=false`), run by `sandbox/crowds/web_bench.py`. The display
refreshes at 240 Hz, so **4.17 ms is the floor** of this table: a cell at 4.2 means "at least this fast".
Two full runs per cell are shown as `first / second`.

| Setup | 10 | 20 | 40 | 80 | 160 |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline | 4.31 / 4.47 | 9.38 / 7.04 | 19.10 / 16.70 | 44.45 / 36.51 | |
| all techniques | 4.17 / 5.51 | 4.17 / 4.17 | 6.60 / 4.17 | 5.27 / 5.21 | 19.76 / 17.67 |

Single techniques at 80 zombies in the browser (one run each, mean ms):

| Setup | Mean ms | 95th percentile | Draw calls |
| --- | ---: | ---: | ---: |
| baseline (two runs) | 44.45 / 36.51 | 58.2 / 48.5 | 156 |
| **animation throttle** | **18.09** | 28.3 | 161 |
| **no eyelid mesh** | **25.79** | 34.8 | 83 |
| **physics at 30 Hz** | **30.44** | 39.2 | 161 |
| repath every 0.25 s | 38.16 | 51.0 | 157 |
| avoidance tuned | 38.43 | 50.5 | 159 |
| visibility range 32 m | 38.28 | 49.5 | 157 |
| fewer bones | 37.73 | 50.8 | 156 |
| avoidance off | 42.76 | 60.0 | 159 |
| all together (two runs) | 5.27 / 5.21 | 9.2 / 8.9 | 62 |

The browser is **about 3 times slower than the desktop build** at the same count (80 zombies baseline: 12.3 ms
desktop, 36 to 44 ms browser). 95th percentile with all techniques at 80: 8.9 to 9.2 ms; at 160: 27 to 30 ms.

## What each technique does {#what-each-technique-does}

Desktop and browser disagree on the order, and **the browser is the one that counts**. At 80 zombies, change from
baseline (desktop full frame / browser):

| Technique | Desktop | Browser |
| --- | ---: | ---: |
| animation throttle | -15 % | **-55 %** |
| no eyelid mesh (half the draw calls) | 0 % | **-30 %** |
| physics at 30 Hz | -17 % | **-20 %** |
| fewer bones (tracks only) | -20 % | 0 % (within noise) |
| repath on a timer | -8 % | 0 % |
| avoidance tuned, visibility range | 0 % | 0 % |

The sections below keep the desktop order.

1. **Fewer bones: -20 %.** The importer builds 17 `BoneAttachment3D` nodes the game does not use (feet, eyelids,
   tongue, IK pole targets): freeing them is free. Then remove the animation tracks of bones nobody sees at crowd
   distance (3 tongue, 2 eyelid, 22 finger, 2 pole-target bones: 29 of 55 tracks per clip) from `Walk`, `Run` and
   `Punch`. This trimmed tracks only; the skeleton still has 50 bones, so a model that really has 25 bones (made in
   Blender, one crowd variant of the rig) should gain more. Result: hands lose finger motion, invisible from the
   camera used here.
2. **Physics at 30 Hz: -17 %.** `Engine.physics_ticks_per_second = 30` halves navigation, avoidance and
   `move_and_slide` work. Movement stays correct because it is scaled by the physics delta. Do this only if
   nothing else in the game needs 60 Hz physics (the player's feel, projectiles); otherwise keep the crowd on its own
   cheaper tick.
3. **Animation throttle: -15 %.** `AnimationTree.callback_mode_process = MANUAL`, and a manager calls
   `tree.advance(accumulated_delta)` every Nth frame: every frame within 14 m of the camera, every 3rd to 24 m,
   every 6th beyond, every 12th outside the view frustum (`Camera3D.is_position_in_frustum`). The tier is
   recomputed every 8th frame per zombie. The animation speed stays correct because the missed time is passed
   on. The gain is bounded here because the whole crowd bunches within 14 m of the camera; with zombies
   spread over a map it is larger.
4. **Repath on a timer: -8 % on desktop, nothing in the browser.** Set `target_position` every 0.25 s with a random
   phase per zombie instead of every physics tick. Cheap to do and it keeps path queries off the critical path as
   the map grows, but it is not what holds the frame budget.
5. **Avoidance off: -4 %.** Avoidance is cheap with the default agent settings in this scene, so keep it on:
   without it the crowd stacks into one capsule. Tuning the neighbour distance and count did nothing measurable
   (in the headless table it is within noise of baseline).
6. **No eyelid mesh: 0 ms on desktop, -30 % in the browser.** Draw calls go from 156 to 83 at 80 zombies. A draw
   call is cheap on this desktop and expensive through WebGL2: merge the eyelid into the body mesh (or hide it
   for far zombies) in the crowd variant of the model.
7. **Visibility range: 0.** All zombies were inside 32 m in this scene, so nothing was hidden. It only helps
   when zombies can be far from the camera, and then only for rendering: animation keeps running unless the
   throttle also knows about it.

The cuts overlap (their single gains sum to more than 100 % in the browser, because each removes part of the same
per-zombie cost); all together take 80 zombies from about 40 ms to about 5 ms, and on the desktop from 12.3 to 5.3 ms.

## Recommendation {#recommendation}

- **Count.** Design for **at most 40 zombies in the world at once, 20 to 30 as the normal wave.** Beyond what the
  player sees, zombies are cheap to keep: despawn or put to sleep (no animation, no avoidance) anything out of
  view and far, and respawn from the edge.
- **Build in from day one, in this order of payoff:** (1) the animation throttle manager (-55 % in the browser),
  (2) a crowd variant of the zombie model with one mesh (merge the eyelid; -30 %), (3) a physics tick chosen for the
  whole game (30 Hz; -20 %), then (4) the repath timer and trimmed bones, which are cheap and help slower CPUs.
  The first is an afternoon of code; the second is an asset change.
- **Keep avoidance on** (RVO, 2D, default radius 0.4), zombies colliding with the floor only. Do not give zombies
  physics collisions with each other.
- **No dynamic shadows from zombies.** One shadow-casting sun quadrupled the draw calls at 40 zombies (84 to 338).
  Use blob shadows or baked light.
- **Measure on a weak machine.** All numbers are from a very fast desktop and Chrome. The 3x browser factor is
  measured; the further factor for a laptop or phone is not: test the first playable on a 2 to 4 year old laptop
  before raising the count.
- **Not tried, worth a follow-up:** `MultiMesh` or vertex-animation textures for a distant crowd (a different
  look); mesh LODs for the skinned body (the importer does not make them for skinned meshes); a shared
  animation phase so far zombies reuse the same pose.

## Gotchas found while building it {#gotchas-found-while-building-it}

- Put the `AnimationTree` as a **sibling of the `AnimationPlayer`** under the imported scene root: the clips' track
  paths (`RootNode/CharacterArmature/Skeleton3D:Bone`) resolve against `..`.
- The glTF import leaves `Walk` and `Run` with `loop_mode = NONE`; set `Animation.LOOP_LINEAR` once on the shared
  resource (all instances share it, so do this before spawning).
- The imported player has every clip twice, as `Walk` and `CharacterArmature|Walk`; use the short names.
- The property is `visibility_range_end`, not `visible_range_end` (a typo is a runtime error, not a parse error,
  on a typed `MeshInstance3D` reached through an untyped variable).
- Navmesh baking from code warns unless `agent_height` and `agent_radius` are multiples of `cell_height` and
  `cell_size`; use the map's cell size (0.25) so the regions connect.
- `Performance.TIME_PROCESS` and `TIME_PHYSICS_PROCESS` did not match the wall-clock frame time in a fixed-fps
  run; the numbers here are wall clock and a headless run instead.
- A capture that draws through a camera of its own gives it to the throttle (`horde.throttle.camera`): the throttle
  poses only what its camera sees, and with the night's camera looking elsewhere the crowd stays on its first pose.
- Zombies in a `--fixed-fps` run advance by a fixed delta, so the run is repeatable; in the browser the delta is
  real, so two runs differ slightly (the "first / second" cells).

- **Approach:** Bake a greybox of `CSGBox3D`s from faces built from each box's size
  (`NavigationMeshSourceGeometryData3D.add_faces(faces, shape.global_transform)`), wound so walkable faces point up in
  Godot's winding, and on a flat floor keep the spawn height rather than the path's. **Watch out for:** the standard
  parser ignores CSG nodes (no polygons), feeding it `CSGShape3D.get_meshes()` warns about reading meshes back from the
  GPU, wrongly wound faces bake to nothing, and the baker lifts the surface by twice the cell height (0.5 m over the box
  tops). **Seen:** Deadnight, 2026-11-01 (fix: Deadnight's baker builds the faces from the boxes).
- **Approach:** Ask a path that may end somewhere unreachable with `NavigationServer3D.query_path` and
  `NavigationPathQueryParameters3D` whose `path_search_max_polygons` is larger than the mesh, and read
  `NavigationPathQueryResult3D.path`. **Watch out for:** `map_get_path` searches at most 4096 polygons, and proving a
  target unreachable means exploring the whole connected mesh, so on a fine bake (0.05 m cells over a 124 x 116 m lot)
  it printed `It's not expect to not find the most reachable polygons` and stopped far from the nearest reachable point.
  **Seen:** Deadnight, 2026-11-01 (fix: the query with a raised polygon limit; a 0.25 m bake never hit it).
- **Approach:** Guard the completion callable of `NavigationServer3D.bake_from_source_geometry_data_async` with
  `is_valid()` before calling it, and keep a test that frees the owner during a bake. **Watch out for:** the server
  calls the completion later on the main thread whatever happened to the node that asked, so a night ended right after a
  door was bought printed `Attempt to call function 'null::_on_baked (Callable)' on a null instance`. **Seen:**
  Deadnight, 2026-11-01 (fix: the `done.is_valid()` guard and a test that frees the owner mid-bake).

## Captures {#captures}

Movie Maker frames and clips are attached to the pull request: 40 zombies baseline and 80 zombies with all
techniques (`crowd-40-baseline`, `crowd-80-all`, PNG and MP4), and the browser run (`web-80-none`, `web-80-all`)
with its result line printed on the canvas.

## Reproduce {#reproduce}

```text
godot --headless --path sandbox/crowds --import
sandbox/crowds/run_bench.sh <godot> <log> [--headless]        # the whole matrix
godot --path sandbox/crowds --fixed-fps 10 --write-movie out/crowd.png --quit-after 200 -- --count=80 --techs=all,movie
godot --headless --path sandbox/crowds --export-release Web out/index.html
uvx --with playwright python sandbox/crowds/web_bench.py http://127.0.0.1:8931/index.html out/web.log
python sandbox/crowds/tabulate_results.py <log> [mean_ms|p95_ms|max_ms|draws]
```

## What a crowd costs at the ceiling, in the real night {#what-a-crowd-costs-at-the-ceiling-in-the-real-night}

Deadnight #949 ablated the real night at its desktop ceiling (round 12, 99 dead, three bots, windowed, RTX 5080,
Compatibility), two to six interleaved runs an arm. Read it before cutting "the crowd's engine cost":

- **Most of the crowd is not in front of the camera.** The dead queue at the boards and walk the lot: 64 of 92 stood
  more than 40 m from the player's camera and 4 to 27 were in the frustum (7 to 20 draw calls, 25 to 40 thousand
  triangles). Drawing the dead was 1 to 1.5 ms of a 17 ms frame (0.2 ms of the renderer's CPU time).
- **An animation advance is the cost, and the throttle's far tier was most of them.** One `tree.advance` with its
  50-bone skeleton update took about 41 microseconds of CPU headless; the throttle still advanced every dead out of
  view every 12th frame, so 87 of 92 views were "period 12" and made 7 of the 9.4 advances a frame. Leaving the
  unseen out (no point of the body in the frustum, back at once, with at most a quarter second of catch-up, when
  seen) cut the advances to 2.8 a frame. A starting phase kept as `accumulated` is not a catch-up to clamp.
- **Test a frustum with more than one point.** One point at the chest called a half-visible dead at the screen edge
  unseen; feet, chest and head with its reach (0.2, 1.0 and 2.2 m) does not.
- **Frame time cannot show a 0.3 ms change on a shared machine** (one arm ran 17 and 29 ms); count the advances and draws
  and time the advance alone (a script that advances 92 views in a loop).

## Gait follows speed {#gait-follows-speed}

Measure each locomotion clip's ground speed (the planted foot's backward speed at game scale) and put the blend
points there; never guess them. Put the move state behind an `AnimationNodeTimeScale` whose scale is ground speed
over the gait's speed, clamped (Deadnight uses 0.5-1.6), and cross over from walk to run over a short band, solving
the rate so the blend covers the target speed, because two out-of-phase loops of different length cover less ground
mid-blend. Beyond the clamp, an authored sprint clip is needed. Deadnight's numbers: `docs/research/zombie-gait.md`
there (Walk 0.97, Run 4.4, Crawl 1.1, boss walk 1.1 m/s).

- **Approach:** Measure each locomotion clip's ground speed, and check foot slide and gait in the same pull request as
  any change to a movement speed. **Watch out for:** speeds were retuned without the clips that show them and the blend
  points were guesses, so fast zombies slid and the gait did not follow the round. **Seen:** Deadnight #260, 2026-11-01
  (fix: clip speeds measured and the time scale above).
- **Approach:** Measure each clip's ground speed before setting any blend threshold. **Watch out for:** the walk and run
  blend points were guessed at 1.0 and 3.0 m/s while the clips move at 0.97 and 4.4, so speed and gait disagreed.
  **Seen:** Deadnight, 2026-11-01 (fix: measuring the planted foot gave the real speeds).

## Height: a crowd off physics needs its floor {#height-a-crowd-off-the-physics-engine-must-be-given-its-floor}

A crowd walked on a navigation path in x and z with no height ("the lot is flat") climbed nothing: on a ramp each
repath asked the map for the nearest mesh point to a position still at floor height, and a little way up the ramp the
nearest point was the floor beside or under it, not the ramp, so every path led back to the ramp's foot (0 of 6 and
0 of 16 reached the top in 40 s; Deadnight #681). Give each walker the floor its path runs on: read the height off the
path segment it walks, take off the mesh's offset above the floor (the baker rounds up to a whole cell: 0.35 to 0.5 m
at 0.25 m cells, so 0.4 m is within 0.1 m), and move it there at a climb rate. Separation and swing reach then need the
height too, or a walker on the ramp pushes one on the floor under it and the dead under a floor hit the person over
their heads. Prove it with a pack on the real ramp and a control that walks the same mesh with the heights left out.

- **Approach:** When a map gains height (ramps, stairs, a second storey), give every mover's simulation a test that
  walks it up and down, and write an assumption like "the lot is flat" where it lives so the change that breaks it finds
  it. **Watch out for:** the zombie sim never gave a zombie a height because the first lot was flat, so on the booth
  ramp and the second map's stairs a zombie kept its spawn height, and no test walked one up a slope. **Seen:**
  Deadnight #681, 2026-11-03 (fix: walkers take their height off the path, as above).
- **Approach:** Before the first map with floors (a roof, a deck), grep every flat distance in gameplay code (`_flat(`,
  `Vector2(a.x - b.x, a.z - b.z)`) and every query on a thing fixed to the ground (a gate, a zone, a trigger), decide
  what a metre of height does to each, and test each with two points a storey apart and 0.3 m apart on the flat.
  **Watch out for:** on the first two-storey map a zombie struck through a wall from a stair, a press upstairs bought
  the door below, and a ground window's gate lifted the dead walking the floor over it. **Seen:** Deadnight (second
  map), 2026-11-03; Deadnight, 2026-11-04 (fix: storey rules for the dead and the use button, a height band on each
  gate; found from `HURT` lines with each zombie's height difference).

## A player against a crowd that is not physics bodies {#a-players-body-against-a-crowd-that-is-not-physics-bodies}

A crowd of plain data (positions and a state machine on the server, drawn from a frame on the client) is not in the
physics world, so a `CharacterBody3D` walks through it: `move_and_slide` can only meet what has a collision layer
(Deadnight #914: the dead had no bodies for performance and determinism, and nobody decided that players could run
through them). Make it solid in the movement function both machines run, not with a physics proxy:

- Each walker is a circle on the ground. After the slide, a body that ended inside one is put back on its edge and loses
  the speed it had into it (`move_and_collide` for the correction, so a wall still wins). One-way: never nearer than the
  tick began, never pushed out of an overlap, so a prediction that disagrees by a few centimetres never fights the
  reconciler.
- Both machines must use the same positions. A server that blocks by where the crowd stands now, and a client by the
  frame it drew (a round trip old), disagree by the crowd's speed times the lag; the server keeps the last few ticks of
  positions (rounded to the frame's centimetres) and blocks each body by the frame its command names (the view step the
  lag compensation already uses). Measured with 120 ms of round trip and a walker that came to meet the body (8 runs,
  the median of the largest correction the reconciler asked for): 0.27 m by the frame the client drew, 0.58 m by where
  the crowd stood now, 0.29 m with no crowd at all.
- The push that moves a walker is the server's alone (the client sees the walker move in a later frame): a player who
  presses into one for a moment and then keeps pressing yields it, and it goes across the player's way, not ahead of it.
  A walker that yields straight away from the body is led along by the player at the yield speed, and a block of a dozen
  does not give at all (stuck for 20 s); rolling it aside (80 percent across) passes one in half the time and the block
  in six seconds. A wall behind the walker stops the yield (a ray), and then it rolls to the side.
- Cost: microseconds per tick per body, only for the walkers within three metres; see Deadnight
  `docs/research/dead-contact.md` for the numbers.

- **Approach:** When a new kind of thing is only data (no node, no physics body), list every way a player's body, shots,
  grenades, the camera and the bots meet it, decide for each whether it is solid, and put a test and a number beside the
  choice. **Watch out for:** the dead were made plain data for a node-free server sim, and a player's body is stopped
  only by physics layers, so players ran through them, which nobody had decided. **Seen:** Deadnight #914, 2026-11-03
  (fix: contact in the movement function the server and the predicting client share, a held push rolls a zombie aside
  (Deadnight's `docs/research/dead-contact.md`)).
- **Approach:** Test a solid that moves during a night (a cabinet, a door, a board) with everything that can stand where
  it lands, bodies that are only data included, and when a unit stands still and nobody can hit it, query the physics
  space at its feet for the node's name. **Watch out for:** a prize crane's cabinet landed on two dead that are not
  physics bodies; inside it, every sight line and shot stopped on the box while their swings, which have no wall
  check, hit a bot for ever. **Seen:** Deadnight #1352, 2026-11-06 (fix: the sim keeps the dead out of the box;
  `test_crane_cabinet_dead.gd` lands it on two).

## A pooled body costs 1 ms to take if the pool still looks the scene up {#pool-scene-lookup}

Deadnight #932 (a blast that cripples 20 walkers into crawlers: a 45 to 59 ms frame, a steady 1.2 ms). Three costs
sat on the way from one body to another, measured with a windowed bench that cripples 20 of 30 on a fresh crowd
twelve times and reads the worst frame:

- **Changing look by `dress`** (free the model, instance the .glb, strip it, build a new `AnimationTree`) is 0.4 to
  2 ms a zombie. Move the zombie to a parked view of the new look instead, as a spawn does, and park the old body.
- **`load(path)` of a scene already loaded is about 1 ms** under a loaded machine. A pool that fetched the `PackedScene`
  before looking for a parked view paid it for every reuse (20 reuses were 21 of the 24 ms). Look the scene up only
  when a view must be made.
- **Switching an `AnimationTree` `active` off and on throws away its resolved tracks**; the next `advance` rebuilds
  them (about 0.1 ms a tree, 2 ms for twenty in one frame). A parked tree that is only ever advanced by hand can stay
  `active`; advance it once when it is made, so the pooled body has its tracks resolved.

Deadnight, 20 crippled in one tick (two runs of twelve blasts each, the same machine, loaded): the call 40 ms to
0.6 ms; the worst frame after the blast 44 and 46 ms (median of twelve; 50 to 59 ms worst of all) to 3.4 and 3.5 ms
(3.8 and 5.5 ms worst), against a 1.2 ms steady frame. Keep a larger pool for a look a blast can make in bulk (crawlers:
20), and prewarm it behind the loading screen.

## A target off the walking mesh turns the crowd round at every repath (Deadnight #950) {#target-off-mesh}

`NavigationServer3D.map_get_path(map, from, to, true)` snaps `to` to the nearest point of the mesh when it is off it
(a player squeezed between two parked cars stands in the band the baker leaves round every obstacle, one agent radius
wide). The nearest point changes side as the target moves a metre, and the routes to the two sides can be 10 m and 29 m:
a crowd that asks again every 0.25 s turns round at each answer and walks up and down for ever, 7 m from the player,
never "stranded" (the path ends within 1 m of the target). Keep the old route while it still ends near the target and
the new one is much longer (Deadnight `ZombieSim._keeps_its_route`: a new route 6 m longer than what is left of the old,
an old end within 3.5 m of the target, more than 1 m left to walk). To find it, print a zombie's position every second
and its path's first points: a position that moves at full speed and goes nowhere, and a path that changes its second
point from one second to the next.

- **Approach:** Test the kept route with a target off the mesh within the goal snap's reach of the far edge
  (`AiRouteRules.OPEN_GROUND`, 0.35 m), a walker with more than 1 m of route left, and an assertion on each route's end
  (`path_changed`); see it fail with `keeps_route` made false. **Watch out for:** a target deep in a hole flips nothing
  in the 3D Third Person navigator (`snap_goal` walks back toward the walker, so the near side), and the body keeps its
  push between steers, so a turn count on `walk_direction` stayed 0 both ways: that test passed without the rule.
  **Seen:** gdstudio #1093, 2026-11-11 (a 2 m hole, the target within 0.15 m of each edge: 3 far routes in 4 s without
  the rule, none with it).

## AI characters: a brain, path queries and a body, apart from drawing (kit #882) {#ai-characters}

<!-- new section: the zombie spike above measured whole animated zombies with Godot Physics; nothing held what the
brain, the path queries and a Jolt body each cost per character on the web, or where the tick falls off a cliff -->

The research for kit #882 (AI characters for the templates) measured a character with a brain apart from its drawing:
N characters drawn by one `MultiMesh` on a 120 m map with 16 boxes, each with a 10 Hz think (distance, cone, at most 2
rays, memory, a small task stack) and a path every 0.25 s from `NavigationServer3D.map_get_path`, then the same with a
`NavigationAgent3D` and RVO, with a `CharacterBody3D` capsule and `move_and_slide`, and at every tick instead of on the
timer. Godot 4.7.2, Compatibility, web export single-threaded, Chrome on the fast desktop of the tables above, 60 Hz
physics; "4x" is the same page with `Emulation.setCPUThrottlingRate` 4. The template's engine is Jolt, so the Jolt
rows count; the option rows come from a Godot Physics build of the same project.

**Microseconds per character per physics tick** (the loop that steps every character, divided by the count; the tick
frame in brackets, ms):

| Setup | 100 | 200 | 400 | 800 |
| --- | ---: | ---: | ---: | ---: |
| brain + staggered server queries, Jolt build | 6.4 (1.5) | 4.3 (1.6) | 4.4 (2.7) | 4.6 (5.0) |
| the same + a Jolt body | 24 (3.3) | 22 (5.4) | 26 (11.8) | 23 (**154**) |
| the same + a Godot Physics body (other build) | 41 (4.9) | 38 (8.6) | 45 (**151**) | 45 (**297**) |
| brain + server query **every tick** (Godot Physics build) | 26 | 25 | 26 | |
| agent with RVO, target on a 0.25 s timer / **every tick** (Godot Physics build) | 3.3 / 23 | 2.9 / 19 | 3.0 / 19 | |
| 4x: brain + staggered server queries, Jolt build | 24 (4.3) | 29 (8.4) | 35 (**42**) | |
| 4x: the same + a Jolt body | 152 (**68**) | 132 (**224**) | 120 (**405**) | |

- A thinking, path-following character is **4 to 5 µs** a tick in the browser (6 to 7 µs below 100, where the loop's
  fixed cost is shared by fewer); the queries and steering are about 3.5 µs of it, the brain 1 to 1.5 µs. Native
  headless is about 1.5 times faster.
- A path query every tick is **about 5 times** the staggered cost (4.3 to 5.6 times with server queries, 4 to 7 with
  agents). A query on this mesh is roughly 20 µs in the browser: its rate matters, not the API.
- `NavigationAgent3D` with its target on a timer costs the same as server queries; RVO adds 1 to 1.5 µs a character
  (read in the tick frame, since it runs in the physics step) and is cheaper than a spatial-hash push in GDScript
  (4 to 8 µs, growing with density). A node per character with its own `_physics_process` measured the same as one
  manager loop.
- **The body costs more than all of the AI:** `move_and_slide` adds 18 to 21 µs with Jolt and 34 to 40 µs with Godot
  Physics. The template's player as it is costs about 200 µs headless on the desktop (#926: animation tree, ragdoll
  bones built at spawn, strings built every frame), so an AI character made of those parts needs #926's fixes first.
- Distance tiers cut the AI step by 25 to 33 % only when most characters are far (a 300 m map); on the 120 m map
  they changed nothing.
- Budget, for the AI step (brain, senses, navigation, bodies): **1 ms a tick** at the cap on the fast desktop in Chrome
  and **5 ms at 4x**; **40 characters** on the web (a browser in a match sets it for everyone), 20 of them at the full
  tier with a body moved every tick, the rest moved every 3rd; 120 on the desktop and a server. Count gates first:
  one path query per character per `repath_seconds`, `think_rate` thinks, at most 2 rays a think
  ([counts tight, time loose](performance-budgets.md#budgets-counts-tight-time-loose)). Since #963 the template's
  defaults are **12** at the Full tier on the web and the rest moved every **4th** tick (below: the real character's
  body costs about twice the spike's capsule). The task layers (#965) cost 2.7 µs a think in Chrome (15 µs at 4x)
  with a typical stack of three tasks, 0.2 µs when empty: 17 µs a tick for 40 characters thinking at 10 Hz
  ([the table](third-person/ai.md#task-cost)). The brain (#968) adds nothing measurable when calm; a fight
  does: 40 guards against two targets are 2.1 ms a tick in Chrome (0.84 with brains off) and 10.5 ms at 4x, over the
  budget, mostly the bodies that aim and fire and no longer rest ([the table](third-person/ai-behaviour.md#cost)).
  Since #1104 those bodies take the lean tick (14 to 25 % off the step) and a web fight is counted apart: **12**
  fighting guards fit the 1 ms budget, **6** the 5 ms at 4x, more fighting at once are over it in a browser
  ([the table](third-person/ai-behaviour.md#cost-follow-up)). Since #1203 the director's attack slots hold a fight to
  that count: 6 guards a target and 12 in all engage in a browser, the rest hold
  ([attack slots](third-person/ai-behaviour.md#attack-slots)).

**The template's real character (#963).** `tools/bench/ai_cost_bench.tscn` (`ai_cost_bench.py` for Chrome) times the
`AiDirector`'s step (tiers, thinks and every body's `Character.step`: what the budget above holds) for
`ai_character.tscn` on a 3 m grid around the player, all inside the Full range, so the Full cap sets the tiers;
"walking" turns each one a little every half second. No brain yet (#966 to #968 add it). Microseconds of the director's
step a tick (mean, in brackets the median whole frame's work in ms: animation, footsteps and the physics step too):

| | 20 standing | 20 walking | 40 standing | 40 walking | 120 standing | 120 walking |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Desktop, native (Full cap 60) | 205 (1.0) | 700 (1.8) | 380 (1.9) | 1750 (4.0) | 1450 (6.8) | 3560 (10.4) |
| Chrome, Full cap 20, Reduced every 3rd | 404 (1.2) | 1008 (1.8) | 653 (2.3) | **1298** (3.0) | 1792 (11.3) | 2949 (17.9) |
| Chrome, Full cap 12, Reduced every 4th | 358 (1.1) | 763 (1.5) | 525 (1.9) | **995** (2.6) | 1459 (9.6) | 2219 (12.2) |
| Chrome 4x, Full cap 20, every 3rd | 1546 (5.0) | 4883 (9.1) | 2696 (10.6) | **6475** (28.3) | 8028 (111) | 14837 (192) |
| Chrome 4x, Full cap 12, every 4th | 1753 (6.3) | 4115 (8.7) | 2429 (10.7) | **4754** (19.5) | 7119 (103) | 11529 (158) |

- A walking body at the Full tier is **35 µs native and about 50 µs in Chrome** (240 µs at 4x), against the spike's 22
  to 26 µs capsule: `Character.step` does more than `move_and_slide` (in µs native, with a timer's overhead in each:
  the move 8, the slide's tick 4, gravity and the jump 3, the step climber's `test_move` 3, the rest 1 or 2 each). The
  director's own work (tiers, the think schedule, the command) is about 3 µs a character.
- A standing character costs 10 µs native and 13 to 18 in Chrome: one at rest is stepped every 3rd tick
  (`rest_step_ticks`), which halved it.
- With the spike's 20 at Full, 40 walkers missed both budgets by about 30 % (1.3 ms, 6.5 ms at 4x), so the template ships
  12 at Full and the rest every 4th tick: 0.99 ms and 4.75 ms. The machine was shared with other agents (the parts
  bench's walking step read 31.7 µs against 23 to 26 µs on an idle one), so these are on the high side.
- At 4x the whole frame of 40 walkers was 19.5 ms, past the 16.7 ms tick: the animation tree and the footsteps, outside
  the AI budget, decided the weak machine. At 120 in Chrome the frame is past the tick even unthrottled, so 120 stays a
  desktop and server count.

**With the animation throttle (#1046).** The same bench, each row without (`-`) and with (`T`) the director's
`AiAnimationThrottle` in one Chrome run, the trees moved a frame and the calibration loop beside it (a fixed GDScript
loop timed before each row: about 8 to 10 ms at 1x and 31 to 44 ms at 4x on this shared machine; the issue's 19.5 ms run
had no calibration). The bench's camera looks on from 50 m, so every character is past `far_distance` (every 6th
frame). Median frame work in ms (the director's step a tick in brackets, ms; ticks a frame after the slash):

| 40 walking | without | with the throttle |
| --- | ---: | ---: |
| Chrome 1x | 2.8 (1.03) / 0.62 | **1.4** (0.96) / 0.31 |
| Chrome 4x, three runs | 53 to 63 (6.4 to 6.5) / 5.1 to 5.7 | **9.0 to 10.2** (6.2 to 6.4) / 0.8 to 1.0 |
| Chrome 1x, 20 / 120 walking | 1.8 / 14.2 | 1.3 / 4.0 |
| Desktop native, 40 walking | 3.6 to 4.1 | 2.8 to 2.9 |

- The throttle halves the 1x frame and takes 40 walkers at 4x out of the catch-up spiral (5 to 6 ticks a frame, the
  cliff above) to one tick a frame or fewer: about 9.5 ms against 55 to 60 ms. It does not reach the 8 ms target, and
  the rest is the walking body: the director's step alone is 6.2 to 6.5 ms of it at 4x on this machine (4.75 ms in the
  quieter #963 run).
- Where the rest goes, in Chrome at 1x: with every tree frozen the frame is 1.5 ms, of which the director's step is
  1.1 to 1.15 ms and the engine's own work (the Jolt step, transforms) about 0.35 ms; the 6.7 tree advances a frame
  the throttle still makes are about 40 µs each. A walking body's `Character.step` is **42.5 µs** in Chrome (242 µs at
  4x), and a bare `move_and_slide` of the same body only **10 µs** (50 µs at 4x): about three quarters of the body is
  the GDScript around the slide (the slide's tick, gravity and the jump, the step climber's `test_move`, the state),
  which is where the next cut is (measured with 40 `ai_character.tscn` stepped by hand, 300 ticks).

**The lean tick (#1059).** `tools/bench/ai_step_profile.tscn` (`ai_step_profile.py` for Chrome) steps 40 walking
`ai_character.tscn` by hand, in blocks that alternate between the real step and a copy of the full step cut into its
modules, each module run over the whole crowd before the next (one module of one body is under the browser's clock
step). Microseconds a walking body a tick, the full tick, mean of three runs (range in brackets):

| Module | Chrome 1x | Chrome 4x | What an AI's lean tick does with it |
| --- | ---: | ---: | --- |
| the controller's `sample()` | 2.1 | 10.0 | built again only when a channel changed (1.2, 5.5) |
| the step's prologue (copy the command, the view) | 3.6 | 17.5 | the copy kept while the AI's command repeats |
| timers and the prone stance | 1.4 | 7.2 | the timers only |
| the vault's trigger | 3.8 | 19.9 | its cooldown only |
| the slide, the crouch, the aim | 3.2 | 17.2 | left out (two timers) |
| steering (the facing on the model 0.6 of it) | 3.8 | 20.0 | the walk's branch only |
| gravity and the jump | 0.6 | 3.5 | the grounded branch |
| the step climber (one `test_move`) | 4.8 | 25.2 | only after the move met a wall, then the move again |
| `move_and_slide` | 12.0 | 62.7 | the same |
| pushing props | 1.0 | 5.6 | the same |
| the state | 2.0 | 10.6 | the walk's branch only |
| the weapon's presses, its tick | 2.2 | 11.8 | the presses left out |
| **the real step** | **42.3** (40.0 to 44.0) | **261** (231 to 294) | |

The lean tick (`CharacterLean`, taken when the controller's `lean_step` is on and nothing but the walk has work) ends
every tick where the full tick does: `test_character_lean.gd` steps a lean and a full body through walking, a kerb,
running, sprinting, a jump, crouch, aim and fire, prone, a slide and presses, and compares their snapshots each tick.

The director's bench, 40 walking with the animation throttle, a build of `main` (before) against the lean tick
(after), runs interleaved; three sessions, because the machine's load changed through the day (step a tick and median
frame work, ms; ticks a frame after the slash):

| 40 walking, three runs each | before | after |
| --- | ---: | ---: |
| Chrome 4x, lean and the command cache only | 6.2 to 6.8, work 9.5 to 10.4 / 0.81 to 0.92 | 5.35 to 5.5, work **8.7 to 8.9** / 0.75 to 0.77 |
| Chrome 4x, with the climber after a wall | 5.8 to 6.1, work 8.5 to 9.1 / 0.73 to 0.80 | 4.4 to 4.7, work **7.2 to 8.1** / 0.62 to 0.69 |
| Chrome 4x, all of it, a busy hour | 7.3 to 7.8, work 10.8 to 16.6 / 1.14 to 1.62 | 5.1 to 6.1, work 8.7 to 11.6 / 0.81 to 1.33 |
| Chrome 1x, all of it, the same hour | 1.20 to 1.41, work 1.9 to 2.4 | 0.88 to 0.99, work 1.6 to 1.8 |

- The director's step is 22 to 30 % shorter in every session, and the body's step is about **23 µs** in Chrome at Full
  and Reduced together (29 to 35 before). The 4x frame is under 8 ms in two of three runs of a quiet session and
  over it when the machine is busy: the rest of the frame (about 3 ms: the trees the throttle still moves, the
  Jolt step, the thinks) is no longer the body's.
- What is left in a walking body is the engine's (`move_and_slide` 12 µs of about 25 in Chrome) and the step's
  prologue; the next cut is the frame's other 3 ms or fewer bodies stepped every tick, not the body's script.

**The template's navigator (#967, #1062).** `tools/bench/nav_cost_bench.tscn` (`nav_cost_bench.py` for Chrome) reads
the navigators' own work (the queries, the steering, the body-ray checks) for characters walking to seeded goals, one
after another, on a baked 96 m map with 16 boxes (306 polygons), under the director's shipped defaults (12 at Full,
the rest Reduced and stepped every 4th tick, 4 path queries a tick). It reads one clock a tick around a loop that steps
only navigators: with `AiNavigator.holding` on, the director's steps only note each navigator's seconds, and the bench
steps them all with `AiNavigator.step_held()` at the start of the next tick, before the director. Microseconds a
character a tick (the loop over the count), Chrome on the fast desktop of the tables above, the range of 3 runs at 1x
and 2 at 4x on a machine other agents were using; "before" is #967's navigator with the same bench:

| | 50 | 100 | 200 |
| --- | ---: | ---: | ---: |
| Desktop, native (the editor's debug build), before | 8.9 to 9.4 | 7.3 to 8.0 | 6.7 to 7.9 |
| Desktop, native, after | 1.6 to 2.3 | 2.0 to 2.4 | 2.1 to 2.8 |
| Chrome, before | 8.8 to 10.5 | 6.7 to 7.3 | 4.4 to 5.3 |
| Chrome, after | **2.8 to 3.8** (3.2) | 2.2 to 3.1 | 2.0 to 2.1 |
| Chrome 4x, before | 53 to 63 | 46 to 48 | 35 to 38 |
| Chrome 4x, after | 15 to 18 | 14 to 15 | 13 |

- **Where the time went.** Timed natively one navigator step at a time, sorted by what the step did (a throwaway
  probe; Chrome's parts measured in tight loops were only 1.2 to 1.5 times the native ones, so the native split
  holds): a step that queried cost 46 µs (the query on this mesh 12 to 18 µs, the goal and route rules, the check's
  rays and the headroom probe's two around it) and came 3.1 times a tick at 50; a step that steered cost 10 µs and
  came 12.5 times a tick (a Full character every 3rd tick at `steer_seconds` 0.05 s, a Reduced one at every step); a
  step that only kept the push cost 3 µs. Queries were 45 % of the work, steers 40 %.
- **What changed.** A slot asks only when the answer can differ (a new goal, a map whose iteration moved, a body 1 m
  off its stretch, a followed target that moved 0.5 m, a blocked path, a stuck rung, or `refresh_seconds`, 4 s): 3.1
  queries a tick at 50 became 0.15 to 0.22, almost all of them new goals. A steer holds until the body may reach the
  next point (0.05 to 0.5 s): 4 to 5 steers a second a walker on average instead of 15 (3.7 steers a tick at 50
  against 12.5). A step that only keeps the push reads no map and calls nothing (1 µs native), and the path's ground
  distances are written out rather than calls to `flat()`, which cost more than the sum in GDScript.
- **The clock was not the fault.** The per-navigator sum #967 read (one `Time.get_ticks_usec()` pair a navigator,
  with Chrome's clock coarse to 100 µs) gave 12.3 µs at 50 where the loop read once a tick gave 11.7 on the same
  build: the sum of coarse reads is unbiased over thousands of steps. #967's table measured something else: its
  bench waited for a closest point above -1, which an empty map answers at once, so its map never took the mesh, every
  goal failed with "no open ground near the goal" and no character walked
  ([navigation in tests](navigation-in-tests.md#a-small-mesh-of-your-own)). The bench now waits for its region's RID
  and reports the share of the time the crowd walked (0.99 to 1.0), its arrivals and failures, and a calibration loop.
- The 50-walker figure moves with how many arrive in the window (each arrival is a new goal: a query, the goal rules,
  the check's rays): 2.8 with 5 arrivals, 3.8 with 11. At 100 and 200 the budget of 4 a tick is no longer what limits
  the queries (0.4 and 0.9 a tick).
- The native rows run the pinned editor binary, whose GDScript is the debug build: its calibration loop read 12 ms
  against 9 ms in Chrome's release export, so "native" is no faster than the browser here and the browser rows are
  the ones the budget holds.

- **Approach:** Make a cost bench report what its crowd did beside the cost (the share of the time walking, arrivals,
  failures) and check it before reading the cost. **Watch out for:** #967's navigator bench never had a mesh: a
  crowd whose every goal fails costs a query and the goal rules a step and nothing else, and its table (1.1 µs native,
  11.2 in Chrome) stood for a navigator that never walked, until #1062 found it with a profile whose paths held no
  points. **Seen:** gdstudio #1062, 2026-11-11 (the bench reports `walking_share`, `arrivals`, `failures`).

- **Approach:** Time a part that runs many times a tick in the browser in a tight loop of thousands of calls as well
  as one call at a time, and look for engine calls (a shape query, a physics test) in what runs every step.
  **Watch out for:** the first navigator asked the body's room to stand (a shape query) at every step and checked
  every new path again although only its first point had moved: 17 µs a character a tick in Chrome at 50, 11 after
  both went. **Seen:** gdstudio #967, 2026-11-11.
- **Approach:** Put off work that a per-tick budget refuses fairly: start the loop over the characters one further
  along each tick, and test the refusal with more characters wanting the work every tick than the budget allows.
  **Watch out for:** the first `AiDirector` walked its list from the start each tick and moved a refused think to the
  next tick, so with one think a tick and four characters at 60 Hz the first thought on every tick and the other three
  never did. **Seen:** gdstudio #963, 2026-11-10 (`test_thinks_over_the_count_a_tick_wait_for_the_next_tick`).
- **Approach:** Give a per-character query over everyone (sight's candidates, a telling to the allies) a shared index
  (the group split by faction, rebuilt when its count changes), walk only the parts the asker cares about, and bench it
  with the crowd itself as the candidates. **Watch out for:** the senses' first look asked every AI character its
  distance on every think (262 µs a think at 200 where 4 players were all it cared about), and every ally passed every
  telling on, so 40 grunts that saw the same players made thousands of tellings. **Seen:** gdstudio #966, 2026-11-10
  (fix: `AiSensePool`, and a listener that knew already passes nothing on; [the cost](third-person/ai-senses.md#cost));
  gdstudio #1204, 2026-11-11 (the noise board by faction: [the think](third-person/ai-behaviour.md#cost-think)).
- **Approach:** Measure the cost of the real character before taking the spike's caps, and set the template's defaults
  from that table. **Watch out for:** the spike's 20 at the Full tier came from a 22 to 26 µs capsule; the template's
  character is about 50 µs in Chrome walking, and 40 walkers with 20 at Full missed the 1 ms and 5 ms budgets by about
  30 %. **Seen:** gdstudio #963, 2026-11-10 (the defaults became 12 at Full, Reduced every 4th tick).
- **Approach:** Keep a test's crowd and its per-tick work under half the tick interval on the weak-machine stand-in
  (4x throttle), and read `ticks_per_frame` beside the frame time. **Watch out for:** past the tick interval (16.7 ms at
  60 Hz) Godot runs up to `physics/common/max_physics_steps_per_frame` (8) ticks a frame to catch up, each as slow, so
  the frame does not grow by a little but jumps from about 10 ms to 150 to 400 ms (7.87 ticks a frame measured): bodies
  hit it between 200 and 400 characters with Godot Physics, 400 and 800 with Jolt, and before 100 at 4x. **Seen:**
  gdstudio #882, 2026-11-10 (the budget above keeps the cap at 5 ms throttled).
- **Approach:** Measure a body's cost in a build with the physics engine the template ships (`3d/physics_engine` in
  its `project.godot`), and check which engine a web export holds by searching its `.pck` for `Jolt Physics`.
  **Watch out for:** the spike's first web export came from the project before it was switched to Jolt, so its body
  rows read Godot Physics: twice the template's cost, and the cliff at half the count. **Seen:** gdstudio #882,
  2026-11-10 (the matrix was run again on a Jolt export; both are in the table, named).
- **Approach:** Write a report's summary figures last, from the table, as the ratio of the measured rows with their
  range. **Watch out for:** the AI research's summary was drafted before the matrix ran and said a per-tick query cost
  ten times the staggered one and left the per-character cost blank; the rows gave about 5 times (4 to 7) and 4 to
  5 µs. **Seen:** gdstudio #882, 2026-11-10 (the summary and the drafted issues were corrected from the logs).
