# Enemies, friendlies and their spawner in 3D Third Person

<!-- new section: the characters a level is populated with (kit #969: the grunt, the shooter, the ally, the civilian),
     the spawner and pool that keep them alive and the AI section that shows them are a subject of their own; the AI
     pages held the base, the senses and the brain, and nothing said how a level gets its characters -->

The characters a level is populated with, and the node that keeps them alive (kit #969). Each one is the base
([AI characters](ai.md#base)) with a profile, a behaviour set ([AI behaviour](ai-behaviour.md#parts)) and a look; an
`AiSpawner` in the level spawns them from a pool. The AI section of the prototype map holds one spawner per kind.

## What is in it {#parts}

| Part | Where (in `templates/3d-third-person/game/`) | What it is |
| --- | --- | --- |
| Grunt | `gameplay/ai/characters/enemy_grunt.tscn` | `grunt.tres`, `hostile_guard.tres`, the male body (`form_male.glb`): patrols, engages, chases, searches. |
| Shooter | `gameplay/ai/characters/enemy_shooter.tscn`, `gameplay/ai/profiles/shooter.tres` | Engages at 24 m and prefers 16, aim 0.55, `careful_margin` 1.0: always in the Careful play state, so it fights from cover and peeks. Male body. |
| Ally | `gameplay/ai/characters/ally.tscn` | `ally.tres`, `friendly_ally.tres`, the female body (`form_female.glb`): follows its leader (the player) and fights with it; startled by shots of anybody. |
| Civilian | `gameplay/ai/characters/civilian.tscn` | `civilian.tres` and set, unarmed (`Loadout.start_slot` -1), wanders 3 m round its home (`home_radius`), keeps away from a stranger with a gun (`remind_up_to` Unfriendly), and flees or cowers at a shot it hears from anybody (`startled_by` `shot`, the set's two heard-shot rows). |
| `AiSpawner` | `gameplay/ai/spawner/ai_spawner.gd` | Keeps `count` of one scene alive at its markers, wakes when a player comes near, respawns after a death, lets bodies lie and takes them back. |
| `AiPool` | `gameplay/ai/spawner/ai_pool.gd` | The spawner's characters, made once; a parked one is out of the tree. |
| `CharacterModel.variant` | `gameplay/character/character_model.gd` | Another model of the same rig in place of the one the base holds ([Replacing the model](character.md#replacing-the-model)). |
| AI section | `world/prototype/ai_section/ai_section.tscn`: `AiMarkers/` (the guard lane `guard_lane`, two shooter posts, 8 cover spots, 3 civilian homes) and `Population/` (Grunts 3, Shooters 2 on route `hold`, Allies 2 with leader `player`, Civilians 3; each `wake_range` 25 m, `max_corpses` 2, `on_server` on) | The population, placed and tuned in the scene (the template's `docs/design/map-sections.md`). |

Enemies wear the male prototype body and friendlies the female (the `form` look,
[the bodies](character.md#mannequins)), so a side reads without the band rings. The older scenes
`gameplay/ai/ai_guard.tscn`, `ai_ally.tscn` and `ai_civilian.tscn` stay for the tests and benches that use them.

## Adding an enemy or a friendly {#recipe}

1. **Scene.** Scene > New Inherited Scene from `gameplay/ai/ai_character.tscn`, saved in `gameplay/ai/characters/`.
2. **Kind.** On the root, `profile`: a profile of `gameplay/ai/profiles/` or a new one (the faction, the ranges, the
   aim, the play-state lines). On `Brain`, `behaviour`: one of `behaviour/sets/` or a copy with rows of your own.
3. **Look.** On `Model`, `variant`: a model of the same rig (an inherited scene cannot delete its base's model; the
   slot swaps it in when the game runs and shows it in the editor without saving anything).
4. **Details.** `Loadout.start_slot` -1 for an unarmed one; `Senses.startled_by` for noises it answers from factions
   it does not care about; `Ragdoll.ragdoll_range` (the section's use 40 m).
5. **Level.** Add a `Node3D` with `ai_spawner.gd`, set `scene`, `count`, `markers` (each faces its -Z), and, for a
   friendly, `leader_group` `player`; for a guard, `patrol_route` (an `AiMarker` route in the level).

A character spawned again starts as a new one: `AiCharacter._enter_tree` registers it with the director again and
calls `restart_mind()` (tasks, brain, senses and grudges reset). A part you add that keeps state in `_ready` must
reset it there too, because `_ready` runs once.

## The spawner and its pool {#spawner}

The pool makes every character the spawner will need (`count` + `max_corpses`) once: when the level loads with
`wake_range` 0, or one a tick once a player is within `wake_range` + 10 m, so a far part of the map costs nothing and
nobody waits for a scene to be made when they arrive. A death is answered by a spawn of a parked one `respawn_delay`
later; a body lies in its ragdoll until it settles (plus `settled_linger`), at most `corpse_seconds`, at most
`max_corpses` at once (the oldest goes first), then goes back to the pool. It spawns only where the AI runs: offline, on
a game server only with `on_server`, never on a client (a client of a remote server, or a map that handed its AI to the
server: `AiAuthority.hand_over` stops it and frees its pool). When one process holds a server's map and clients' maps
(an `OnlineRig` test, a capture), the spawner decides by its own map (`spawns_here(..., from)`): under a `NetServer` it
spawns only with `on_server`, beside a `NetClient` never. The players that wake it and lead its friendlies are the
bodies of `player_group` in its own world (`get_world_3d()`), so on a game server they are the players' bodies
(`NetServer.ai_sees_players`), never a client's player in another viewport. Online, the section's population reaches the
clients as puppets ([the AI online](ai-online.md#section-online)).

- **Approach:** Park a pooled character out of the tree (`remove_child`), not hidden in it, and reset it on reuse:
  `AiCharacter._enter_tree` re-registers and restarts the mind, `AiSenses.forget_everywhere(node)` drops it from the
  others' memories. **Watch out for:** a hidden character in the tree stays in the director, the senses' lists, its
  groups and the minimap; and one re-added was not re-registered, because `_ready` runs once, so it stood still with
  no think. **Seen:** kit #969, 2026-11-11.
- **Approach:** Let a corpse lie outside the director's population cap: `AiDirector.register` and the match cap count
  the living only (`living_count()`), so a population that sits at `web_cap` respawns while its dead lie, and what
  lies on top is at most the spawners' `max_corpses` (20 for the AI section at scale 4), each stepped only at the rest
  cadence. **Watch out for:** a population at the cap with the dead counted was refused every respawn until a corpse
  went back to the pool (up to `corpse_seconds`), with an `AiDirector: ... refused` warning, and a refused character
  stands frozen in the level; a match cap lowered with corpses down parked living characters in their place. **Seen:**
  kit #1247, 2026-11-11 (the AI soak at `scale=4` in Chrome, kit #971;
  `test_a_corpse_does_not_count_against_the_population_cap`,
  `test_a_population_at_the_director_cap_respawns_while_its_dead_lie`).
- **Approach:** Ready a pool's spare with `AiCharacter.warming` on (`AiPool.prewarm` sets it around its `add_child` and
  `remove_child`), so its `_ready` joins no director; count refusals with `AiDirector.refused` and probe the web
  build for the `refused` warning before and after a fix. **Watch out for:** without it each spare made while the
  living sit at the cap was refused with a warning, and these were all 8 refusals of the soak at `scale=4` (the
  `max_corpses` spares, two of each kind): the counting fix alone left the same 8 in Chrome, because the issue's guess
  (the corpses) was not the whole cause. **Seen:** kit #1247, 2026-11-11
  (`test_the_pool_readies_its_spares_without_asking_the_director_at_its_cap`).
- **Approach:** Make a pool lazily (on the approach, one a tick); a suite that runs the map but is not about the AI
  sets `enabled = false` on each spawner of `World/AISection/Population` in `before_test` (`test_section_walks.gd`).
  **Watch out for:** parked characters are out of the tree, so GdUnit counts them as orphans and the run exits 101,
  which CI fails with every case green; GdUnit counts a case's orphans before `after_test`, so clearing the pool
  there is too late (still 1188). **Seen:** kit #969, 2026-11-11 (`test_camera_zone.gd`, `test_player_in_the_map.gd`
  walk within `wake_range` + 10 m; `Node.print_orphan_nodes()` named the parked grunts).
- **Approach:** Decide where a node runs by the map it is in (walk its ancestors for a `NetServer` or a sibling
  `NetClient`), and pick the players it measures from in its own world, before trusting an `OnlineRig` test of it.
  **Watch out for:** `spawns_here` read only the command line and `current_scene`, which in a rig is the test runner,
  so the server's spawners spawned with `on_server` off and a test of the switch passed either way; and
  `get_nodes_in_group(&"player")` held the clients' players of the other viewports too, so a client's player could
  wake the server's spawner and lead its allies. **Seen:** gdstudio #1234, 2026-11-11 (fix: `spawns_here`'s `from`,
  `_bodies_of`; `test_a_map_under_a_server_spawns_only_when_asked_and_beside_a_client_never`,
  `test_a_player_in_another_world_neither_wakes_it_nor_leads_its_friendlies`).

## The inspector {#inspector}

- **`AiSpawner`**: Spawn `scene`, `count` 3, `markers`, `respawn_delay` 10 s (below 0: no respawn), `cap` 0 (no
  limit), `enabled`; Waking `wake_range` 0 m (at once), `player_group` `player`; Wiring `patrol_route`,
  `leader_group`, `debug`; Bodies `max_corpses` 4, `corpse_seconds` 20 s, `settled_linger` 2 s; Network `on_server`
  off (on for the AI section's four). Signals `spawned`, `released`. Pinned by `test_ai_spawner.gd`.
- **`CharacterModel`**: `variant` (empty: the scene's own model), `body_layers`.
- **`AiSenses`**: `startled_by` ([AI senses: the inspector](ai-senses.md#inspector)).
- **`AiReactionRow`**: `noises` ([AI behaviour: the inspector](ai-behaviour.md#inspector)).

## What it costs {#cost}

`tools/bench/ai_section_bench.tscn` (`ai_section_bench.py` for Chrome) runs `main.tscn` with the section's whole
population (10) awake round the player: `watch`, the player stands in the doorway and never fires; `fight`, the
section's pilot walks the player round and shoots (deaths, respawns, civilians fleeing). The director's step a tick
(senses, brains, tasks, navigators, bodies), mean and p95 in µs, the living characters on average, and the median
frame work in ms:

| Where | Row | Step mean | Step p95 | Alive | Each | Frame work |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Desktop, native headless | watch | 385 | 628 | 10.0 | 38.5 | 1.11 |
| Desktop, native headless | fight | 385 | 561 | 9.8 | 39.5 | 1.21 |
| Chrome 1x | watch | 517 | 900 | 10.0 | 51.7 | 1.20 |
| Chrome 1x | fight | 483 | 700 | 9.3 | 51.9 | 1.30 |
| Chrome 4x | watch | 2,578 | 4,300 | 10.0 | 258 | 5.90 |
| Chrome 4x | fight | 2,437 | 3,900 | 8.4 | 291 | 7.50 |

Godot 4.7.2, Compatibility, the fast desktop of [Crowds](../crowds.md#ai-characters), 900 ticks a row after 120 of
warm-up, kit #969 (2026-11-11, the machine shared with other agents: calibration 7.0 ms at 1x, 31.5 at 4x). The section
fits [the budget](../crowds.md#ai-characters) with room: about half of the 1 ms a tick in Chrome and half of the 5 ms
at 4x, the p95 under both. A character costs about 50 µs a tick in Chrome, ten times the spike's thinking capsule and
in line with the fighting guards of [the behaviour bench](ai-behaviour.md#cost-follow-up) (the body and its aim are
most of it): a section of this mix (half of it fighting) reaches the budget at about 20, and the fighting ones count
by the behaviour bench's limits (12 in Chrome, 6 at 4x). The
soak's director step (180 s, desktop native) was 650 µs mean, 998 p95, with a moving fight and the respawns.

## The cost gate and the web probe {#cost-gate}

<!-- new section: the cost section above is the section's own population on the bench; nothing held the gate CI runs
     on the AI's counts and cost, or the browser numbers of the soak's populations -->

`tests/gameplay/test_ai_cost_gate.gd` (the template job) runs 50, 100 and
200 of the template's `civilian.tscn` on a 28 m test mesh round a visitor in the player's faction and a raider in the
enemy's (seen and fled from), 300 ticks after a 120-tick warm-up, under the director's shipped budgets with its desktop
cap raised to 200. Counts are held exactly: no character asks for more paths than its `repath_seconds` allows, thinks
more often than its `think_rate` or casts more than `max_rays_per_think` (2) rays a think, and the shared budget is
never overspent. Time is held as medians: the step a character and a think over the median of a ruler loop timed
every 50 ticks of the window (GDScript work of the AI's kind: vectors, an array, a dictionary, about 10 ms here), and
the hit history over the step of the same ticks (a section of a few microseconds that a loop does not follow:
[the ruler](../performance-budgets.md#budgets-counts-tight-time-loose)). Each limit sits between the highest ratio seen
and twice the lowest, so a step, a think or a record twice as slow fails (a run with each made twice as slow by a wait
failed every row), and a failure prints the row. Native debug build, Windows, 2026-11-11, on the prototype bodies;
the step and think columns are 4 runs with the ruler (2 of them side by side), the history column 11 runs (5 with two
or three copies of the gate beside it, 4 beside the full template suite):

| Civilians | Step a character a tick | A think | Hit history a character (`ai_history_us`) | Paths / thinks a second each | Rays a think | Walking |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 50 | 48 to 56 us (4.6 to 5.1 a ruler ms; limit 8.0) | 72 to 84 us (6.9 to 7.7; limit 13) | 1.7 to 3.0 us (0.031 to 0.038 of the step; limit 0.055) | 0.60 / 10.0 | 0.17 | 57 % |
| 100 | 44 to 47 us (4.1 to 5.1; limit 7.5) | 91 to 97 us (8.5 to 10.4; limit 14) | 2.1 to 3.8 us (0.034 to 0.049; limit 0.06) | 0.51 / 6.7 | 0.10 | 50 % |
| 200 | 35 to 40 us (3.3 to 4.0; limit 6.5) | 108 to 119 us (10.0 to 12.2; limit 18) | 2.6 to 3.5 us (0.046 to 0.063; limit 0.09) | 0.39 / 3.6 | 0.11 | 35 % |

- The first ruler was the soak's `sin` loop: on the Linux CI runner it took 7.5 ms against 12.5 on this desktop while
  the AI's step cost the same (60 us a character at 50), so the step read 7.9 to 5.9 loops there against 4.3 to 6.2
  here and failed CI. The C library's `sin` is not the AI's kind of work; the ruler now is.
- With the `sin` loop, 11 runs on a loaded machine (two or three copies of the gate, or the full suite, beside it)
  read the step at 46 to 95 us a character: load moves the microseconds 2 times and the ratio 1.6 times.
- The branch before the prototype bodies (Quaternius's mannequins), measured turn about with these, read the same: the
  body's look is not in the AI's step. The first table of this gate (34.9 us a character at 50, ratio 3.2) was a mean
  over one calibration on a quieter day.
- A think grows with the crowd (about 80 us at 50, 115 at 200) where the step a character falls: a frightened
  civilian's think walks more beliefs and tellings in a bigger crowd. The calm crowd (no raider) is 31 to 46 us a
  think.
- The server's record of every AI character's hit volume (`AiHitHistory`, #1198) is 2 to 3.5 us a character a tick:
  120 characters add about 0.3 ms to a server tick.

`tools/web_smoke/ai.py` loads the soak's web export (`gds template bench-web 3d-third-person tools/soak/ai_soak.tscn`)
with `?scale=N&pathing=0` (the AI section's 10 times N, the player fighting round it) for 15 s and reads the last 10 s
(Chrome on the fast desktop, before the attack slots of #1203 landed; a run after them read a calibration loop of 34 to
150 ms against 8 to 42 on a machine other agents had loaded, so it is not in the table; the page clean of console
errors; frame work and the AI step in ms, median / 95th percentile):

| Characters (fighting) | CPU | Frame work | AI step a tick | Ticks a frame |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 1x | 1.6 / 2.3 | 0.57 / 0.80 | 1.00 |
| 20 | 1x | 2.4 / 3.6 | 0.85 / 1.20 | 1.01 |
| 30 | 1x | 2.8 / 4.1 | 0.98 / 1.50 | 1.00 |
| 40 | 1x | 3.3 / 4.8 | 1.23 / 1.80 | 1.01 |
| 10 | 4x | 9.5 / 20.8 | 3.07 / 4.80 | 1.15 |
| 20 | 4x | 45.1 / 98.7 | 4.86 / 7.60 | 3.73 |
| 30 | 4x | 97.4 / 138.3 | 5.91 / 9.20 | 6.74 |
| 40 | 4x | 99 / 155 | 6.14 / 9.40 | 6.67 |

- The section's own population of 10 holds both budgets (0.57 ms, 3.1 ms at 4x); fighting populations of 20 and more
  fall off the tick cliff at 4x (3.7 to 6.7 ticks a frame), as [the fight table](ai-behaviour.md#cost-follow-up) says: a
  web fight needs the attack slots of #1203 to hold its engaged count.
- At 40 (scale 4) the director refused characters past its cap of 40 with a console warning: the spawners' corpses
  still count against the cap while they lie, so a population at the cap is refused on its first respawns.

## Proof {#proof}

`tests/gameplay/test_ai_characters.gd` (the four scenes, their looks and kinds), `test_ai_spawner.gd` (count,
markers, pool, respawn, corpses, waking, reuse, network, a player of another world), `test_net_ai_section.gd` (the
section online: a server and a client), `tests/world/test_ai_section.gd` (in `main.tscn` with the
real player: the cone, walking heard and crouching not, one shot heard by the shooter and the ally while only the
civilians run, killing an ally turns the allies Hostile). The AI soak `tools/soak/ai_soak.tscn` fights round the
section with its population and fails on any of its gates ([the AI soak](../../../gamedev/bots.md#ai-soak));
`tests/gameplay/test_ai_cost_gate.gd` holds the AI's counts and cost ([the cost gate](#cost-gate)).
`tools/capture/section_tour.tscn` (`SECTION_TOUR=fight|cover|chase|civilians`) films each from the game
camera; `tools/capture/ai_section_online_tour.tscn` films the section's fight online from a client's camera.
