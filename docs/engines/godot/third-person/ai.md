# AI characters in 3D Third Person

<!-- new section: the AI characters (kit #963 and the chain #964 to #971 after it) are a subject of their own; the template
     page holds only its row, and nothing said how the base, the profile and the director fit together -->

The base every enemy, friendly and civilian is made from, the resource that says what kind it is, and the one node that
budgets them all (kit #963; the design is the research for #882, the costs [Crowds: AI
characters](../crowds.md#ai-characters)). Senses, tasks and reactions come in #964 to #971, each into a slot this base
leaves for it; the navigator (#967) is [below](#navigator).

## What is in it {#base}

| Part | Where (in `templates/3d-third-person/game/`) | What it does |
| --- | --- | --- |
| `AiCharacter` | `gameplay/ai/ai_character.gd`, `ai_character.tscn` | The template's `Character` (its body, `Model` slot, animation, `Health` and ragdoll, as the player has them: the scene inherits `character_dressed.tscn`) driven by an `AiController`. Joins the group `ai_characters`, never `player`. Signals `situation_changed`, `tier_changed`, `thought`. A hit comes through `Health`, a death goes into the same ragdoll. |
| `AiController` | `gameplay/ai/ai_controller.gd` | The `CharacterController` the parts write: the movement channel (`walk_direction`, `walk_strength`) and the action channel (`look_direction`, `aim`, `fire`), turned into one `PlayerCommand` a tick with `set_from_world`. A fire that starts is a press in exactly one command; `is_still()` says it asks for nothing. |
| `AiProfile` | `gameplay/ai/ai_profile.gd`, `profiles/grunt.tres`, `ally.tres`, `civilian.tres` | Every number a kind of character reads, in six groups (Movement, Senses, Combat, Nerve, Social, Budget), each an `@export` with a range, a unit and a tooltip, read where it is used so an edit applies live. |
| `AiDirector` | `gameplay/ai/ai_director.gd`, a node of `world/world.tscn` (group `ai_director`) | Steps every registered character's body, runs its think at its rate on its own phase, puts it in a tier by distance, and holds the shared `AiBudget`. It gives a character its `tier` and its `budget` and nothing else. |
| `AiBudget` | `gameplay/ai/ai_budget.gd` | Rays, path queries and thinks all characters together may spend in one physics tick; `take_ray()`, `take_path()`, `take_think()` refuse the one over the count. |
| `AiSituation` | `gameplay/ai/ai_situation.gd` | Unaware, Suspicious, Alert, Engaged, Fleeing, Dead: rising is at once, calming down or turning sideways waits `situation_dwell`, awareness crosses its lines with `awareness_hysteresis`, death is at once and only `revive()` leaves it. |
| Debug overlay | the `DebugLabel` (`Label3D`) of `ai_character.tscn` | The profile's name, the situation and the tier above the head, with `debug` on (off by default; written only on a change or a think while on). |

The director lives in `world.tscn`, not `main.tscn`: the main scene holds only instances and wires
([Which scene to open](../third-person-template.md#scene-map)), and the director is a system the map owns, which a server
that loads the world gets too. It finds the characters already in the tree when it starts, and a character added later
finds it through the group; a character with no director steps itself and never thinks.

## The inspector {#inspector}

- **`AiCharacter`** (group AI): `profile` (the grunt in `ai_character.tscn`), `debug`, `debug_label`; group Slots:
  `senses`, `navigator`, `task_runner` (`navigator` holds the scene's `Navigator`, an `AiNavigator`; the others
  stay empty until #966 and #965 fill them). Everything `Character` has
  (tuning, weapon, ragdoll) is there too.
- **`AiProfile`**: `display_name`; Movement `walk_speed` 1.6 m/s, `run_speed` 4.5 m/s, `turn_rate` 360 °/s,
  `acceleration` 12 m/s²; Senses `sight_range` 24 m, `lose_sight_range` 32 m, `half_angle` 55°, `near_radius` 2 m,
  `hearing_range` 30 m, `time_to_notice` 0.6 s, `reaction_time` 0.35 s (never under 0.2), `memory_seconds` 6,
  `suspicious_at` 0.3, `awareness_hysteresis` 0.1; Combat `engage_range` 18 m, `preferred_range` 10 m,
  `attack_range` 1.6 m, `fire_interval` 0.4 s, `burst_size` 3, `accuracy` 0.5, `aim_speed` 360 °/s,
  `retreat_margin` 3 m; Nerve `courage` 0.5, `flee_below_health` 0.3, `panic_recovery_seconds` 8, `aggression` 0.5,
  `curiosity` 0.5, `alert_hold_seconds` 10, `situation_dwell` 1 s; Social `faction`, `share_radius` 12 m,
  `obeys_orders` 0.5; Budget `think_rate` 10 Hz, `reduced_think_rate` 2 Hz, `dormant_think_rate` 0.5 Hz,
  `full_range` 25 m, `reduced_range` 70 m, `tier_margin` 4 m, `max_rays_per_think` 2, `repath_seconds` 0.25 s. The
  three files change only what makes the kind: the grunt (faction `enemies`, `accuracy` 0.4), the ally (`players`,
  0.6, `obeys_orders` 0.9), the civilian (`civilians`, `engage_range` 0, `flee_below_health` 1, `courage` 0.1).
- **`AiDirector`**: Population `web_cap` 40, `desktop_cap` 120, `web_full_cap` 12, `desktop_full_cap` 60,
  `player_group`; Budget a tick `rays_per_tick` 8, `paths_per_tick` 4, `thinks_per_tick` 12; Steps
  `reduced_step_ticks` 4, `dormant_step_ticks` 6, `rest_step_ticks` 3.

## How the director schedules {#schedule}

- **Thinks.** A character thinks every `ticks per second / rate` ticks at its tier's rate, read from the profile at each
  think (so an edit applies at the next one; 0 stops it). Its first think goes on the tick of the coming interval
  where the fewest thinks already fall, so N characters with the same interval take N different ticks while N is at
  most the interval (6 ticks at 10 Hz and 60 Hz). A think over `thinks_per_tick` waits for the next tick, and each
  tick the loop starts one character further along so the same one is not put off every time.
- **Tiers.** Every 8th tick on each character's own slot, by its distance to the nearest body of `player_group`:
  Full under `full_range`, Reduced under `reduced_range`, Dormant past it, and a character keeps a nearer tier until it
  is `tier_margin` past that tier's range. At most `web_full_cap` (in a browser) or `desktop_full_cap` are Full; a
  nearer character takes the slot of the farthest Full one. No player at all is infinitely far: every character is
  Dormant.
- **Steps.** A Full body is stepped every tick, a Reduced one every `reduced_step_ticks` and a Dormant one every
  `dormant_step_ticks`, on its own slot, with the missed time handed on: `Character.step(command, delta)` takes a whole
  number of physics steps and scales the velocity for the move, so a far character walks as far in the same time
  (`test_a_far_character_stepped_less_often_walks_as_far`). A character at rest (on a floor that does not move, still,
  its controller asking for nothing) or dead is stepped at most every `rest_step_ticks`. A far body moves in steps of
  four or six ticks, which shows only to a camera near it.

## The navigator {#navigator}

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
  before the map's first iteration (`map_get_iteration_id`), none while it crosses a link. The navigator turns the
  server map's async iterations off
  ([navigation in tests](../navigation-in-tests.md#a-thread-synced-map-drops-meshes-swapped-in-one-go)).
- **Goals and routes.** An unreachable goal (the path ends more than 1 m short) is asked once more with no polygon
  limit, at the next slot, then `failed(UNREACHABLE)` and refused for 5 s without a query. Following, a path ending
  3 m or more short of a target 12 m or more away is `stranded`, said once a goal; moving the character is the
  director's choice. A route is kept while it ends within 3.5 m of the target and a new one is 6 m longer
  ([crowds](../crowds.md#target-off-mesh)). A path found blocked on three checks in a row is `failed(BLOCKED)`.
- **Links.** At a link's start it emits `link_reached` and, with `auto_traverse_links` on, sprints at it and jumps
  where the floor ends (a drop is walked off); off, it waits for `finish_link()` from the task that crosses.
- **Steering.** At most every `steer_seconds` (0.05 s) on a stretch, and at every step within 2 m of the end, on a
  link, while stuck or jumping; between two steers the body keeps its push.

The backend is SERVER: the research measured both the same once the target is set on a timer, and SERVER needs no
node, answers the same on every machine and is what a test can hash; AGENT is there for its RVO in a crowd.

- **Approach:** Restart the stuck window only when a new path is another route (what is left differs by more than a
  metre), never on every repath. **Watch out for:** the first navigator restarted the window with every path it took;
  with 0.25 s repaths and a 0.5 s window no window ever closed, so a body pressed against a block it did not know of
  stood there for 20 s with no episode at all. **Seen:** gdstudio #967, 2026-11-11
  (`test_a_sidestep_takes_it_round_a_block_it_did_not_know_of` fails with the restart put back).
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

**What it costs.** `tools/bench/nav_cost_bench.tscn` (`nav_cost_bench.py` for Chrome) reads the navigators' own work
a tick for 50, 100 and 200 characters walking to seeded goals on a baked 96 m map with 16 boxes, under the director's
shipped defaults: [Crowds: AI characters](../crowds.md#ai-characters).

**Proof.** `tests/gameplay/test_ai_nav_rules.gd` (the path, the stuck watch fed traces, the ladder, the kept route,
remembered goals), `test_ai_navigator.gd` (walking, the first iteration, async iterations off, the repath count, the
budget, the goal in a wall, the off-mesh target, the much longer route, the unreachable goal, the overlay, a far
character, the AGENT backend with RVO, two walkers meeting), `test_ai_nav_recovery.gd` (the sidestep, the report with
no teleport, the wall the mesh runs through, the door that shuts mid-walk, the locked door, the link crossed and left
to a task) and `tests/world/test_ai_nav_course.gd` (every route of the pathing section at Full and stepped every 4th
tick, and the AI section from its doorway: no stuck second on any of them). Each rule's test fails with that rule
taken out. The capture is `tools/capture/nav_tour.tscn` (the course from above, a crowd through the doorway, a stuck
recovery, from the player's camera).

## What it costs {#cost}

<!-- new section: the cost of the real character, which sets the director's web defaults, is read here first -->

40 walking characters in Chrome on the fast desktop: the director's step is 0.99 ms a tick (4.75 ms at a 4x CPU
throttle) with the shipped defaults, 12 at the Full tier and the rest stepped every 4th tick; standing, 0.53 ms (2.4 ms).
A walking body at Full is about 50 µs in Chrome and 35 µs native, the director's own work about 3 µs a character. The
table and why the Full cap is 12 and not the research's 20: [Crowds: AI characters](../crowds.md#ai-characters).

- **Approach:** Raise `web_full_cap` or lower `reduced_step_ticks` only with the bench run again in Chrome at 1x and 4x
  (`tools/bench/ai_cost_bench.py`), and read the frame's work beside the director's step. **Watch out for:** at 4x the
  whole frame of 40 walkers is 19.5 ms, past the 16.7 ms tick, from the animation and the footsteps, which the AI budget
  does not count. **Seen:** gdstudio #963, 2026-11-10.

## Proof {#proof}

`tests/gameplay/test_ai_director.gd` (thinks at the rate and on ticks of their own, the ray budget shared and reset, the
think budget, a profile edit while running, tiers with the margin and the cap, the population cap, the rest cadence,
far characters walking as far), `test_ai_situation.gd` (rising, dwell, hysteresis, death) and `test_ai_character.gd`
(the parts, the channels, a hit that kills into the ragdoll, the overlay, the profiles). The capture is
`tools/capture/ai_tour.tscn` (the three profiles side by side with the overlay, a grunt killed into its ragdoll) and the
cost is `tools/bench/ai_cost_bench.tscn` with `ai_cost_bench.py` for Chrome ([the numbers](../crowds.md#ai-characters)).
