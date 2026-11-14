# The AI and online parts

<!-- new section: the template page's table of parts reached the size limit (#1457); each row's place and
     notes moved here, for the AI characters and online play -->

The full row of each part of [the 3D Third Person template](../third-person-template.md#what-is-in-it), moved from its
table of parts (#1457): where it lives (in `templates/3d-third-person/game/`, the base in `templates/3d-blank/game/`),
what it does, its inspector and the pages with the rest. The AI characters and everything online: the packets and link,
the game server and its image, the predicting client, the online game scene, shots online and the networked map parts. A
new inspector line goes in its part's section here.

## AI characters {#ai-characters-part}

**Where:** `gameplay/ai/` (`AiCharacter` + `ai_character.tscn`, `AiController`, `AiProfile` and `profiles/*.tres`,
`AiDirector` in `world/world.tscn`, `AiBudget`, `AiSituation`, `relations/`, `senses/`, `navigation/`, `tasks/`,
`behaviour/`, `tasks/stock/`, `characters/`, `spawner/`, `ai_guard.tscn`, `ai_ally.tscn`, `ai_civilian.tscn`)

The base every enemy, friendly and civilian is made from: the dressed character driven by an `AiController` (the
navigator writes `walk_direction`, the action channel `look_direction`, `aim` and `fire`), with its senses
(`gameplay/ai/senses/`: an `AiSenses` node turning sight, hearing, touch and tellings into `AiBeliefs` on the think
tick, from the level's `AiNoise` board that every body's `AiNoiseMaker` writes, with a debug view of the cone, the rings
and awareness bars), an `AiNavigator` in the navigator slot (`gameplay/ai/navigation/`: `go_to`, `follow`, `stop`,
`arrived`, `failed`; path queries on a timer within the budget and only when the answer can differ, the goal and route
rules, the stuck ladder, links, a debug drawing) and its task layers (`gameplay/ai/tasks/`: an `AiTasks` node owning an
`AiTaskRunner` of `AiTask` resources in five layers, with sequences, parallels, repeats and selectors as tasks), and its
brain (`gameplay/ai/behaviour/`: the `AiBrain` in the `brain` slot routes each event through an `AiBehaviourSet` table,
`sets/hostile_guard.tres`, `friendly_ally.tres`, `civilian.tres`, into 18 stock tasks in `gameplay/ai/tasks/stock/`,
with Aggressive, Careful and Safe play states; the guard, ally and civilian scenes ship ready). The level's characters
are `characters/enemy_grunt.tscn`, `enemy_shooter.tscn`, `ally.tscn` and `civilian.tscn` (enemies in the male prototype
body by `CharacterModel.variant`, friendlies in the female), kept alive by an `AiSpawner` per kind from its `AiPool`;
the prototype map's AI section holds 3 grunts, 2 shooters, 2 allies and 3 civilians, woken when a player comes within 25
m, offline or on a game server ([Enemies, friendlies and their spawner](ai-characters.md#parts)). The `AiDirector` steps
the bodies (Full every tick, Reduced every 4th, Dormant every 6th, at rest every 3rd, the missed time handed on), runs
each think on its own phase, sets the tiers by distance to the nearest player and shares one `AiBudget` of rays, paths
and thinks a tick; its `AnimationThrottle` child (an `AiAnimationThrottle`, the `CharacterAnimationThrottle` with the
tiers) moves far, Reduced and unseen characters' animation less often, Dormant ones' not at all, and plays footsteps
only near the camera ([the animation throttle](ai.md#animation-throttle)). A web build holds up to 40 characters, but a
fight costs more than a walk: the director's attack slots let 6 guards engage one target and 12 in all in a browser (16
and 48 on the desktop and a server) while the rest hold with their guns down, measured with
`tools/bench/ai_behaviour_bench.tscn` ([AI behaviour: attack slots](ai-behaviour.md#attack-slots)). Factions and
relationships live in `gameplay/ai/relations/`: the `AiRelations` table (`ai_relations.tres`: `player`, `enemy`, `ally`,
`civilian`, asymmetric attitudes with banded hysteresis, events that only witnesses feel, recovery), the level's
`AiFactions` in `world.tscn` (lookups, reports, friendly fire through `HitZones`, the band rings) and an
`AiFactionMember` on each character and the player.

Inspector: `AiCharacter` `profile`, `debug`, the slots; every number on the `AiProfile`; `AiDirector` caps, budget, step
cadences, `animation_throttle` and attack slots; `AiAnimationThrottle` distances, periods and catch-up; `AiRelations`
factions, events, band lines, `hysteresis`, `recovery_per_minute`; `AiFactions` `relations`, `show_bands`;
`AiFactionMember` `faction`, `reports_events`; `AiTasks` `default_task`, `routine`, `attack_task`, `needs`; each
`AiTask`'s contract; `AiBrain` `behaviour`, `leader`, `patrol_route`, `home_radius`, threat recheck and reminder, bark
cooldowns, `authority_only`; the profile's play-state lines; each `AiReactionRow`, waiver and situation rule; `AiMarker`
`kind`, `route`, `wait_seconds`; each stock task's exports; `AiNavigator` `backend`, `repath_seconds`,
`refresh_seconds`, `arrive_distance`, `path_desired_distance`, `steer_seconds`, `look_ahead`, `nav_class`,
`navigation_layers`, `search_max_polygons`, `max_climb_speed`, `auto_traverse_links`, `check_reach`, `headroom_check`,
`avoidance`, `avoidance_radius`, `debug`; `AiSenses` senses, targets, awareness shares and `show_view`; `AiNoise`
`radii`, `occlusion`, `show_noises`; `AiNoiseMaker` footsteps and shots; `AiSenses` `startled_by`, `AiReactionRow`
`noises`; `AiSpawner` `scene`, `count`, `markers`, `respawn_delay`, `cap`, `enabled`, `wake_range`, `player_group`,
`patrol_route`, `leader_group`, `debug`, `max_corpses`, `corpse_seconds`, `settled_linger`, `on_server`;
`CharacterModel` `variant`. Online the AI runs on the server only: a client's own AI stands down when it joins
(`AiAuthority`) and its `AiReplica` (in `online_main.tscn`; inspector: `interp_delay`, `extrapolate_seconds`,
`glide_max_jump`, `extrapolate_mask`, `section_origin`, `variant_scenes`, `puppets_per_frame`, `puppet_budget_usec`,
`puppets_shown_per_frame`, `viewer`) draws the server's characters as puppets from the TICK's AI block, made and shown a
few a frame, nearest first ([the AI online](ai-online.md#replication)). The proof: `tools/soak/ai_soak.tscn` (inspector:
`AiSoak` `seconds`, `random_seed`, `population_scale`, `pathing_kinds`, `pathing_count_each`, `round_seconds`,
`rescue_seconds`, `quit_at_end`, `character_lines`, `warm_seconds`; `AiSoakWatch` every gate's threshold; `AiSoakFaults`
`faults`, `slow_think_usec`, `overdue_timeout`) and the cost gate `tests/gameplay/test_ai_cost_gate.gd` ([the AI
soak](../../../gamedev/bots.md#ai-soak)). [AI senses](ai-senses.md), [AI characters](ai.md), [Factions and
relationships](ai-relations.md#relations), [Tasks](ai.md#tasks), [AI behaviour](ai-behaviour.md).

## Net packets and link {#net-packets-and-link-part}

**Where:** `gameplay/net/` (the packets, the AI's `AiSnapshot`; `NetLink`, `WebSocketLink`, `WsListener`,
`LoopbackLink`, `LinkConditioner`), `tools/net/`, `ui/probe/net_probe.gd`

The bytes of online play ([packets](../multiplayer.md#template-packets)) and the transport under them: a WebSocket
client (desktop and web), the server's listener, an in-process pair and a bad network around any of them; polled each
physics tick; no inspector (code objects). [The template's transport](../multiplayer.md#template-transport).

## Game server {#game-server-part}

**Where:** `gameplay/net/net_server.gd` + `net_server.tscn`, `peer_slot.gd`, `core/net_args/`,
`tools/bench/server_bench.tscn`, `tools/net/server_bot.gd`

`godot --headless --path game -- --server [--port N]`: admits up to `max_players`, steps a `character.tscn` body per
player by that player's commands and sends every client a TICK 30 times a second; logs JSON lines.

Inspector (Server, Players, Rules and Shots groups): `port`, `bind_address`, `max_players`, `cap_frame_rate`,
`print_log`, `world_root`, `body_scene`, `body_items`, `players_root`, `spawn_group`, `spawn_seed`, `hold_ticks`,
`command_ticks`, `silent_seconds`, `hello_seconds`, `origin_slack`, `revive_seconds`, `revive_at_spawn`,
`ai_rewind_seconds`, `ai_rewind_flight_seconds` (a player's shot meets each AI character where the shooter's screen drew
it: `gameplay/net/ai_hit_history.gd`, `shot_rewind.gd`, [the AI online](ai-online.md#rewind)); AI group: `ai_rates`
(`AiTierRates`: `full_radius`, `reduced_radius`, `interest_radius`, `full_hz`, `reduced_hz`, `dormant_hz`,
`keyframe_seconds`), `ai_section_origin`, `ai_variants`, `ai_sees_players`. The AI runs here only and reaches the
clients in each TICK ([the AI online](ai-online.md#replication)). [The game server](game-server.md#template-server).

## Server image {#server-image-part}

**Where:** `server/` beside `game/` (`Dockerfile`, `railway.toml`, `stage.sh`, `deploy.sh`, `check.sh`),
`gameplay/net/process_stats.gd`

The game server as a Docker image (debian-slim, the pinned Linux Godot, imported at build time, run by a non-root user
under `tini` on `$PORT`) and its deploy to a Railway service; `check.sh` plays bots against any server and checks an
older client is refused. No inspector (files and scripts). [The server image](game-server.md#server-image).

## Online client {#online-client-part}

**Where:** `gameplay/net/net_client.gd`, `reconciler.gd`, `body_overlap.gd`, `stall_guard.gd`, `silence_walk.gd`,
`remote_players.gd`, `interpolation_track.gd`, `loopback_listener.gd`; `gameplay/player/player_puppet.gd`
(`Player.make_puppet()`, `puppet_to()`), `gameplay/character/puppet_vault.gd` (a puppet's vault, planned on the screen
that draws it); `tests/fixtures/online_arena.tscn`, `tools/net/predict_bot.gd`, `tools/capture/online_tour.tscn`; the
bad-network gate: `tools/net/bad_network_gate.py`, `bad_network.py`, `gate_server.gd`,
`tools/web_smoke/net_play_smoke.py`, `ui/probe/net_play_probe.gd` (`?netplay`; it joins after the level's warm-up,
`gameplay/net/join_wait.gd`), `circling_controller.gd`, `net_play_report.gd`; the long proofs: `tools/net/soak.gd`,
`tools/net/bandwidth.py`, `tests/fixtures/world_parity.gd`, `tests/fixtures/tcp_relay.gd`

Joins a server, plays the local `Player` at once with the server's own step and slides it to the server's answer (a
quarter a frame, a snap past 2.5 m or when a quarter lands inside a ledge), skips the catch-up ticks after a freeze and
first steps the body as the server stepped its own through it, and draws every other player as a puppet `player.tscn`
0.1 s behind, between two TICKs; nothing cosmetic is sent. `main.tscn` stays offline; `online_main.tscn` (the row below)
adds the client.

Inspector: `NetClient` `player`, `remote_players`, `ai_replica`, `world_root`, `join_on_ready`, `join_after_warm_up`,
`player_name`, `spawn_group`, `spawn_seed`, `rejoins`; `RemotePlayers` `puppet_scene`, `delay`, `animation_throttle`;
`CharacterAnimationThrottle` (the online scene's `PuppetAnimationThrottle`) distances, periods and catch-up. [The online
client](online-client.md#template-client); its proof over a bad network, native (in CI) and in the browser: [the
bad-network gate](online-gate.md#bad-network-gate); the soak, the unread client, the hostile cost and the bandwidth:
[the long proofs](online-client.md#soak-and-bandwidth).

## Online game {#online-game-part}

**Where:** `online_main.tscn` (+ `.gd`, a root scene beside `main.tscn`), `ui/online/online_status.tscn`,
`gameplay/net/join_wait.gd`, `frame_settle.gd`, `gameplay/player/player_bot.gd`, `ui/probe/online_probe.gd`
(`?onlineprobe`, `--onlineprobe`), `ui/menus/main_menu.tscn` (Play online), `ui/menus/menu_scene.gd` (`--connect`,
`?url=`); `tools/web_smoke/online.py`, `tools/net/other_version_server.gd`, `tools/capture/online_status_tour.tscn`

The offline game with a `NetClient`, `RemotePlayers` and an overlay of loading (the join waits for the level's warm-up
and settled frames), connecting, refused (another version: reload or update; full; another map), unreachable and lost,
each with Back to menu. Entered from the menu's Play online (an address field in a debug build only), from
`-- --connect ws://host:8910 [--name Ada]`, or from a page's `?url=wss://host`. `--bot route` or `--bot watch` plays
through the player's own input.

Inspector: `OnlineMain` `client`, `remote_players`, `player_rig`, `status`; `OnlineStatus` `menu_scene`,
`connect_seconds`, the Texts group; `MainMenu` `online_scene`, `server_address`, `address_field`; `MenuScene`
`online_scene`; `PlayerBot` `plan`, `turn_speed`, the Route group (`route`, `door_side`, `door_wait`, `stand_at`,
`shots`, `miss_degrees`), `fire_after`. [Playing online](online-client.md#play-online).

## Online shots {#online-shots-part}

**Where:** `gameplay/net/server_combat.gd`, `client_combat.gd`, `net_hits.gd`; `Weapon.authoritative`, `effects`,
`seed_base`, `fire_cosmetic()`; `Projectile.authoritative`, `stop_at()`; `Character.revive_at()`;
`tools/capture/online_shots_tour.tscn`

The server fires the real shots and owns every hit and health: it refuses a shot block from too far off the body or
during the cooldown (`REJECTED`), and sends `SHOT`, `HIT` (with the health left), `DIED` and `REVIVED` events; each
screen plays them with its own cosmetic shots, impacts, flinches and ragdolls (never sent).

Inspector: the server's Shots group above. [Shots, hits and deaths online](online-shots.md#template-shots).

## Networked map parts {#networked-map-parts-part}

**Where:** `gameplay/net/net_entity.tscn` (in `door.tscn`, `moving_platform.tscn`, `pickup.tscn`, `physics_prop.tscn`
and `target.tscn`), `gameplay/trigger_zone/trigger_zone_net.tscn` (under the map's pressure pad), `net_world.gd`,
`prop_state.gd`, `prop_track.gd`, `gameplay/moving_platform/platform_rider.gd`; `tools/capture/map_parts_tour.tscn`,
`tools/capture/props_tour.tscn`

Every door, platform, pickup, pushed prop and target of a map is owned by the server (props: the server simulates them,
their records ride each TICK while they move and a client's frozen copy is put at the predicted tick, [Pushed props
online](net-world.md#props); targets fall and stand by the server's word, [Targets online](net-world.md#targets)): the
panel and the slab are a function of the tick, put at each command's tick on both sides before the body steps, a change
starts `entity_lead_ticks` after the server decides it, a pickup is taken by the first server body and the client hears
who took it; a late joiner gets the table in its WELCOME; the pressure pad's plate is pressed on every screen by the
server's word (`TriggerZone.sensing` off on a client). No new inspector field on the parts. [Networked map
parts](net-world.md#net-world).
