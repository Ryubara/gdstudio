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

## What was built

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

## Numbers

Machine: Windows 11, RTX 5080, a fast desktop. Other agents were using the same machine while the runs went, so
single runs are noisy: three repeats of 40 zombies, baseline, gave 6.32, 6.48 and 6.55 ms, but the 80-zombie rows can
move by 1 ms or more. Read differences under 10 % as noise.

### Desktop, full frame (ms per frame, mean)

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

### Desktop, script and engine work only (headless, no rendering; ms per frame)

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

### Browser (the real target: web export, single-threaded, Chrome, same machine)

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

## What each technique does

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

## Recommendation

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

## Gotchas found while building it

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
  poses only what its camera sees, and with the night's camera looking elsewhere the crowd stays on its first pose
  ([lesson](../../lessons/2026-11-04-a-capture-with-its-own-camera-froze-the-dead.md)).
- Zombies in a `--fixed-fps` run advance by a fixed delta, so the run is repeatable; in the browser the delta is
  real, so two runs differ slightly (the "first / second" cells).

## Captures

Movie Maker frames and clips are attached to the pull request: 40 zombies baseline and 80 zombies with all
techniques (`crowd-40-baseline`, `crowd-80-all`, PNG and MP4), and the browser run (`web-80-none`, `web-80-all`)
with its result line printed on the canvas.

## Reproduce

```text
godot --headless --path sandbox/crowds --import
sandbox/crowds/run_bench.sh <godot> <log> [--headless]        # the whole matrix
godot --path sandbox/crowds --fixed-fps 10 --write-movie out/crowd.png --quit-after 200 -- --count=80 --techs=all,movie
godot --headless --path sandbox/crowds --export-release Web out/index.html
uvx --with playwright python sandbox/crowds/web_bench.py http://127.0.0.1:8931/index.html out/web.log
python sandbox/crowds/tabulate_results.py <log> [mean_ms|p95_ms|max_ms|draws]
```

## What a crowd costs at the ceiling, in the real night

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

## A pooled body costs 1 ms to take if the pool still looks the scene up

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

## A target off the walking mesh turns the crowd round at every repath (Deadnight #950)

`NavigationServer3D.map_get_path(map, from, to, true)` snaps `to` to the nearest point of the mesh when it is off it
(a player squeezed between two parked cars stands in the band the baker leaves round every obstacle, one agent radius
wide). The nearest point changes side as the target moves a metre, and the routes to the two sides can be 10 m and 29 m:
a crowd that asks again every 0.25 s turns round at each answer and walks up and down for ever, 7 m from the player,
never "stranded" (the path ends within 1 m of the target). Keep the old route while it still ends near the target and
the new one is much longer (Deadnight `ZombieSim._keeps_its_route`: a new route 6 m longer than what is left of the old,
an old end within 3.5 m of the target, more than 1 m left to walk). To find it, print a zombie's position every second
and its path's first points: a position that moves at full speed and goes nowhere, and a path that changes its second
point from one second to the next.
