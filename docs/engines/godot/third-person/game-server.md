# The game server

<!-- new section: the multiplayer page held the transport and the packets (and is near its size limit); nothing held
     how the template's server admits, steps and answers players, which the predicting client (#905) and the server
     image (#910) build on -->

The 3D Third Person game server: who it admits, how it steps the bodies, what it sends and logs, and what it costs.
Part of [the 3D Third Person template](../third-person-template.md); the wire under it is
[the template's packets](../multiplayer.md#template-packets) and [transport](../multiplayer.md#template-transport).

## What it does {#template-server}

<!-- new section: gdstudio #904 added the server; nothing said how it runs, what each message gets in answer, or which
     numbers a client must match -->

`NetServer` (`gameplay/net/net_server.gd`) on a `WsListener`, one `PeerSlot` (`peer_slot.gd`) a connection.
`gameplay/net/net_server.tscn` is the map (`world/world.tscn`) and the server, with a `Players` node the bodies go
under.

```text
godot --headless --path game -- --server [--port N]
```

`MenuScene` (the main scene) reads `NetArgs.is_server()` (`core/net_args/net_args.gd`: `--server`, `--port`,
`--connect`, `--name`, `--bot`, or the page's query on the web, where `--server` is never true) and opens the server
scene before any menu. The port is `--port`, else `$PORT` (Railway), else `WebSocketLink.DEFAULT_PORT` (8910); `port =
0` takes a free one (`listener.port()`). The scene sets `cap_frame_rate`, so `Engine.max_fps` is the tick rate (60) and
a headless process does not spin; the step is `physics_ticks_per_second` (60, pinned by `test_net_limits.gd`).

| Message in | Answer |
| --- | --- |
| HELLO of a version `NetWire.accepts` refuses (outside `MIN_VERSION` to `VERSION`, both 4 since the shots, #906) | `REFUSED(version)`, then the close after the listener's linger |
| HELLO whose world hash is not `NetServer.world_hash` | `REFUSED(world)` |
| HELLO with every slot of `max_players` held | `REFUSED(full)` |
| HELLO otherwise | the lowest free slot (0 is the first; the codec carries 0 to 7), a body, `WELCOME` (slot, tick rate, the server tick, the world hash, every player with its name), and a `joined` event to everyone else |
| COMMAND with a `seq` past the last | queued |
| COMMAND before the hello, out of order, or one the codec refuses | a strike (`PeerLimits.fault`), then a kick |
| PING | `PONG` with the server tick |

Each physics step, in order: the listener is polled (the answers above); a seated peer with no command for
`silent_seconds` (15) and a connection with no hello for `hello_seconds` (10) are hung up on; every body steps once for
each command its slot hands out, in slot order; every second step each client gets a TICK with its own `ack` (the last
`seq` applied), every player and the events since its last TICK. The bodies are `character.tscn` (the body alone:
no model, animation, ragdoll or camera) with physics processing off, `ragdoll_by_command` off, and `fell` answered by
the slot's spawn point. Characters are on the Characters layer, which no character's mask lists, so bodies never block
each other ([Physics layers](../physics-layers.md#template-layers)).

- **Commands, exactly once and in order.** A step takes up to `PeerSlot.MAX_PER_STEP` (6) queued commands and steps the
  body once for each, so a client back from a stall catches up in a few steps; with none waiting, the body waits
  `hold_ticks` (4) steps without stepping (`HELD`: a command a step late, as two machines' frames drift, is waited for
  rather than guessed at, [the online client](online-client.md#template-client)), then the last command is
  stepped again with its presses cleared (`clear_edges`) for `command_ticks` (30) steps, then one that asks for nothing
  (the view kept). The queue holds `NetLimits.TICK_RATE * NetLimits.STALL_SECONDS` (240); past that the oldest goes and
  its presses join the next (`merge_edges_from`). A body stepped six times in one physics frame ends where one stepped
  once a frame ends (`test_net_server_stream.gd`, within 1 mm on a floor): a predicting client may replay unanswered
  commands in one frame the same way. A held `prone` bit lays the body down (state `PRONE`, 11, in every TICK) and it
  crawls by the same commands (`test_net_server_stream.gd`).
- **Every move is the character's own.** The server adds no rule of its own for a move: crouch pressed at a sprint
  slides the body (`SLIDE`, 12), a jump pressed in front of a wall that carries a `Vaultable` vaults it (`VAULT`, 13) or
  climbs onto it (`MANTLE`, 14), and the weapon presses (flag bits 11 to 14: reload, next, previous, the empty hands)
  switch and reload the body's `WeaponLoadout`, all through `step` (`test_net_server_moves.gd`). TICKs carry the state,
  never the weapon held or its ammunition: a SHOT names the weapon it left, and shots, hits and deaths are
  [their own page](online-shots.md#template-shots).
- **Spawns.** Slot n starts at the n-th enabled `SpawnPoint` of `spawn_group` (`player`) in the bodies' world, by node
  path, wrapping past the last; the spot inside the point's radius comes from a generator seeded by `spawn_seed` and the
  slot (`spawn_transform(slot)`). `SpawnPoint.pick` is random among the points free this frame, so it cannot give a
  slot its own point; the prototype map has three (`PlayerA` to `PlayerC`).
- **Snapshots and events.** TICKs are full (no deltas). A TICK a full socket refuses is not sent and the events wait
  for the next (`peers_stalled` in the stats); at most 32 ride on one TICK and a client keeps at most 128 waiting. An
  event is something that happened once (`joined`, `left`); cosmetics never travel.
- **The world hash** is `NetServer.world_hash_of(map)`: the paths from the map node and the `net_kind` metadata of the
  nodes under it in the group `net_part` (#907 adds them; the map has none yet). Both sides hash from the map node, the
  `World` instance: `NetServer.world_root` (`World` in `net_server.tscn`) and `NetClient.world_root` (`World` in the
  online arena), so what holds the map (a `SubViewport`, the tree's root, a menu scene) does not change the hash. The
  map need not be in the tree: `server_bot.gd` hashes a `world.tscn` it never adds. A new client scene sets
  `world_root` to its `World` (empty is the node's parent); `test_net_world_hash.gd` joins a client with one part and
  refuses one whose part moved (#1058).
- **The log** is one JSON object a line, said through `logged` too: `listening` (port, players_max, tick_hz,
  version, and the host's cpu and cores), `joined` (slot, name, players), `left` (slot, reason `goodbye`, `dropped`,
  `silent` or `kicked`, players, drops), `refused` (reason, peer), `kicked` (peer, drops by reason), and every 10 s
  `stats` (players, tick, out_bytes_per_s, step_ms_p50, step_ms_p95, steps_over_budget over 6 ms, peers_stalled,
  steps_held, steps_repeated, kicked; on Linux also rss_mb, anon_mb and cpu_pct from `ProcessStats`, [the server image](#server-image)).
- **Clocks.** The connection rules read `NetServer.clock` (the machine's when empty, the frame clock in tests), as
  [a room over a real socket](../multiplayer.md#room-over-socket) says.

What it costs, measured on Windows with Godot 4.7.2 once main's moves, weapons and character split had landed
(gdstudio #887, #1019, #1021, #1024, #1029, #1042; other agents were using the machine). Step times in milliseconds;
the process rows take the second 10 s `stats` line, the first with every bot moving.

| Run | 1 player | 2 | 4 | 8 |
| --- | ---: | ---: | ---: | ---: |
| `tools/bench/server_bench.tscn`, 1200 steps in the map, p50 / p95 | 0.10 / 0.16 | 0.16 / 0.22 | 0.30 / 0.40 | 0.54 / 0.73 |
| A headless server process (`-- --server`), bots of `tools/net/server_bot.gd` in another process, p50 / p95 | 0.18 / 0.30 | 0.28 / 0.47 | 0.43 / 0.69 | 0.69 / 1.02 |
| The same with `--moves` (weapon presses, a slide, three vaults and a mantle each), p50 / p95 | | | | 0.66 to 0.78 / 1.20 to 1.30 |
| Down a client (B/s) | 708 | 1067 | 1781 | 3211 |
| Server process, working set / private (MB) | 180 / 140 | 181 / 141 | 182 / 142 | 182 / 143 (183 / 144 with `--moves`) |

Up is 908 B/s a client in every run (911 with `--moves`), and no step went over the 6 ms budget once every bot was
in (one did in the first window of the 4 and 8 player runs, while the bots joined). Idle with no player the process
holds 180 MB working set and 140 MB private; the bench's static memory is 93 MB with one body and 101 MB with eight.
`test_net_server_cost.gd` fails above 6 ms p95 with 8 bots in the map.

The bytes are payloads (the WebSocket frame adds 2 a packet down and 6 up): down is 30 TICKs of 107 bytes, up 60
commands of 15 and two pings (8 players). On Linux, in its image and on Railway: [the server
image](#server-image). The bot's round trip on localhost read 13 to 22 ms (rounded to its frames) and every bot's `ack`
trailed what it had sent by 1 or 2 commands, the ones in flight.

With `--moves` every bot of `server_bot.gd` steers by its own position in the TICKs: the weapon presses, a slide on its
way to the map's `VaultCourse`, then the three vaults and the mantle; its `SERVER_BOT` line lists the states the
server sent for it. In the 8-player run above every bot saw `SLIDE`, `VAULT` and `MANTLE`, and the log held no
`kicked` line and no `ERROR`.

- **Approach:** Prove a server's step by stepping an offline body with exactly what the server applied: keep each
  slot's `history` (the `seq` of every command applied, or that the step repeated, stood or idled, grouped by step)
  and replay it in a world of its own; send the stream both one a tick and all at once. **Watch out for:** a paced
  client over a real socket on one machine may miss a frame now and then, so a test that compares against the plain
  stream fails on a repeat the server rightly made; the burst run proves the catch-up path the paced one rarely meets.
  **Seen:** gdstudio #904, 2026-11-10 (`test_net_server_stream.gd`).
- **Approach:** Have a bot that steers from TICKs press a move that needs speed (a slide) only after several TICKs in
  a row of `RUN` and a speed averaged over them, and report the states the server sent so a missed move shows.
  **Watch out for:** a press at a fixed tick, or on one TICK-to-TICK speed, missed the slide for two of eight bots and
  then for three: the prototype map drops off a ledge just west of the spawn points, so the crouch came in the air
  (`FALL`) and only crouched. **Seen:** gdstudio #904, 2026-11-10 (`tools/net/server_bot.gd --moves`).

## The server image {#server-image}

<!-- new section: #template-server says how the server runs in a process; nothing held its container, its deploy and
     what it costs on Linux and on Railway (gdstudio #910) -->

The template's `server/`, beside `game/`, puts the server in a container and on Railway:

| File | What it does |
| --- | --- |
| `Dockerfile` | debian:bookworm-slim; downloads the Linux Godot of the kit's `tools.toml` and checks its SHA-512 (the kit test `test_server_image.py` fails when the two differ); copies `game/` to `/app`, owned by the user `game`; writes `override.cfg` with two worker threads ([why](../multiplayer.md#headless-server-image)); imports at build time; runs `godot --headless --path /app -- --server` as `game` under `tini`, on `$PORT` (8910 when unset) |
| `railway.toml` | The Dockerfile builder and a restart on failure; no health check (the server speaks WebSocket only) |
| `stage.sh <folder>` | The build context: the two files above and `game/` without `.godot/`, the tests, the tools, GdUnit4 and the MCP addon (22 MB) |
| `deploy.sh <service> [stage]` | Stages, `railway up --ci` to the service, waits for `SUCCESS`; refuses with neither `RAILWAY_TOKEN` nor a linked folder ([which project](../../../studio/railway.md#link)) |
| `check.sh <url> [bots] [seconds]` | `tools/net/server_bot.gd` against a server: every bot welcomed and still connected at the end, then a hello of `NetWire.MIN_VERSION - 1` (`--version old`) refused for its version |

```text
server/stage.sh /tmp/stage && docker build -t game-server /tmp/stage
docker run --rm -e PORT=8910 -p 8910:8910 game-server
GODOT=<pinned godot> server/check.sh ws://127.0.0.1:8910 8 60
server/deploy.sh <service>            # from a scratch folder linked with railway link
GODOT=<pinned godot> server/check.sh wss://<service>.up.railway.app 8 600
```

TLS ends at Railway's edge, so the server speaks plain `ws://` and a client uses `wss://`. The bot's line carries
`connect_ms` (connect to WELCOME, TLS and WebSocket handshakes included) and its round trip's `rtt_ms_p50` and
`rtt_ms_p95`. `ProcessStats` (`gameplay/net/process_stats.gd`) adds to each `stats` line the resident memory
(`rss_mb`), the process's own part of it (`anon_mb`; the rest is the mapped Godot program, shared and reloadable, and
a container's memory counts close to `anon_mb`) and the share of one core (`cpu_pct`), read from procfs on Linux.

**Image and start.** 126 MB compressed, 272 MB in layers (the Godot program 146 MB, debian-slim 85 MB, `game/` 24 MB,
the import 9 MB); a build with no cache takes 23 s locally. From `docker run` to the `listening` line takes 1.0 to
1.2 s (Godot's own `t` 0.5 s); on Railway 1.1 s from `Starting Container` to `listening`, and 49 to 55 s from
`railway up` to a live deployment (upload, remote build, push). `docker stop` takes 0.4 s under `tini`; with Godot as
process 1 it took 10.3 s and ended in a kill (exit 137).

**What it costs on Railway** (us-west2, Intel Xeon Icelake, 48 cores; gdstudio #910, 2026-11-11): 10 minutes each with
2, 4 and 8 bots of `server_bot.gd` over `wss://` from a machine about 80 ms away, read from the 57 or 58 `stats` lines of
each run with every bot in (median window, then the range of the windows).

| Players | 0 | 2 | 4 | 8 |
| --- | ---: | ---: | ---: | ---: |
| Step p50 (ms) | 0.04 | 0.89 (0.82 to 1.07) | 1.33 (1.22 to 1.82) | 2.28 (2.06 to 2.84) |
| Step p95 (ms) | 0.07 | 1.69 (1.29 to 2.65) | 2.48 (1.88 to 5.32) | 4.16 (3.36 to 7.02) |
| Steps over 6 ms, of 36 000 | | 50 | 179 | 638 (1.8%) |
| Share of a core | 5.4% | 10.4% | 13.2% | 18.8% |
| Resident / own memory (MB) | 145.6 / 75.9 | 145.6 / 75.9 | 145.6 / 75.9 | 145.6 / 75.9 |
| Out (payload B/s) | 0 | 2 144 | 7 168 | 25 854 |
| Down / up a bot (B/s, frames included) | | 1 071 / 913 | 1 791 / 913 | 3 230 / 913 |
| Connect (ms, TLS and WebSocket included) | | 325 | 320 to 416 | 273 to 370 |
| Round trip p50 / p95 (ms) | | 83 / 90 | 82 / 90 | 82 / 89 |

No bot lost its connection, the log held no `kicked` line and no stalled peer, every `left` was a `goodbye`, and a
hello of version 2 was answered `REFUSED(version)`. The same image on a Ryzen 7 9800X3D (16 cores) under Docker
Desktop, 8 bots for 60 s: step p50 0.64 to 0.75 ms and p95 1.0 to 1.26 ms with none over budget, 7.0 to 7.7% of a
core, 145 MB resident and 77 MB own, round trip p50 14 ms; Railway's host steps the same work about 3.4 times slower.
Memory does not grow with players: the map, the bodies and the engine are there before the first hello, and the own
part (76 MB) is under the research's 80 MB budget, while the resident size (146 MB) counts the mapped Godot program.

With Godot's default worker pool (a thread a core, 48 there) the same deployment idled at 50 to 62% of a core and ran 8
bots at 64 to 82%, with the same step times (p50 2.0 to 2.6 ms, p95 3.4 to 6.0 ms): two threads cost a quarter of
that ([why](../multiplayer.md#headless-server-image)).

- **Approach:** Read a deployed server's step times against its host (`cpu` and `cores` in `listening`) and its p95
  windows, and budget for the host the game runs on, not the workstation. **Watch out for:** the same image stepped 8
  players in 0.68 ms median on a desktop and 2.28 ms on Railway's Icelake host, where 1.8% of the steps passed the
  6 ms budget and a window's p95 reached 7 ms; a budget proved locally was proved for the wrong machine. **Seen:**
  gdstudio #910, 2026-11-11 (the series above).
- **Approach:** Probe a WebSocket-only server with a WebSocket client (`server/check.sh`), never with `curl`. **Watch
  out for:** `curl -I` at the domain answered 502 from Railway's edge and left three engine lines `ERROR: Invalid
  method or HTTP version` (`wsl_peer.cpp`) with a GDScript backtrace in the server's log, which read like a fault of
  the server. **Seen:** gdstudio #910, 2026-11-11.
