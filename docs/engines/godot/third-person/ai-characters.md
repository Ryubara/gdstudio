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
| Grunt | `gameplay/ai/characters/enemy_grunt.tscn` | `grunt.tres`, `hostile_guard.tres`, the male mannequin: patrols, engages, chases, searches. |
| Shooter | `gameplay/ai/characters/enemy_shooter.tscn`, `gameplay/ai/profiles/shooter.tres` | Engages at 24 m and prefers 16, aim 0.55, `careful_margin` 1.0: always in the Careful play state, so it fights from cover and peeks. Male mannequin. |
| Ally | `gameplay/ai/characters/ally.tscn` | `ally.tres`, `friendly_ally.tres`, the female mannequin: follows its leader (the player) and fights with it; startled by shots of anybody. |
| Civilian | `gameplay/ai/characters/civilian.tscn` | `civilian.tres` and set, unarmed (`Loadout.start_slot` -1), wanders 3 m round its home (`home_radius`), keeps away from a stranger with a gun (`remind_up_to` Unfriendly), and flees or cowers at a shot it hears from anybody (`startled_by` `shot`, the set's two heard-shot rows). |
| `AiSpawner` | `gameplay/ai/spawner/ai_spawner.gd` | Keeps `count` of one scene alive at its markers, wakes when a player comes near, respawns after a death, lets bodies lie and takes them back. |
| `AiPool` | `gameplay/ai/spawner/ai_pool.gd` | The spawner's characters, made once; a parked one is out of the tree. |
| `CharacterModel.variant` | `gameplay/character/character_model.gd` | Another model of the same rig in place of the one the base holds ([Replacing the model](character.md#replacing-the-model)). |
| AI section | `world/prototype/ai_section/ai_section.tscn`: `AiMarkers/` (the guard lane `guard_lane`, two shooter posts, 8 cover spots, 3 civilian homes) and `Population/` (Grunts 3, Shooters 2 on route `hold`, Allies 2 with leader `player`, Civilians 3; each `wake_range` 25 m, `max_corpses` 2, `on_server` on) | The population, placed and tuned in the scene (the template's `docs/design/map-sections.md`). |

Enemies wear the male mannequin and friendlies the female, so a side reads without the band rings. The older scenes
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

## Proof {#proof}

`tests/gameplay/test_ai_characters.gd` (the four scenes, their looks and kinds), `test_ai_spawner.gd` (count,
markers, pool, respawn, corpses, waking, reuse, network, a player of another world), `test_net_ai_section.gd` (the
section online: a server and a client), `tests/world/test_ai_section.gd` (in `main.tscn` with the
real player: the cone, walking heard and crouching not, one shot heard by the shooter and the ally while only the
civilians run, killing an ally turns the allies Hostile). The soak `tools/soak/ai_section_soak.tscn` fights round
the section for 180 s and fails on a character stuck for 3 s, idle with a threat in view for 5 s, or any engine
error. `tools/capture/section_tour.tscn` (`SECTION_TOUR=fight|cover|chase|civilians`) films each from the game
camera; `tools/capture/ai_section_online_tour.tscn` films the section's fight online from a client's camera.
