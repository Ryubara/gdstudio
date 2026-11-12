# The AI navigator in 3D Third Person

<!-- new section: moved whole from ai.md's navigator section when that page passed the 50 KB limit (kit #968); the
     navigator (#967, #1062) is a part with its own rules, inspector, cost and proof -->

## What it does {#navigator}

<!-- new section: the navigator (kit #967) is the first part in a slot; nothing said how it moves the body, what it
     spends or how it gets unstuck -->

`AiNavigator` (`gameplay/ai/navigation/ai_navigator.gd`, the `Navigator` node of `ai_character.tscn`) moves its
character along the navigation map by writing the controller's movement channel and the moves on the way (`jump`,
`crouch`, `sprint`, added to `AiController`): the body walks, climbs steps with its step climber, crouches, slides,
vaults a `Vaultable` and jumps a gap with its own moves, and nobody is moved by hand. `AiCharacter.before_step()`
calls it before every step of the body with the time since the last one (the director's missed ticks included), so a
far character stepped every 4th tick walks the same path.

| Part | File (`gameplay/ai/navigation/`) | What it does |
| --- | --- | --- |
| `AiNavigator` | `ai_navigator.gd` | `go_to(point, speed)`, `follow(node, band, speed)`, `stop()`, `is_arrived()`, `path`; signals `arrived`, `failed(reason)` (`NO_PATH`, `UNREACHABLE`, `STUCK`, `BLOCKED`), `link_reached(link, from, to)`, `stranded(gap)`, `path_changed`. Idle, it leaves the controller alone. |
| `AiNavQuery`, `AiNavAgentQuery` | `ai_nav_query.gd`, `ai_nav_agent_query.gd` | The SERVER backend (`NavigationServer3D.query_path`, no node, the default) and the AGENT backend (a `NavigationAgent3D` child of the character, its target set on the same timer). |
| `AiNavPath` | `ai_nav_path.gd` | The points, the link starts, passing a corner run wide of, what is left (cached lengths), the point to steer to. |
| `AiRouteRules` | `ai_route_rules.gd` | Goals snapped to open ground of the layers (a goal in a wall: the first open point back toward the walker), the kept route, remembered goals. |
| `AiPathCheck` | `ai_path_check.gd` | A new path checked with knee-height rays as the body would walk it; a moving thing or an unlocked door is no block, a `Vaultable` is a place to jump. |
| `AiStuckWatch`, `AiStuckLadder` | `ai_stuck_watch.gd`, `ai_stuck_ladder.gd` | Stuck from the path left (over 1 m/s asked, under 0.25 m/s of progress for 0.5 s; it ends on 0.5 m of net progress), and the rungs: sidestep, repath from the mesh to a moved goal, a jump where the level allows one, drop the goal for 10 s, walk back along the breadcrumbs, report. |
| `AiNavAvoidance` | `ai_nav_avoidance.gd` | OFF, SEPARATION (a push from the characters near) or RVO (the server's avoidance agent, or the agent node's). |
| `AiNavDebug` | `ai_nav_debug.gd` | With `debug` on: the path (a link's stretch orange), the point it steers to, a path ending short of the goal in red; the overlay's line says what it does, the stuck rung and why a goal was refused. |

- **Queries.** One path query per character at most every `repath_seconds` (0: the profile's 0.25 s), on a phase of
  its own, and only when the director's `AiBudget` gives one (`take_path()`; a refusal tries at the next step). None
  before the map's first iteration (`map_get_iteration_id`), none while it crosses a link. A slot asks only when the
  answer can differ (#1062): a new goal, a stuck rung or the unreachable retry, a map whose iteration id moved since
  the path was asked, a body more than 1 m off the stretch it walks (or a storey off it), a followed target 0.5 m from
  where it was asked for, a path found blocked, or `refresh_seconds` (4 s; 0: never) gone by; otherwise it looks
  again a slot later. The same map asked again from a point on the same path gives the same route, and a query is
  most of the navigator's cost (about 45 µs on the bench's mesh in Chrome).
- **The map's builds are on the physics step.** The template's `project.godot` turns off both of Godot's threaded
  builds, `navigation/world/region_use_async_iterations` and `navigation/world/map_use_async_iterations` (#1075), and
  the navigator turns the map's off again for a game that sets it back. A region added to the level (a section) or a
  mesh swapped into one (a door) is then in the map at the next tick on every machine; with a region's build on a
  worker thread it took 12 to 48 ticks for a section and 24 to over 300 for the test arena, as the machine's load
  moved ([navigation in tests](../navigation-in-tests.md#a-thread-synced-map-drops-meshes-swapped-in-one-go)). A
  web build has no threads, so it built on the step already: the switches change the desktop and the server only.
  The test arena (`NavArena.build()`) also turns its region's switch off by its RID, for a game that sets the
  project's back ([a small mesh of your own](../navigation-in-tests.md#a-small-mesh-of-your-own)).
- **Goals and routes.** An unreachable goal (the path ends more than 1 m short) is asked once more with no polygon
  limit, at the next slot, then `failed(UNREACHABLE)` and refused for 5 s without a query. Following, a path ending
  3 m or more short of a target 12 m or more away is `stranded`, said once a goal; moving the character is the
  director's choice. A route is kept while it ends within 3.5 m of the target and a new one is 6 m longer
  ([crowds](../crowds.md#target-off-mesh)). A path found blocked on three checks in a row is `failed(BLOCKED)`.
- **Links.** At a link's start it emits `link_reached` and, with `auto_traverse_links` on, sprints at it and jumps
  where the floor ends (a drop is walked off); off, it waits for `finish_link()` from the task that crosses.
- **Steering.** At every step within 2 m of the end, on or heading to a link, while stuck or jumping; elsewhere a
  steer holds until the body may reach the next point of the path (or a vault, or the last 2 m) at the faster of its
  asked and real speed, at least `steer_seconds` (0.05 s) and at most 0.5 s, or `steer_seconds` with avoidance on.
  Between two steers the body keeps its push; a body pushed off the stretch asks for a path (above). `steers` counts
  them.

The backend is SERVER: the research measured both the same once the target is set on a timer, and SERVER needs no
node, answers the same on every machine and is what a test can hash; AGENT is there for its RVO in a crowd.

- **Approach:** Restart the stuck window only when a new path is another route (what is left differs by more than a
  metre), never on every repath. **Watch out for:** the first navigator restarted the window with every path it took;
  with 0.25 s repaths and a 0.5 s window no window ever closed, so a body pressed against a block it did not know of
  stood there for 20 s with no episode at all. **Seen:** gdstudio #967, 2026-11-11
  (`test_a_sidestep_takes_it_round_a_block_it_did_not_know_of` fails with the restart put back).
- **Approach:** A test of a rule that guards against what a repath does (the stuck window's restart, no query on a
  link) sets `refresh_seconds` to a slot, so a path is asked at every slot as under a changing map. **Watch out for:**
  once a slot asked only when the answer could differ (#1062), the sidestep and link tests passed with their rules
  taken out: nothing asked mid-walk, so nothing restarted the window or asked from the gap. **Seen:** gdstudio #1062,
  2026-11-11 (both tests set `refresh_seconds = 0.25`).
- **Approach:** Ask no path while a link is being crossed. **Watch out for:** a repath from the middle of a gap starts
  at the nearest mesh point, back at the link's start; the walker turned back to it and announced the link again at
  every repath, and never got across. **Seen:** gdstudio #967, 2026-11-11 (`test_it_crosses_a_link`).
- **Approach:** Let a part in a slot leave the controller alone while it has nothing to do, and run the base's suites
  (`test_ai_character.gd`, `test_ai_director.gd`) after filling a slot. **Watch out for:** the idle navigator cleared
  `walk_direction` before every step, so six director and character tests that drive the channel by hand stood
  still. **Seen:** gdstudio #967, 2026-11-11.
- **Approach:** Check `is_instance_valid()` on every node of a list kept from one step to the next (the separation
  push's neighbours). **Watch out for:** the capture freed a shot's characters and the others' kept list cast freed
  objects: 18 `SCRIPT ERROR` lines in the Movie Maker run, none in the suites, which never free a walker mid-walk.
  **Seen:** gdstudio #967, 2026-11-11 (`tools/capture/nav_tour.tscn`).

## What it costs {#cost}

**What a region costs the frame.** `tools/bench/nav_sync_bench.tscn` (`nav_sync_bench.py` for Chrome) adds a region
with a mesh, waits until the map answers on it and frees it, 20 times, and reads the time after the frame's physics
callbacks (the navigation step, on the main thread). Desktop (headless, `--fixed-fps 60`), step against thread: the AI
section's 135 polygons 42 to 70 us once against 13 to 17 us (1 tick against 15 to 21), the pathing section's 106
polygons 31 to 52 us against 11 to 13 us (1 tick against 12 to 48), a 128 m grid of 4096 quads 1.9 ms against 0.2 ms
(1 tick against about 390). Chrome, which builds on the step either way: 0.2 ms for a section and 1.9 ms for the
grid, 1 ms and 9.5 ms under a 4x CPU throttle. A section's swap costs the desktop frame some 40 us once; a level of
thousands of polygons swapped in at once is a frame's budget on a weak phone either way, so a game that grows one
splits it into regions.

**What it costs.** `tools/bench/nav_cost_bench.tscn` (`nav_cost_bench.py` for Chrome) reads the navigators' own work
a tick for 50, 100 and 200 characters walking to seeded goals on a baked 96 m map with 16 boxes, under the director's
shipped defaults, with one clock read a tick around a loop that steps only navigators (`AiNavigator.holding` and
`step_held()`): [Crowds: AI characters](../crowds.md#ai-characters).

## Proof {#proof}

`tests/gameplay/test_ai_nav_rules.gd` (the path, the stuck watch fed traces, the ladder, the kept route,
remembered goals), `test_ai_nav_queries.gd` (one path for a walk on a still map, asked again after `refresh_seconds`,
on a map that changed, for a body put off its path and a followed target that moved; a steer that holds on a long
stretch), `tests/world/test_navigation_sync.gd` (both switches off, a section added to the level and a mesh
swapped out of it at the next tick: fails with the region's switch back on), `test_ai_navigator.gd` (walking, the
first iteration, async iterations off, the repath count, the
budget, the goal in a wall, the off-mesh target, the much longer route, the unreachable goal, the overlay, a far
character, the AGENT backend with RVO, two walkers meeting), `test_ai_nav_recovery.gd` (the sidestep, the report with
no teleport, the wall the mesh runs through, the door that shuts mid-walk, the locked door, the link crossed and left
to a task) and `tests/world/test_ai_nav_course.gd` (every route of the pathing section at Full and stepped every 4th
tick, and the AI section from its doorway: no stuck second on any of them). Each rule's test fails with that rule
taken out. The capture is `tools/capture/nav_tour.tscn` (the course from above, a crowd through the doorway, a stuck
recovery, from the player's camera).
