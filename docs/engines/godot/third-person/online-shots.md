# Shots, hits and deaths online

<!-- new section: the game-server and online-client pages say how bodies move; nothing said who decides a hit online,
     what travels for a shot or a death, or what each screen makes itself (gdstudio #906) -->

The server of [the game server](game-server.md#template-server) owns every hit and every health; the clients of [the
online client](online-client.md#template-client) send presses and play small events. Part of [the 3D Third Person
template](../third-person-template.md); the bytes are [the template's packets](../multiplayer.md#template-packets).

## Who decides what {#template-shots}

<!-- new section: the server's rules for a shot and the events it sends, with the client's side of each -->

`ServerCombat` (`gameplay/net/server_combat.gd`, one on each `NetServer`) and `ClientCombat`
(`gameplay/net/client_combat.gd`, one on each `NetClient`); what a HIT names is `NetHits` (`net_hits.gd`).

- **The server fires the real shot.** Its bodies' weapons are the real ones (`Weapon.authoritative` on) with no
  flash, sound or mark (`Weapon.effects` off): the body fires along the command's shot block inside its own `step`,
  as offline, and its `Projectile` (a body on the server only) hits through `HitZones` or a `Health` as offline. The
  server's bodies have no model, so no hit zones: a shot on a body is a hit on the whole body (no head multiplier).
- **Before a step the server judges the shot block** (`ServerCombat.judge`): numbers that are not finite, an origin
  farther than `origin_slack` (4 m) from the body's eye, or fire pressed while the weapon cools down are refused. The
  shot block and the fire presses come off the command, nothing fires, and the sender alone gets `REJECTED` (its
  command's `seq`, the `ServerCombat.Reason`). A client cannot even send a number that is not finite
  (`CommandCodec.encode` refuses it), so that rule is for a hand-made packet.
- **Events.** A shot that leaves is a `SHOT` (slot, the low 16 bits of the command's `seq`, the loadout slot + 1, where
  it left, the way it went after the spread) to every other player, never back to the shooter. What it meets is a
  `HIT` (the point, the normal, the kind, the id, the health it left) to everyone. A body whose health reaches zero is a
  `DIED` (slot, the velocity of its last step, the cause); after `revive_seconds` (3 s) the server gets it up where it
  died (or at its spawn point with `revive_at_spawn`), in whole centimetres, and sends `REVIVED` with that point.
- **Melee** (#1254). A blow's press carries the shot block, so it is judged as a shot (a refused one takes the melee
  press off too) and meets the AI where the attacker's screen drew it, moved on by the ticks to its window. It is a
  4-byte `MELEE` (slot, the low 16 bits of `seq`) to every other player, its puppet plays its own clip, and what it
  meets is a `HIT`; an AI's blow is an `AI` event with the code `MELEE` ([melee](shooting.md#melee)).
- **Ids.** A player is `0xFF00 + slot` (the body carries the meta `net_slot` on every peer), a `Target` `0xFE00 +` its
  place among the map's targets (the group `target`) by node path in its viewport; anything else has no id and the
  client finds the surface with a 10 cm ray along the normal. The world table of #907 takes the low ids.
- **The spread is seeded by the slot and the command's number** (`Weapon.seed_base`, `shot_seq`), so a predicting
  client draws the same pellet as the server whatever either fired before; the puppets copy the server's heading.
- **The AI is the server's** (#970). A client's own AI stands down when it joins; the server's characters are drawn
  from the TICK's AI block, a player's shot on one is a HIT with the code `AI` and the id `NetHits.AI_BASE` + its
  wire id (the puppet flinches and shows the health left), an AI's shot is an `AI` event (the puppet fires a cosmetic
  shot) and what it meets a HIT, and an AI's death an `AI` event its puppet falls from
  ([the AI online](ai-online.md#replication)).
- **No rewind for players.** The server checks a shot against the players as they are: a projectile flies for many
  ticks, so the frame the shooter saw cannot decide where another player is. At 200 ms each way a shot at a running
  player drawn 1.3 m behind missed, the same shot at one who stood hit, on every screen
  (`test_at_200_ms_each_way_the_server_decides_what_a_shot_hit`).
- **The AI is met where the shooter drew it** (#1198): the command's `view_tick` is the tick the shooter's screen
  draws the AI at, and the server meets the shot with each AI character's capsule there (a hitscan shot at once, a
  projectile for its first `ai_rewind_flight_seconds`, the drawn tick moving on with its flight), then hits it where
  it is now. Only the volume is rewound, never the AI's brain, senses or navigation
  ([the AI online: a shot meets the AI where its shooter drew it](ai-online.md#rewind)).

- **A hitscan weapon** (`WeaponDef.hitscan`, #1252) is the cheapest shot on the wire: the server fires the ray in the
  body's step, meets the AI where the shooter drew it at once and sends the same `SHOT` and `HIT` in the same TICK
  (30 bytes to each other player); no peer makes a projectile, and every TICK is still exactly its header, players,
  props and events (`test_net_hitscan.gd`, `test_net_ai_rewind.gd`'s hitscan cases). A puppet's hitscan shot is its
  flash and sound; the shooter's impact comes with the server's HIT
  ([the costs](shooting.md#weapons)).

What each screen makes itself (`ClientCombat`), never sent: the shooter's own flash, sound, recoil and round at once
(its weapon is cosmetic: `authoritative` off, the round stops at its first contact and changes nothing); a puppet's
shot from its own muzzle along the event's heading with the weapon the event names (`Weapon.fire_cosmetic`,
`WeaponLoadout.equip_now`); the impact of the surface at the server's point (mark, effect, sound) and a cosmetic round
on its way there ends there (`Projectile.stop_at`); the health on the player or target (`Health.set_wire_value`: a
target at zero falls, a player's zero waits for its `DIED`); the flinch on the part this screen's pose has at the point;
the ragdoll, from the pose the body is in and the event's velocity; the get-up, the body standing at the server's point
at once and the pose blending there over `get_up_time` (`Character.revive_at`). Events about the local player play at
once; the rest wait until the puppets are drawn at their TICK's time (`RemotePlayers.drawn_time`), so a puppet's
shot leaves where the puppet is drawn and its hit lands as the round gets there. A dead puppet is left to its ragdoll
(`PlayerPuppet.place`); a ragdoll that falls out of the map waits for the server's `REVIVED`. A HIT near this screen's camera
shakes it (`NearHitShake` on the rig, from the impact; [the near-hit shake](../camera.md#shake-component), #1068).

- **Approach:** Name a thing a client must find again by its place among its kind in the same viewport
  (`get_viewport() ==`), and find a level's one-of-a-kind node (`Impacts`, `EffectEmitter`) the same way, whenever one
  process can hold several maps (the online tests and the side-by-side capture hold three). **Watch out for:** the
  targets were first filtered by `get_world_3d()` of the node asking, and the client asked from its `NetClient`, a
  `Node` with no world, so it counted the targets of all three maps and the server's `TargetB` was another map's on the
  client: the board fell on the server and on no screen. `Impacts.find` and `EffectEmitter.find` answered the first in
  the group, which in a test is another map's: a flash or an impact played in the wrong viewport. **Seen:** gdstudio
  #906, 2026-11-11 (`NetHits.targets_in`, `Impacts.find`, `EffectEmitter.find`).
- **Approach:** Space a test's or a bot's presses of fire one tick more than the weapon's interval (16 ticks for the
  pistol's 0.25 s), or press only when the predicted weapon can fire, as `PlayerInput` does. **Watch out for:** a press
  on the 15th tick finds `0.25 - 15 / 60.0` a hair above zero, so the server refused every second press as a cooldown
  violation and eight players measured two shots a second where four were meant. **Seen:** gdstudio #906, 2026-11-11
  (`test_eight_players_firing_four_shots_a_second_add_under_1_kb_a_second_down`, `server_bot.gd --shoot`).
- **Approach:** Before a test sends a body running across the map, check its lane is clear for the whole run (read
  the server body's position at the end), and assert the distance that makes the case (here how far behind the
  shooter's screen drew the runner). **Watch out for:** the first lane ran into a wall at x = 6.66 in a second, so the
  runner stood still when the shot came, the shot hit, and the latency case failed for the map, not the rule.
  **Seen:** gdstudio #906, 2026-11-11 (`LANE_START` in `test_net_shots.gd`).

## What it measured {#shot-costs}

<!-- new section: the numbers the bad-network proof (#908) builds on -->

Windows, Godot 4.7.2, other agents using the machine. The events: `SHOT` 15 bytes, `HIT` 15, `DIED` 9 (pinned by
`test_a_death_is_a_nine_byte_event_and_the_body_gets_up_where_the_server_says`, which also checks that every TICK is
exactly its header, events and players), `REVIVED` 8, `REJECTED` 6.

- **Bandwidth.** Eight players over real sockets, each firing at the floor (every shot a HIT): 936 B/s more down a
  client at four shots a second each, against a budget of 1024 (3183 B/s quiet, 3885 firing; a client hears seven
  SHOTs and eight HITs a round). The first layout, with the full 32-bit `seq` in a SHOT, measured 992.
- **A bad network, with bots.** A headless server, `tools/net/relay.py` at 200 ms each way with a 300 ms stall on 2% of
  chunks, seven bots of `server_bot.gd --shoot` and one `predict_bot.gd`, 32 s:

| | Without shots | With `--shoot` |
| --- | ---: | ---: |
| Shots, hits, deaths, refused (server) | 0 | 336, 306, 19, 17 |
| Server step p50 / p95 (ms), each 10 s window | 0.90 to 1.01 / 1.49 to 4.91 | 0.75 to 1.03 / 1.38 to 2.59 |
| Server out (B/s) | 25 800 to 25 900 | 27 600 to 28 500 |
| Down a bot (B/s) | 3054 to 3071 | 3358 to 3386 |
| Predicting client, `NetClient` a step p50 / p95 (µs) | 196 / 368 | 260 / 1493 |
| Events it played: shots, hits, deaths, get-ups | | 266, 240, 18, 19 |

No bot was kicked and the predicting client lost nothing. The bots fire at 1.4 shots a second on average (only with
someone alive to aim at); their 17 refusals are their own: a bot aims from its position in the last TICK, 0.4 s old,
so a sprinting bot's origin is now and then past the 4 m slack (a predicting client aims from its own body, within
centimetres of the server's). A first run on a busier machine read 385 / 3100 µs for the client.

- **What a client's event costs.** A shot played 529 µs on average and a hit 596 (worst 908 and 1253), a death 265 and
  a get-up 249. Almost all of it is starting the sound: in a probe, 50 `AudioStreamPlayer3D.play()` calls of the
  pistol's OGG randomizer took 25.8 ms, the 50 flashes 1.3 ms and the rest of 50 impacts 3.4 ms. The same sounds cost
  the same offline; the online part (the queue, the lookups, the cosmetic round) is a few microseconds. Since #1067
  the weapon and the impacts play their takes decoded once to PCM: on a native run with seven shooting bots a shot
  went from 663 to 216 to 252 µs and a hit from about 700 to 240 to 339, the same as with every sound off
  ([Audio: starting sounds](../audio.md#starting-sounds)).
