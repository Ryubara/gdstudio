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
| HELLO of a version `NetWire.accepts` refuses (outside `MIN_VERSION` to `VERSION`, both 2 since prone, #1012) | `REFUSED(version)`, then the close after the listener's linger |
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
  body once for each, so a client back from a stall catches up in a few steps; with none waiting, the last command is
  stepped again with its presses cleared (`clear_edges`) for `command_ticks` (30) steps, then one that asks for nothing
  (the view kept). The queue holds `NetLimits.TICK_RATE * NetLimits.STALL_SECONDS` (240); past that the oldest goes and
  its presses join the next (`merge_edges_from`). A body stepped six times in one physics frame ends where one stepped
  once a frame ends (`test_net_server_stream.gd`, within 1 mm on a floor): a predicting client may replay unanswered
  commands in one frame the same way. A held `prone` bit lays the body down (state `PRONE`, 11, in every TICK) and it
  crawls by the same commands (`test_net_server_stream.gd`).
- **Spawns.** Slot n starts at the n-th enabled `SpawnPoint` of `spawn_group` (`player`) in the bodies' world, by node
  path, wrapping past the last; the spot inside the point's radius comes from a generator seeded by `spawn_seed` and the
  slot (`spawn_transform(slot)`). `SpawnPoint.pick` is random among the points free this frame, so it cannot give a
  slot its own point; the prototype map has three (`PlayerA` to `PlayerC`).
- **Snapshots and events.** TICKs are full (no deltas). A TICK a full socket refuses is not sent and the events wait
  for the next (`peers_stalled` in the stats); at most 32 ride on one TICK and a client keeps at most 128 waiting. An
  event is something that happened once (`joined`, `left`); cosmetics never travel.
- **The world hash** is `NetServer.world_hash_of(root)`: the paths and `net_kind` metadata of the nodes in the group
  `net_part` (#907 adds them; the map has none yet). A client sends the same function of its own map.
- **The log** is one JSON object a line, said through `logged` too: `listening` (port, players_max, tick_hz,
  version), `joined` (slot, name, players), `left` (slot, reason `goodbye`, `dropped`, `silent` or `kicked`, players,
  drops), `refused` (reason, peer), `kicked` (peer, drops by reason), and every 10 s `stats` (players, tick,
  out_bytes_per_s, step_ms_p50, step_ms_p95, steps_over_budget over 6 ms, peers_stalled, kicked).
- **Clocks.** The connection rules read `NetServer.clock` (the machine's when empty, the frame clock in tests), as
  [a room over a real socket](../multiplayer.md#room-over-socket) says.

What it costs, measured on Windows with Godot 4.7.2 (other agents were using the machine):

| Run | Step p50 | Step p95 | Down a client | Up a client | Memory |
| --- | ---: | ---: | ---: | ---: | ---: |
| `tools/bench/server_bench.tscn`, 8 bots in the map, 600 steps (`test_net_server_cost.gd`, which fails at 6 ms p95) | 0.56 ms | 0.89 ms | 3210 B/s | 902 B/s | 106 MB static |
| A headless server process (`-- --server`) with 8 bots of `tools/net/server_bot.gd` in another process, two 10 s stats lines | 0.74 to 0.77 ms | 1.32 to 1.39 ms | 3201 B/s | 900 B/s | 169 MB working set, 130 MB private |
| The same process idle, no player | 0.02 ms | 0.03 ms | | | 168 MB working set, 127 MB private |

The bytes are payloads (the WebSocket frame adds 2 a packet down and 6 up): down is 30 TICKs of 107 bytes, up 60
commands of 15 and two pings. The template's menu scene alone, headless, is 142 MB working set and 90 MB private, so
the map, the bodies and the server add about 27 MB working set and 37 MB private; the image of #910 measures the Linux
resident size against the research's 80 MB estimate. The bot's round trip on localhost read 20 ms (rounded to its
frames) and every bot's `ack` trailed what it had sent by 2 commands, the ones in flight.

- **Approach:** Prove a server's step by stepping an offline body with exactly what the server applied: keep each
  slot's `history` (the `seq` of every command applied, or that the step repeated, stood or idled, grouped by step)
  and replay it in a world of its own; send the stream both one a tick and all at once. **Watch out for:** a paced
  client over a real socket on one machine may miss a frame now and then, so a test that compares against the plain
  stream fails on a repeat the server rightly made; the burst run proves the catch-up path the paced one rarely meets.
  **Seen:** gdstudio #904, 2026-11-10 (`test_net_server_stream.gd`).
