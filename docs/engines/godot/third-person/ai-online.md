# The AI online in 3D Third Person

<!-- new section: the AI page's online part (kit #970) and the lag compensation for shots on the AI (kit #1198) took
     the AI page past the size limit; where the AI runs online, its wire, its costs and how a shot meets it are one
     subject -->

Where the AI of [AI characters](ai.md) runs in an online game, what reaches a client and what it costs, and how the
server meets a player's shot on an AI character. Part of [the 3D Third Person template](../third-person-template.md);
the bytes are [the template's packets](../multiplayer.md#template-packets), the shots [shots online](online-shots.md).

## Online: the AI runs on the server {#replication}

<!-- new section: the AI's base, brain and senses are on this page; nothing said where the AI runs in an online game,
     what reaches a client and what that costs on the wire -->

The AI runs only in the process that steps the world (the `NetServer`, or a game played offline) and reaches every
client as a few bytes a character at the end of each TICK (kit #970). The client draws each character as a puppet and
plays everything cosmetic itself; nothing cosmetic is sent.

| Part | Where (in `templates/3d-third-person/game/`) | What it does |
| --- | --- | --- |
| `AiAuthority` | `gameplay/ai/ai_authority.gd` | Decides where the AI runs, by map: `NetClient.join_with` calls `hand_over(map)`, which frees the map's `AiDirector` and every `AiCharacter` (their senses, brain, tasks and navigator with them) before any of them processes a frame and marks the map; an AI character or director that enters a marked map later takes itself out in its `_ready` (`runs_here`). A test counts a client's AI processing: zero. |
| `AiBroadcast` | `gameplay/net/ai_broadcast.gd`, one on each `NetServer` (`ai`) | Gives each AI character of the map a wire id (the meta `net_ai`), builds its row once a TICK (`AiRow`, its 14 bytes made once for every client), makes each client's block, and turns what happens once (alerted, fired, died, got up) into an AI event for each client that holds that character. Its weapons fire real shots with no effects; what they meet is a HIT (`ServerCombat.send_hit`). Only the characters the director manages are sent. |
| `AiSnapshot` | `gameplay/net/ai_snapshot.gd` | The codec: `encode(characters, view, rates, tick)` on the server and `apply(block)` on the client. A full snapshot, or a delta against the sequence the client holds: new or changed rows, moves (a character that only walked, 7 bytes), the ids that left. The layout and its pinned limits are in the script's header and [the packets](../multiplayer.md#template-packets). |
| `AiPeerView` | `gameplay/net/ai_peer_view.gd`, one in each `PeerSlot` (`ai_view`) | What one client holds: the last sequence, each character's bytes as sent and when. A TICK the socket refused resets it (the next block is full). |
| `AiTierRates` | `gameplay/net/ai_tier_rates.gd`, `ai_tier_rates.tres` (the server's `ai_rates`) | How often a client hears of a character by its distance from that client's body: within `full_radius` (20 m) every TICK (`full_hz` 30), within `reduced_radius` (40 m) at `reduced_hz` (7.5), within `interest_radius` (80 m) at `dormant_hz` (1), past it never (the client drops it); a full snapshot every `keyframe_seconds` (10 s) mends a client that dropped a delta. |
| `AiReplica` | `gameplay/net/ai_replica.gd`, a node beside `RemotePlayers` in `online_main.tscn` (the `NetClient`'s `ai_replica`) | Draws each character the client holds as a puppet: the dressed character of its look (`variant_scenes[row.variant]`, `character_dressed.tscn` by default) with no AI part, no collision and no step of its own, placed by its `AiGlide` and animated from the row (state, speed, aim, the pitch toward its target). A death starts the puppet's own ragdoll from one event with its velocity; a shot is a cosmetic shot from its muzzle; a HIT on it flinches it. |
| `AiGlide` | `gameplay/net/ai_glide.gd` | A playout buffer of rows (`interp_delay`, 0.1 s), each released row walked to over the ticks since the one before (even steps: 0.050 m a tick at 3 m/s from 30 Hz rows, and from 7.5 Hz ones), set down at once for the first row, a jump past `glide_max_jump` (4 m) or a gap past 2 s, and guessed ahead at its speed for at most `extrapolate_seconds` (0.1 s), never through `extrapolate_mask`. |
| Population | `AiDirector.match_cap`, set by `NetServer` from the HELLO's `F_WEB` flag | A browser in the match caps the population for everyone at `web_cap` (40): the newest characters past it are parked (frozen, not stepped, not sent) until the browser leaves. |

The server's inspector (`net_server.tscn`, group AI; the lag compensation's two are under Shots, [below](#rewind)):
`ai_rates`, `ai_section_origin` (positions travel as
centimetres from it, 327.67 m each way), `ai_variants` (a character's look on the wire is the index of its profile
here: `grunt.tres`, `ally.tres`, `civilian.tres`), `ai_sees_players` (the players' bodies join the group `player`
with the faction `player`, so the AI sees, fights and measures its tiers from them). The client's (`AiReplica`,
group Drawing): `interp_delay`, `extrapolate_seconds`, `glide_max_jump`, `extrapolate_mask`, `section_origin`,
`variant_scenes`.

### A shot meets the AI where its shooter drew it {#rewind}

<!-- new section: the replication above draws every character behind the server; nothing said where the server meets
     a player's shot on one, what is rewound for it and what that costs (kit #1198) -->

A client draws each character behind the server: the TICK's way down, the playout buffer (`interp_delay`) and a send's
glide, about 0.27 s at 150 ms each way, 1.1 m for a guard at a run; the command then takes its own way up. So the
server meets a player's shot on an AI character with that character where the shooter's screen drew it (lag
compensation, kit #1198); a player is still met where the server has it ([shots online](online-shots.md#template-shots)).

| Part | Where (in `templates/3d-third-person/game/`) | What it does |
| --- | --- | --- |
| `AiHitHistory` | `gameplay/net/ai_hit_history.gd`, the server's `ai_history` | Each character's feet and capsule (radius and height, 0 when dead) over the last `ai_rewind_seconds`, recorded with the TICK's rows from the same positions, so tick T here is what a client was sent for T; a tick between two records (every second step) is the line between them, as the client's glide walks it. |
| `ShotRewind` | `gameplay/net/shot_rewind.gd` | One command's view of the AI: `NetServer.rewind_for` makes it from the command's `view_tick` (16 bits made whole near the server's tick) and hands it to the body's `Weapon` (`Weapon.rewind`) for that step only. Each shot takes the characters within 4.5 m of its path (`for_shot`), out of its physics query (a ray's `exclude`, a projectile's collision exceptions), and meets their capsules here, each at the view tick less one send's glide at the rate the server sends it to that client (`AiTierRates.interval_ticks` less one). A character met is hit where it is now: the point is moved by what the character moved since, and its `HitZones` answer the moved ray, so the part, the multiplier and the HIT are the same as for a shot met in the world. |
| `view_tick` | `NetClient.view_tick()`, `PlayerCommand.view_tick` | The server tick the client's screen draws the AI at (`AiReplica.drawn_time`), not the newest TICK's tick: the client knows its own playout buffer, so the server keeps no copy of it. |

- **A hitscan shot or a blow** meets the drawn characters at once (`Weapon._scan`: the nearer of the world's hit and
  the drawn character's, `ShotRewind.nearer`).
- **A projectile** meets them for its first `ai_rewind_flight_seconds` (0.5 s, 22 m for the pistol's 45 m/s round),
  the drawn tick moving on one a tick with its flight, as the shooter's screen shows the round fly at puppets that
  walk on; each tick's move is tested against the capsules (widened by the round's radius) before the physics move,
  and a nearer wall or player still wins. Past that window the characters go back into its physics and it meets them
  where they are now: a round that flies on that long meets a character up to a round trip ahead of where the shooter
  drew it, as every round did before.
- **Never rewound:** the AI's brain, senses, navigation, its body in the physics world and its own shots. A shot
  older than the history (a client further than the history allows, or a hostile `view_tick`) is met at the oldest
  tick kept; a newer one at the newest.
- **What to aim at:** where the screen draws the character when the round gets there. A test or a bot that shoots a
  runner leads it by the round's flight (`test_net_ai_rewind.gd`'s `_drawn_chest`), as a player does.

The server's inspector (`net_server.tscn`, group Shots): `ai_rewind_seconds` (0.6 s, the history; 0 meets the AI as
it is now), `ai_rewind_flight_seconds` (0.5 s).

Proof (`tests/gameplay/test_net_ai_rewind.gd`, two clients over the real socket at 150 ms each way): a shot Ada's
screen draws on a running guard's chest hits on the server and flinches the guard's puppet on Bo's screen; with
`ai_rewind_seconds` at 0 the same shot misses (it missed on main); a shot led to where the server will have the guard
misses, and hits with the rewind off; the drawn guard is 1.8 mm on average (3.6 mm at worst) from the history at the
tick its shot is met at. `tests/gameplay/test_shot_rewind.gd`: the history, the 16-bit tick across its wrap, the ray
against a capsule, and the costs below. The clip `tools/capture/ai_rewind_tour.tscn` shows the server's world beside
Ada's screen: three shots with the rewind off miss, three with it on hit, a ghost capsule on the server's half where
each was met.

What it costs (Windows, Godot 4.7.2, 2026-11-11, one workstation shared with other agents):

| | 120 characters |
| --- | ---: |
| Recording the history, the codec's test (standing bodies) | 1.08 µs a character a record, 129 µs a record, about 65 µs a step |
| Recording on the game server (`bandwidth.py --players 4 --ai 120 --delay-ms 150`, every one walking) | 171 to 219 µs a record (1.4 to 1.8 µs a character), against 703 to 741 µs for building the rows; step p95 2.8 to 2.9 ms |
| A shot's pick of the characters near its path | 70 to 90 µs (all 120 looked at once a shot) |
| A projectile tick's meet | 2.1 µs a character near its path (126 µs for 60 near; 0 once its window is over) |

The native bad-network gate passed with the change (both runs, every check).

- **Approach:** Move a node's physics transform to the server yourself (`force_update_transform()`) when a query in
  the same tick must meet it where you just put it; a body that is placed only when a shot asks, like `HitZones`,
  needs it most. **Watch out for:** `HitZones.follow_bones` set the zones' body's `global_transform` and the second
  test's ray met them where the physics server still had them: at the spot of the shot before, or where the character
  spawned. The first rewound hits passed through a running guard (`zones.shot` answered null) until the transform was
  sent; offline a first shot on a character that moved since its last hit could do the same.
  **Seen:** gdstudio #1198, 2026-11-11 (`test_a_character_moved_since_the_last_shot_is_found_where_it_is_now`).
- **Approach:** In a test of a shot at a running character, aim where the target will be drawn when the round gets
  there (its drawn position plus its velocity times the flight), and print where the round met it before blaming the
  rule. **Watch out for:** the first test aimed at the drawn chest of a guard at 4 m/s; the 6 m flight took 7 ticks,
  the drawn guard ran 0.45 m on, and the round met the edge of the capsule but no zone: a miss that was right.
  **Seen:** gdstudio #1198, 2026-11-11.

### What it costs {#replication-cost}

<!-- new section: the numbers of the AI's wire, measured over the real socket, which the defaults above are read
     against -->

Windows, Godot 4.7.2, 2026-11-11, one workstation: the game server (`tools/net/gate_server.gd --ai N`, a crowd of N
walkers on circles over the 44 m square round the spawn dais, every one moving every tick: an upper bound), three bots
and one predicting client, each through `tools/net/relay.py` at 150 ms each way (a 300 ms round trip), the predicting
client's thread frozen 5 s at 12 s, 20 s counted once all were seated (`tools/net/bandwidth.py --players 4 --ai
0,40,120 --delay-ms 150 --freeze 12:5000`). Bytes are the relay's, WebSocket framing included.

| AI | Down a client, B/s: mean / most | Four players in all | Server: AI rows a TICK / blocks a TICK, step p95 | Client: apply a TICK p50 / p95, place a step p50 |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 2082 / 2084 | 8.3 KB/s | 4 µs / 28 µs, 1.1 ms | 4 / 5 µs, 3 µs |
| 40 | 7718 / 8767 | 30.9 KB/s | 319 µs / 355 µs, 2.1 ms | 169 / 472 µs, 275 µs |
| 120 | 16597 / 18541 | 66.4 KB/s | 1275 µs / 1010 µs, 3.8 ms | 481 / 1344 µs, 1026 µs |

The most-loaded client's AI share at 120 is about 550 B a TICK (18541 B/s less the 2084 of the players, over 30),
against Deadnight's 561 B a tick at 120 with an interest radius, and four players take 66.4 KB/s in all against its
67. Each client applied every block after the 5 s freeze (none refused) and settled within 8 mm of the server. The
first full snapshot makes every puppet at once: 61 ms for 40 and 185 ms for 120 in one frame on the desktop, the join's
hitch. The codec alone (`test_net_ai_snapshot.gd`, 120 walkers over 100 x 100 m): a full snapshot 1684 B, a delta 249
B a TICK on average; 40: 564 and 98.

In Chrome (`tools/web_smoke/net_play_smoke.py --gpu --ai 40`, the bad-network gate's browser half with the AI): every
gate passed at 42 frames a second (35 with no AI), 40 puppets, applying a TICK 100 µs at the median and 300 at the
95th percentile, placing them 200 µs a frame (the page's clock counts in 100 µs), the first full snapshot 60 ms. With
`--ai 120 --delay-ms 150` (a 317 ms round trip) the browser capped the match at `web_cap` (40 drawn, 80 parked on the
server) and every client check passed at 60 frames a second; the server's clock check failed once (28 steps lost in
the 10 s window while the page loaded, with 120 characters stepping). Drawn with SwiftShader (no `--gpu`) the page
fell to 7 frames a second with 40 puppets, under the gate's floor of 20, so the browser runs are judged on the GPU;
the puppets' own drawing cost is #1138's.

- **Approach:** Find a map's `AiDirector` by the viewport the character is drawn in (`AiDirector.find_for`), and have
  a director register only the characters of its own viewport and let go of them when it leaves the tree. **Watch out
  for:** one process may hold a server's map and its clients' maps (`OnlineRig`, a capture); `get_first_node_in_group`
  handed a client's director the server's 40 characters as it started, the client then freed its director on joining,
  and the server sent none of them (each held a freed director). **Seen:** gdstudio #970, 2026-11-11 (fix:
  `find_for`, the viewport check in `_ready`, `_exit_tree` letting go).
- **Approach:** Measure a crowd's bytes with every character walking near every player (`tools/net/bandwidth.py --ai`,
  an upper bound) before choosing a row's layout, and give a delta a compact form for what a crowd mostly does: walk.
  **Watch out for:** with 14-byte rows, 120 walkers within 20 m of a client cost 34.8 KB/s down a client, twice
  Deadnight's 561 B a tick; a move (id, centimetres moved, yaw, speed: 7 bytes) halved the codec's bytes for the same
  crowd. **Seen:** gdstudio #970, 2026-11-11.
