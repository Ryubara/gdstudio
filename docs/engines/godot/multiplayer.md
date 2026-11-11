# Multiplayer in Godot (web, server-authoritative)

What we learned building the Deadnight net spike (Godot 4.7.2, Compatibility renderer, web first). Game-specific
numbers and the architecture we chose live in that game's `docs/research/multiplayer.md`; this page is what any
GDStudio game can reuse.

## Why our own protocol: the comparison {#why-our-own-protocol-the-comparison}

Measured in Deadnight #38 (`docs/research/networking-comparison.md` there): 4 players and 24 zombies at 30 Hz,
localhost, bytes counted by a proxy in front of each stack.

| Stack | Down per client | Up per client | Server CPU (one core) |
| --- | --- | --- | --- |
| Own protocol (delta snapshots) | 2.4-2.9 KB/s | 0.56 KB/s | 2-4 % |
| MultiplayerAPI, server-owned synchronizers, input RPCs | 20-23 KB/s | 0.78 KB/s | 2.5-5 % |
| netfox 1.35.3, tuned | 30 KB/s | 12 KB/s | 26-28 % |

- The MultiplayerAPI is not quadratic when the server owns the synchronizers; client-owned synchronizers are, because
  the server relays each client's data to every other client.
- Feel at 100 ms and under TCP stalls was alike for our protocol and the MultiplayerAPI; TCP stalls hit both.
- netfox cost about ten times the server CPU, cause not isolated; it states no Godot 4.7 support.
- Railway documents TCP and HTTP only, and WebSockets on its HTTPS domain; a web client can only use WebSocket or
  WebRTC anyway.

- **Approach:** Before any netcode, write down who plays where (browser, Discord, desktop), the bandwidth each player
  has and where the server runs, and compare the options with measured numbers. **Watch out for:** the engine's built-in
  multiplayer was the first reach, a default rather than an answer to the game's constraints (players in a browser, the
  cost of hosting). **Seen:** Deadnight, 2026-11-01 (fix: deadnight runs its own protocol and backend, built
  network-first, chosen by the comparison above).

## The constraint that decides everything {#the-constraint-that-decides-everything}

A web client (and a Discord Activity inside an iframe) can only open **WebSockets** (and HTTP). No raw TCP/UDP, no
WebRTC through Discord's proxy. So the shape is: one authoritative server that clients reach over a WebSocket
(`wss://` in production). WebSocket runs over TCP: delivery is reliable and ordered, so packet loss never shows up as
a missing packet, it shows up as a **stall** (head-of-line blocking) followed by a burst. Design for stalls: tolerate
late data, send state (snapshots) rather than events that must each arrive, and never let the sim wait for a client.

## A client that freezes, measured on the live server {#a-client-that-freezes-measured-on-the-live-server}

Deadnight #483 (2026-11-02): a native headless client joined a night on the deployed server (guest sign-in, own lobby,
`wss`), walked, froze its own thread with `OS.delay_msec` and walked on. Worst gap to the server's position, then the
gap once it stood still:

| Client and round trip | Freeze 0 / 0.5 / 2 / 5 s |
| --- | --- |
| Before the fix, real round trip 66-124 ms | 0.8 to 3.9 m worst, 0.01-0.03 m settled: stable |
| Before the fix, 100 ms each way added (about 300 ms) | diverged before any freeze: thousands of metres, then 10^13 m and infinite |
| After the fix, about 300 ms, deployed | 2.2 / 2.3 / 4.3 / 6.0 m worst, 0.01-0.03 m settled |

- A prediction loop that is stable at 100 ms each way can be unstable at 300 ms round trip: test at the worst shipped
  round trip, with a push, closed (client, link and server), and freeze the client's thread, not only the link.
- Godot's WebSocket buffers default to 64 KB: a client that does not read for a few seconds makes the server drop the
  newest ticks. Raise them (1 MB), and send a whole frame, not a delta, after a tick the socket would not take.

- **Approach:** Test every closed loop (prediction, interpolation, rate limits) at the worst shipped round trip (300 ms
  and more) with a push, freeze the client's own thread (`OS.delay_msec`) over a real socket, not only the link, and
  read a server's `send` errors. **Watch out for:** the reconcile moved the body but not the remembered positions of the
  unanswered commands, so each answer corrected the same error once per frame in flight and a snap grew exponentially; a
  freeze sent eight catch-up ticks at once and the 64 KB socket buffers dropped the newest. **Seen:** Deadnight #483,
  2026-11-02 (fix: the reconcile shifts the remembered positions of the unanswered commands by every correction,
  snaps a body far from the server, and skips the catch-up ticks after a freeze; the loop is tested closed, in one
  dimension, at 50 to 400 ms).
- **Approach:** After moving a predicting client's body by hand in a test, move the server's too, call
  `reconciler.reset()`, let both settle, and read the camera on the frame after the body moved. **Watch out for:**
  `Reconciler` judges a frame by where its recorded command left the body, so a hand move reads as an error and snaps
  the body by it on top of where it stands (87 m out plus the 87 m "correction"); the rig is placed in `_process`, a
  wait on `RenderingServer.frame_post_draw` hangs headless, and a test spot inside a 3.8 m snow bank was pushed out by
  the physics. **Seen:** Deadnight #862, 2026-11-03 (fix: reset after the move; the camera read a frame later).

### The same in the browser (Deadnight #502) {#the-same-in-the-browser-deadnight-502}

The page's main thread is Godot's, so a busy loop run in the page (`page.evaluate`, a `while (performance.now() < end)`)
is the freeze a player gets, and the browser goes on receiving into the socket's buffer meanwhile. A probe that joins a
local game server in Chrome, walks, stalls 0.5, 2 and 5 s and compares the body with the server's position (published
by the game's probe object) found the **same desync in the browser** as the native one, but only with a round trip:
over loopback the pre-fix client came back to within 1 m of the server every time, and with a TCP relay that holds
each chunk back 100 ms each way (a round trip of 220 to 240 ms) it flew off to 10^22 m. The browser's own network
throttling does not touch WebSockets, so the delay is a relay in the probe. A 60 s stall also showed 670
`Buffer payload full` console errors with the 64 KB buffers and none with 1 MB (Deadnight `tools/web_smoke/freeze.py`).

The probe starts the game server as a process of its own. On Windows the console build of Godot is a wrapper that starts
the real program, so stop it with `taskkill /T /F /PID` (the tree) in a `finally`; a probe killed by a time limit leaves
the server running, and the next run cannot open its log ([Processes a probe starts](headless-probes.md#processes)).

## Godot's raw WebSocket, without the high-level multiplayer {#godots-raw-websocket-without-the-high-level-multiplayer}

- **Client** (desktop and web, same code): `WebSocketPeer.new()`, `connect_to_url("ws://host:port")`, then call
  `poll()` every tick and read `get_ready_state()` (`STATE_OPEN`, `STATE_CLOSED`), `get_available_packet_count()` and
  `get_packet()`. `send(PackedByteArray, WebSocketPeer.WRITE_MODE_BINARY)`.
- **Server** (desktop/headless only; a web export cannot listen): `TCPServer.listen(port)`; each tick
  `take_connection()` into a new `WebSocketPeer` with `accept_stream(stream)`, poll it until `STATE_OPEN`, then it is a
  client. Poll every peer every tick and drop it on `STATE_CLOSED`. No extra threads needed.
- Run both from one fixed tick (`physics/common/physics_ticks_per_second`, `_physics_process`), not from `_process`:
  the server then has the same rate on every machine and in headless mode.
- Put the network behind an interface (`send(bytes)`, `poll()`, `packet_received`) with a WebSocket and an in-process
  **loopback** implementation, plus a wrapper that adds delay, jitter and loss from a seeded RNG and the caller's own
  tick clock. The same server then serves single-player and tests, and "bad network" is a command-line option.
- `StreamPeerBuffer` is enough for a compact binary protocol: little-endian by default, `put_u8/put_8/put_16/put_u32`
  and the matching `get_*` (signed variants have no `u`). Check each packet's length before reading.

- **Approach:** Let the side that closes linger: stop sending, then send the close frame a few ticks later (0.25 s), so
  the other end reads the last packets in a poll of their own; a refusal is sent, then the server waits for the client
  to close. **Watch out for:** Godot 4.7.2's `WebSocketPeer` throws away every packet that reaches it in the same
  `poll` as the other end's close frame, in both directions: 20 packets sent and then `close()` arrived as 0 when the
  receiver had not polled between them (20 when it had), so "read to the floor after the close" saves nothing and a
  refusal sent with its close is lost. **Seen:** gdstudio #903, 2026-11-10 (fix: `WebSocketLink.close()` and
  `WsListener.disconnect_peer()` linger; a test keeps the engine's loss without the linger, so an engine fix shows).
- **Approach:** Give a listener its own handshake deadline (3 s, on the caller's clock) and its own packet-size cap
  under the inbound buffer, and hang up (1009) on a packet over it. **Watch out for:** `WebSocketPeer` has no
  `handshake_timeout` in 4.7.2 (that is `WebSocketMultiplayerPeer`'s), so a TCP connection that never sends the upgrade
  waits forever; a frame of exactly the inbound buffer's size (65,536 bytes into 64 KB) is accepted and passed on, so a
  flood of 64 KB frames went through until the cap; a 1 MB frame the engine refuses and closes itself. **Seen:**
  gdstudio #903, 2026-11-10.

## The template's transport (3D Third Person) {#template-transport}

<!-- new section: the sections above say how to use WebSocketPeer and what Deadnight measured; nothing said what the
     template's transport classes are, what they guarantee, or what 4.7.2 measured on localhost and in the browser -->

`templates/3d-third-person/game/gameplay/net/` carries packets and never reads them (the packets are the codecs'):

| Class | What it is |
| --- | --- |
| `NetLink` | The interface: `send(bytes) -> bool`, `poll()` once per physics tick, `is_open()`, `close()`, `close_code()`, `left_on_purpose()`; signals `packet_received`, `connected`, `closed`. |
| `WebSocketLink` | The client, desktop and web: `NetLimits.BUFFER_SIZE` inbound, 8192 packets, a lingering `close()`, `drop()` for tests, `server_url()` from `--connect <url>` or the page's `?url=`, and no `ws://` from an `https` page (`refusal` says why). |
| `WsListener` | The server: ids per handshake, `NetLimits.BUFFER_SIZE` outbound and `send` false when full (`refused_sends`), 64 KB inbound and a 4 KB packet cap (1009), a 3 s handshake deadline, a lingering `disconnect_peer` and a 1 s close grace, `port()` after `listen(0)`, `left_on_purpose(id)`. |
| `LoopbackLink` | `pair()`: two ends in one process; a packet sent in tick t is read in tick t+1; `close()` is a goodbye, `drop()` a network that went. |
| `LinkConditioner` | Wraps any link: `delay`, `jitter`, `stall_chance` and `stall_seconds`, `stall_for(seconds)`, a seeded RNG and a `clock` Callable; never reorders, a stall holds everything behind it. |

**One socket buffer size: `NetLimits.BUFFER_SIZE` (256 KB).** `WebSocketLink.inbound_buffer` and
`WsListener.outbound_buffer` both start from it and neither file has a constant of its own; `test_net_limits.gd` pins
the value and that both read it. It was 1 MB in the transport and 256 KB in the packets' limits until #934 measured it
in the browser (`net_link_smoke.py --inbound <bytes>`, a 5 s frozen tab at 35 KB/s, so 175 KB wait): 256 KB lost
nothing in six runs (0 `Buffer payload full` errors, every packet in order), 1 MB the same in two, and the 64 KB
control lost packets in 7 of 9 pages (4 to 86 errors; two pages lost none, so the smoke tries the control up to three
times). A size above that buys nothing in a freeze that short and costs 1 MB a peer each way on a full server.

Measured on Windows, Godot 4.7.2: a thousand packets each way over `127.0.0.1` in order; a conditioner of 100 ms each
way gave round trips of 217 to 250 ms on the physics-frame clock; two GdUnit runs of the suites at once on one machine
passed (`listen(0)`). In the browser (`tools/web_smoke/net_link_smoke.py`, headless Chromium, SwiftShader): the page
opened the address from `?url=`, refused `ws://` on an `https` origin (a Playwright route) without opening a socket, and
read every packet of a 35 KB/s stream through a 5 s busy-loop freeze with the 1 MB buffer, where the engine's 64 KB lost
packets out of order and logged 6 to 41 `Buffer payload full` errors (three runs). Round trips in that page are rounded
to its frames (the SwiftShader page ran at 6 frames a second): median 148 to 197 ms over loopback, 301 to 398 ms through
`tools/net/relay.py` at 100 ms each way. The relay alone, a Python TCP echo through it: 214 to 222 ms at 100 ms each
way, and with `--stall-chance 0.2 --stall-ms 300` up to 821 ms (9 stalls in 20 trips).

- **Approach:** Prove a socket buffer size where it overflows (the browser, or a real network), and pin the size with a
  test; on localhost test only what the buffer guarantees (nothing lost in 5 s at 35 KB/s, `send` false when full).
  **Watch out for:** on Windows loopback the kernel took about 200 KB beyond the listener's buffer before `send` was
  refused (207 KB with a 16 KB buffer, 261 KB with 64 KB, 1.24 MB with 1 MB), and a native client's 64 KB inbound
  buffer never overflowed because each poll reads at most what the kernel holds, so a native test of the 64 KB default
  passed and proved nothing. **Seen:** gdstudio #903, 2026-11-10 (fix: the browser control run with `&inbound=65536`;
  a native test pins the sizes); #934 (one constant, `NetLimits.BUFFER_SIZE`, after two parallel copies).

## The pattern that worked (own protocol over that transport) {#own-protocol}

- Fixed tick (30 Hz). The client sends one **input command per tick with a sequence number**, repeated redundantly (last
  1 to 3) if the link may lose packets; the server applies each input exactly once, in order, with a fixed step per
  input (so a client cannot go faster by lying and replays are exact).
- The server sends **snapshots** carrying its tick and the last input sequence it applied for that client. Send a
  **delta
  against the last snapshot that client acknowledged** (the client puts its newest snapshot tick in every input packet);
  fall back to a full snapshot when there is no baseline or a delta cannot express the change. 37 % fewer bytes with 8
  players all moving; far more when most are idle.
- The client **predicts** its own player by running the shared movement rule at once, and on each snapshot takes the
  server position, drops acknowledged inputs and **replays** the rest. Corrections are zero unless the server knows
  something the client did not (collisions): measure them.
- Others are **interpolated about 100 ms in the past** (3 ticks at 30 Hz) between the two snapshots around that time.
- Keep the simulation free of nodes and engine time (integer centimetres, `RefCounted`): the same code serves the
  headless server, single-player over an in-process loopback transport, and tests.
- Compact numbers: 5 bytes per player in a full snapshot, 3 in a delta, 12 bytes per input packet; about 0.4 KB/s up and
  0.6 to 1.0 KB/s down per client.

## The template's packets (3D Third Person) {#template-packets}

<!-- new section: own-protocol says what worked in Deadnight; nothing held the template's own layout, its sizes or how
its decoders stay quiet on a hostile packet -->

`templates/3d-third-person/game/gameplay/net/` (gdstudio #902) is the wire of an online game of the template, plain
`RefCounted` code with no node, socket or clock: `NetWire` (types, `VERSION`, the HELLO, REFUSED, PING and PONG, the
layout comment of every message, `world_hash`), `CommandCodec` (a `PlayerCommand` in 15 bytes, 27 with a shot block,
and the `snap_*` steps), `SnapshotCodec` (TICK and WELCOME, `PlayerEntry`, `NetEvent`, `EntityEntry`), `PeerLimits` and
`TokenBucket` (the budgets of one connection, time passed in by the caller), `NetLimits` (every shared number) and
`NetDrops` (why each packet was dropped). A transport carries the byte arrays as they are; what the same player
state costs against synchronizers is [below](#template-network-costs). Measured by
`test_net_snapshot_codec.gd` (it prints the line), against the research estimates of #883:

| Message | Bytes | Estimate |
| --- | ---: | ---: |
| HELLO with an 8-character name | 15 (7 + name; the world hash travels in it) | 3 + name |
| WELCOME, 1 player, no world parts | 30 | about 40 |
| WELCOME, longest (8 players with 16-byte names, 128 parts of 8 bytes) | 1783 | |
| REFUSED | 3 | 3 |
| COMMAND / with a shot block | 15 / 27 | 15 / 27 |
| TICK, 8 players, no events | 107 | 107 |
| TICK, longest (32 events of 19 bytes, 8 players) | 715 | |
| PING / PONG | 7 / 11 | 7 / 11 |
| Events: joined (4-letter name), left, shot, hit, died, revived, entity (3 bytes), pickup, rejected | 7, 2, 15, 15, 9, 8, 11, 4, 6 | shot about 17, hit about 12 |

What the command's fields mean, fixed by gdstudio #901: `move` is the push in the view's axes (`x` right, `y`
forward, no longer than 1), `yaw` the view's heading (0 looks along -Z, so the body's `facing` is `yaw + PI`), `pitch`
positive up; `crouch` is already the toggle's result; a press is true in one command. The shot block (`has_shot`) rides
only on a tick where a shot can leave (a press buffered or just made, or an automatic weapon held, and the weapon
ready), so fire held for three seconds measured 1302 B/s up for the pistol and 1346 B/s for an automatic one at four
shots a second (a command a tick and two pings, each with a 6-byte frame; 1286 with no block, 2006 if the block rode on
every held tick, against a budget of 2000). Flag bits 11 to 14 are the weapon presses (reload, next, previous,
the empty hands; gdstudio #887) and bit 15 is prone (#1012); no flag bit is free. `NetWire.VERSION` 4 (#906): a shot
carries the weapon and the low 16 bits of its `seq`, a hit the health it left
([shots online](third-person/online-shots.md#template-shots)).

A flood of commands sent as fast as a loop can is cut off after 444 packets (240 of burst, then 0.5 strike each to
100); an honest client at 60 a second with two pings is never struck, and 3 s of stall (180 commands at once) passes.

- **Approach:** Read every field through a reader that checks the length before each read and answers 0 with an `ok`
  flag, validate a name's UTF-8 by hand before `get_string_from_utf8()`, and test every prefix of a valid packet and
  a few hundred one-byte mutations for exactly one counted drop each. **Watch out for:** in Godot 4.7.2
  `PackedByteArray.decode_u16` past the end prints an `ERROR` with a backtrace and `get_string_from_utf8` on a broken
  sequence prints `Unicode parsing error`, both answering a value anyway: a hostile client could fill the server's log
  with one packet a tick, and a decoder that trusts the value reads garbage. **Seen:** gdstudio #902, 2026-11-10 (a
  probe printed both; `WireReader` and `NetWire.valid_name`).
- **Approach:** Compare a position decoded into a `Vector3` with a tolerance (`is_equal_approx`, or the range plus
  0.0001), and keep the limit itself a `float` constant. **Watch out for:** a `Vector3` holds float32, so the far edge
  of the centimetre range, 327.67, reads 327.670013 and an exact `<=` against `NetLimits.POSITION_RANGE` failed 86
  times in one run. **Seen:** gdstudio #902, 2026-11-10.

## Godot's high-level multiplayer: what to know {#godots-high-level-multiplayer-what-to-know-before-using-it}

`MultiplayerSynchronizer` / `MultiplayerSpawner` / RPC work over `WebSocketMultiplayerPeer` and are quick to start
with, but, measured in the spike (4 clients, each client-owned input synchronizer at 30 Hz and a server-owned position
synchronizer at 20 Hz): the server **relays** client-owned synchronizer data to every other client, so traffic grows
with the square of the player count (per-client upstream 1.8 KB/s with 2 players, 3.7 with 4, 6.1 with 8) unless you
restrict visibility by hand (`public_visibility = false` and `set_visibility_for`). There is no snapshot
acknowledgement,
no prediction and no interpolation hook; node paths must match between peers; and `WebSocketMultiplayerPeer` ids are
random 31-bit numbers. Fine for a prototype; for a game with a real tick, own the protocol.

- **Approach:** Connect both `synchronized` and `delta_synchronized` of a `MultiplayerSynchronizer`, and take the first
  real update as the starting point, not the spawn value. **Watch out for:** properties in `REPLICATION_MODE_ON_CHANGE`
  arrive as a delta sync, which emits `delta_synchronized`; `synchronized` fires only for full syncs (`ALWAYS` and the
  spawn state), so values replicated but prediction and reconciliation never started, and a spawn packet can carry a
  stale value. **Seen:** Deadnight #38, 2026-11-01 (fix: both signals are connected in the networking spike).

## What a template-sized game costs on the wire {#template-network-costs}

<!-- new section: the comparison section measures 4 players and 24 zombies; nothing said what only players cost, or what
SceneMultiplayer.send_bytes costs against a synchronizer, which decides the networking of a small template -->

Measured in gdstudio #883 (`sandbox/template-net/`, Godot 4.7.2 headless, localhost, a counting TCP proxy that includes
WebSocket framing): a server walks N players and sends their state at 20 Hz to one client over
`WebSocketMultiplayerPeer`, five ways. KB/s down per client (bytes per tick):

| Mode | 2 players | 8 players | 16 players | 16, 4 walking | 16, all standing |
| --- | ---: | ---: | ---: | ---: | ---: |
| One `MultiplayerSynchronizer` per player, 5 properties, `ALWAYS` | 1.67 (83) | 6.89 (345) | 13.16 (658) | 11.98 (599) | |
| The same, `ON_CHANGE` | 1.83 (92) | 7.38 (369) | | 3.76 (188) | 0.00 (0) |
| One synchronizer, one `PackedByteArray` property of 11 B | 0.97 (48) | 3.72 (186) | 7.45 (372) | 7.44 (372) | |
| One `unreliable_ordered` RPC with every player in a buffer | 0.70 (35) | 2.15 (108) | 4.10 (205) | 4.10 (205) | |
| `SceneMultiplayer.send_bytes`, the same buffer | 0.66 (33) | 2.10 (105) | 4.06 (203) | 4.08 (204) | 4.06 (203) |
| `send_bytes`, only the players that changed | 0.66 (33) | 2.10 (105) | 4.06 (203) | **1.14 (57)** | 0.18 (9) |

- A player's state is 12 bytes as one entry (slot, position in centimetres `s16` x3, yaw `u16`, state, flags, pitch),
  43 with five synchronized properties (Variant headers) and 23 packed in one property. A packet adds 6 bytes of
  header and 2 of WebSocket frame. `send_bytes` costs 3 bytes a packet over the payload: the peer layer is as cheap as a
  raw `WebSocketPeer`; the cost of the high-level API is the synchronizers.
- `ON_CHANGE` saves nothing for walking players (position changes every tick) and everything for standing ones.
- A client's input costs 0.57 KB/s as `send_bytes` (30 packets a second of 12 B, 19 B on the wire with the headers)
  and 0.63 KB/s as an RPC.
- On a WebSocket an `unreliable_ordered` transfer is accepted and every packet still arrives (reliable and ordered, it
  is TCP); a design for this transport sends state again rather than relying on loss.

- **Approach:** Choose between synchronizers and own packets for a small game by what the game needs on the wire
  (a tick, an acknowledged command number for prediction, an interpolation clock), then check the bytes per player per
  tick: at 8 players the gap is 6.9 against 2.1 KB/s. **Watch out for:** Deadnight's 8x gap was 24 moving zombies,
  not players; for 2 to 16 players alone the synchronizers fit any link, and what they cannot give is the tick and the
  ack, so a game with prediction writes its own packets next to them anyway. **Seen:** gdstudio #883, 2026-11-10
  (the table above; the template's design is in the research report of that issue).
- **Approach:** Pack a player's state into one buffer (about 12 bytes) before the first measurement and send all
  players in one packet; repeat the measurement with half the players standing. **Watch out for:** a synchronizer
  per player with `ALWAYS` sends every property of every player every interval, standing or not (16 players, 4
  walking: 12 KB/s, the same as all walking), and Variant headers triple the entry. **Seen:** gdstudio #883, 2026-11-10.

## A room over a real socket, faster than real time (Deadnight #230) {#room-over-socket}

A soak of a game server's room with real clients (ten game minutes, two people and two bots) runs in about three
minutes of wall time on one headless Godot process: `--fixed-fps 60` makes each frame exactly one physics tick and
removes the pacing (no vsync headless), so the server, the clients and the bots step as fast as the machine allows. Two
things have to run on game time, or the run fails for a reason that is not the code: the server's connection rules (a
peer may send 90 commands a second: at fixed-fps the wall clock sees several hundred and kicks it), which take a
`clock` Callable (`NightHost.clock`, `Engine.get_physics_frames() / 60.0`), and the client link's own clock
(`WebSocketLink.clock`). A run through a `GameServer` (tickets, rooms) sets `GameServer.clock`, which times the server's
own hellos and gives every room it opens the same clock (Deadnight #1059: without it the first bench lost its client
within a few seconds). Everything else already counts frames. The numbers: 36,000 ticks, server step 1.5 ms mean for
two autopilot clients and two bots, no engine error in the verbose log. The soak is
`tests/captures/bots_slots_soak.tscn` in Deadnight, a CI job of its own because it is too long for a test shard.

## The two worlds must hold the same solid things {#the-two-worlds-must-hold-the-same-solid-things}

A predicting client moves its body against its own copy of the map, the server moves the real one against the server's.
A solid thing that only one holds is a wall the other walks through, and the client's body then drifts metres from the
server's (Deadnight #748: a prize crane's cabinet, a `StaticBody3D` that the client-only drawing added to itself). Views
and drawings carry no collision; a solid thing is built into the world both sides build and moved there by the rules
(server) and the frame (client). The same goes for the bodies: the client draws the other players as puppets with no
collision, so the server's bodies must not block one another either (Deadnight #760: a body on layer 1 with a mask of 1
and 2 stopped at a teammate for good; players now sit on a layer of their own). Test it with a real client and host:
list every `CollisionObject3D` and colliding `CSGShape3D` under each side's viewport and compare them
(`tests/net/test_world_parity.gd`).

- **Approach:** Build a solid thing into the world both sides build and move it by the rules (server) and the frame
  (client); a view script adds no collision (a node it makes with `.new()` gets none), and a test joins a real client to
  a real host and asks that every solid thing in the client's viewport is in the server's at the same place. **Watch
  out for:** the prize crane's drawing gave itself a `StaticBody3D`, a game server draws nothing, so a sprint past it
  stopped the client's body and not the server's, and a soak failed under load with "client N is 2.5 m from the
  server"; a stall guard was blamed first, and a trace of what each world held at the server's spot found it.
  **Seen:** Deadnight #748, #754, 2026-11-03 (fix: `CraneBlock` lives in `NightWorld`; the test failed on main, 227
  against 226).
- **Approach:** Keep played bodies on a layer of their own that no body's mask lists, so bodies never block one another
  on either side, and list `PhysicsLayers.BODY` in the mask of every ray that must meet a body (a shot, a swing, a
  grenade, footsteps, a ping). **Watch out for:** bodies on layer 1 with a mask of 1 and 2 stopped at a teammate on
  the server and not on the client, whose puppets have no collision; the 0.6 to 0.9 m that left grew into metres at
  the next corner, the gaps sat just over the reconciler's 2.5 m snap, and a correction that cannot move a blocked body
  hides the rest. **Seen:** Deadnight #760, 2026-11-03 (fix: layer 4; the soak compares both worlds' solid things every
  300 ticks and names what each body slid on; a missed ray broke `test_smallmap_bot_night`).
- **Approach:** When a map ships, play it through every path that builds a night (solo, host, a client built from the
  WELCOME, the balance simulator) and assert that the host's and the client's economy has the map's rules. **Watch out
  for:** the map's rules overlay (`MapTuning`, laid by `NightWorld.rules_for`) was applied by the solo night and
  `SeatedNight` only, so `NightHost` and `Night.start_remote` built the map's scene with the shared table and the
  room's server threw at `use_offers.gd:20` for want of the door items. **Seen:** Deadnight, 2026-11-03 (fix: both lay
  `world.rules_for(table)`; `test_map_choice_net.gd`).

## Every client sees the same bodies {#appearance}

<!-- new section: the solid-things section compares collision; nothing covered how bodies look and stand on every
client -->

- **Approach:** Dress every body, the player's own included, from one appearance table the server owns, build local and
  remote bodies from one scene (or one shared transform), and test two clients over the real socket: every player shows
  the same parts, colours, skeleton height, scale and facing on every client and on the server. **Watch out for:**
  bodies were dressed only on the loopback path, two windows on one machine shared one settings file, and the player
  scene turned its model half round and scaled it 0.8 while remote avatars did neither, so on the other screen a player
  was a quarter taller and faced the camera. **Seen:** Deadnight, 2026-11-01 (looks); Deadnight, 2026-11-01 (height)
  (fix: the two-client test, and a `--look` flag that gives local windows different looks).
- **Approach:** Build and test every player-visible feature twice, as the player sees themselves and as every other
  client sees them, from the same state and events: a two-client test over the real socket asserts the other client's
  screen for each action (weapon, swap, aim, fire clip and flash, reload, swing, throw, a late joiner). **Watch out
  for:** online, a remote player was a bare model with no `PlayerAnimation`, so everything that draws a weapon got null
  and the aim pose was not in the frame; every test looked at the local body. **Seen:** Deadnight #518, 2026-11-02 (fix:
  remote bodies are the same scene as local ones (a puppet `Player`), the frame gains `aim` and `pitch`, captures come
  from the second client (Deadnight #548); code that works through a node type (`as Player`) turns "no such body" into
  a silent skip, so say it loudly); gdstudio #905 (online-client.md#puppets).

## Events reach a client only through its command loop {#events-reach-a-client-only-through-its-command-loop}

A test client that is driven by hand must still send its command every tick (`night.ticked` connected to
`link.send(command.to_dict())`): the server answers a command with the tick's events, and without one the client is
sent only the spawn requests. Fire with the same command a player's input makes (`NightCommand.aim_along`, `fire`),
never with `server._combat(...)` beside the step: the server refuses a shot whose view disagrees.

A test that is the server (a kill, a purchase, a blow, a repair made with `rules.apply`) is heard by the server's own
listeners (the tallies) and by no client unless its events are sent on: `room._collect(rules.apply(action))`
(`NightHost._collect`). Compare a client's count only after the client has heard the event.

- **Approach:** Send every event list the server produces, for a request and for a tick, to the clients, and test a path
  with no request in it (a reload that finishes on its own). **Watch out for:** only the answers to a client's request
  were sent back, so points rose but the target stayed standing and no burst showed after a lobbed shot: a projectile
  bursting, a reload finishing or a round ending happen inside the server's tick. **Seen:** Deadnight, 2026-11-01
  (fix: both lists are sent; a test of a path that has no request).
- **Approach:** Drive a test client by its command: connect `ticked` to `link.send(command.to_dict())`, keep one
  `NightCommand` per client and aim and fire it as the player's input does (`aim_along`, `fire`), never call the combat
  server by hand. **Watch out for:** the night server waits for each player's command and answers with the tick's
  events, so a client that sent none heard only `zombie_spawn_requested`, and a shot made beside the step had an origin
  the server refuses. **Seen:** Deadnight, 2026-11-03 (fix: the two-client test sends a command every tick).
- **Approach:** Deliver an event a test makes itself as the link would (`night.state.apply_events(rules.apply(action))`
  in one process, `room._collect(rules.apply(action))` online), run one tick, and wait on the client's state, never on
  the call. **Watch out for:** the server returns only the events of its own `apply` and `step`, so a call made beside
  it is in no client's stream: the HUD read "NEED 350 POINTS" with 600, the clients' witness stayed at 0 kills while
  the server was in round 2, and the loopback link delivers on `pump()`, so `night.state.over` read false until a tick.
  **Seen:** Deadnight, 2026-11-01 (HUD); Deadnight, 2026-11-04 (loopback); Deadnight #1074, 2026-11-05 (clients).
- **Approach:** Send an event that names a thing before the event that announces it (`NightHost._name_seat` before the
  `JOIN`), and when a change adds data to an existing flow list every text built from the earlier event; when a test
  waits for a string that never appears, print what the notice list did hold. **Watch out for:** `player_added` and
  `player_named` went in one tick, so the notice read `PLAYER 3 JOINED` and later `CY LEFT`, and a test that waited for
  `PLAYER 3 LEFT` suggested a lost event where the product was inconsistent. **Seen:** Deadnight #542, 2026-11-02 (fix:
  the name goes first and the test asserts names).

## A room test that needs a map or a fast round {#a-room-test-that-needs-a-map-or-a-fast-round}

A ticket's map is kept only when the host's level opens it, so name a host level (`TicketMaker.make(..., settings, 12,
seat)` opens the back rooms at 10) and assert `room.server.rules.settings.map` first. The count multiplier is also the
speed of the spawns: below 1 a round is smaller and the dead come that many times as slowly (0.25: four times), above 1
they come faster. A test about many rounds takes 0.25; a test about seconds takes 2.
The spawn clock is the real cost of a round, not the play: at the shipped tuning a round of a night at 0.25 waits 13 s
for each dead. A room test that plays rounds shortens it in its own copy of the tuning
(`rounds.first_spawn_delay = 0.1`, `spawn_interval_start = 0.1`, `spawn_interval_min = 0.05`); Deadnight #1074's
online suite of 11 cases went from 270 s to 23 s that way, with the same checks, and a shard fails at 80% of its
time limit.

## Act on a rules event where the rules say it, not in the list a step returns (Deadnight #1059) {#rules-events}

`NightServer.step` returns the events of that tick, but a rules event can also be made by an `apply` between steps, by a
bot's buy, or by a test that calls the rules directly, and those land in the outbox the host has already taken. A host
that waits for `round_ended` in the step's list to post a report misses the round that ended outside the step, and the
report never goes. Hook the rules' own signal (`GameRules.event_emitted`, which `NightServer._on_rules_event` already
listens to) and keep what is owed (`XpAward.take_due`); the host asks after each step and posts what is due.

## What the last event of a night makes {#what-the-last-event-of-a-night-makes}

Once the rules say the match is over, `NightServer.step` runs `_step_over` (a frame and the intermission's clock) and
nothing else, so whatever the end made has to be handed out there. A stat that is counted at `game_over` or by the
last down (*Dead on arrival*, *Standing room only*, a night count) finishes challenges in that same event; their events
(`ChallengeAward.take_events()`) wait for the next `apply`, and a client with its player down sends none (Deadnight
1172: the board held the number and no client heard it). `_step_over` drains them. Test a night's end as *told*: wait
for `challenge_done` on a client after `game_over`, not only for the board's number.

## An end the server owns: intermission and return (Deadnight #973) {#server-owned-end}

The end of a match is a state of the server, not of each client, or no two screens agree on the second:

- **Freeze, count, say once.** When the rules say the match is over the server stops stepping the world (bodies,
  enemies, rules) and only counts the intermission, putting the whole seconds left in every frame (`-1` while the match
  is on, so it costs a match in play nothing) and sending one `night_closed` event at 0. A client counts by that number.
- **The client stays through it.** Leaving the seat at the game over (to avoid an unread socket) made the screens
  diverge and left nothing to show; reading the frames costs nothing when the world is still, and a client that is
  sent no commands cannot move. It closes its link at the event or when its player presses Leave. The room waits a
  short grace for the rest and hangs up on them.
- **A frame that says the match is over also covers a late arrival** (a seat taken during the intermission heard no
  `game_over`).
- **The return is the backend's to remember.** The game server tells the backend the match *finished* and which users
  were still present; the backend reopens the same lobby (code, host, settings) for them instead of dropping it. A
  match that ended any other way (everyone left, a crash) still drops it. A client asks for its lobby until it reads
  `open`, because it may ask before the game server's call has landed.
- **Test it over real sockets** with the real backend and a leaver: clocks within a second of each other, the room freed,
  the lobby open again with the host's rules, a host who left replaced, and a night everyone left not reopened.

## A player's way in and out of a room {#player-states}

<!-- new section: the room sections cover the transport and the protocol; none lists the states a player passes
through, the ways in and out, or what is kept for a seat -->

- **Approach:** For any multiplayer flow, list every state a player can be in (alone, with friends, started, late, full,
  host gone, tab closed) from the player's view before building, test each with two or more real clients on the real
  stack, and run a new screen once in the web build against the real backend. **Watch out for:** creating a night was
  create then start, so the waiting room, who is in it and who starts were never designed: no screen showed the members,
  a closed tab never left, and the first lobby screen reused a covered screen's requests, which never answered.
  **Seen:** Deadnight #515, 2026-11-02 (fix: Deadnight #521, #537 and #555: a node's network requests live and die with
  its parent's `process_mode`, so a screen that keeps asking while on top owns its own request nodes under itself).
- **Approach:** Erase state kept by player id in a second place where the rules erase the player, and test a seat given
  up and taken again; walk a "did not arrive" report from every source with both lists side by side, and say which
  source the walk could not reach. **Watch out for:** leaving erased the rules' player but not the combat server's
  loadout, and the room gives the lowest free id to the next person, who carried the last one's weapons while the rules
  said the start weapon only. **Seen:** Deadnight #904, 2026-11-03 (fix: the combat server forgets a player on
  the rules' `player_removed`; `test_weapon_sources.gd` walks every weapon through every carry and a seat given up and
  taken again, and failed first with `pistol, mp5`; a source the walk cannot reach is named in the report).
- **Approach:** For any "you are already in X" refusal, list every way the system puts a player into X and every way out
  from the player's view (button, menu, closed tab, dropped connection, night ended, Activity closed), test each over
  the real stack with bots in, and prefer moving the player to refusing them. **Watch out for:** a finished night's
  reopen put its users back in the one-open-lobby index, an entry they never made, so a player at the menu was refused
  by a lobby they could not see for ten minutes. **Seen:** Deadnight #1177, 2026-11-05 (fix: a failing test for every
  suspect, keeping the ones that fail (bots were innocent); create, join and quick join move a player out of the old
  lobby, an empty or unread reopened one is dropped, both exits of a night say `leave`; [Netcode](../../gamedev/netcode.md#leaving)).

## A feature that crosses services {#across-services}

<!-- new section: the page covers the client and the game server; nothing covered a change that also needs the
backend deployed -->

- **Approach:** Call a feature that crosses services (client, backend, game server) done only when every service it
  crosses is deployed by the pipeline that merges it, with one test per setting through the real stack, read back from
  the running night. **Watch out for:** the backend had no deploy job, so the live one predated the lobby rules,
  answered a rules change with a bare 404 and ignored a start's settings; every test ran a backend built from the
  checkout. **Seen:** Deadnight #944, 2026-11-04 (fix: the deploy compares the live service's settings keys with the
  client's, and an unknown key is refused by name at every border; `deploy-backend` joined the pipeline and one test per
  setting reads the value back from the running night).

## Measuring a network {#measuring}

<!-- new section: the comparison section reports numbers; nothing said how to measure bytes, latency or a field's cost -->

- **Approach:** Compare stacks through a small asyncio TCP proxy between the clients and the headless server: it counts
  bytes (WebSocket framing included), delays each chunk and models TCP loss as a retransmission timeout that stalls
  every later chunk in that direction; take server CPU from `psutil` over the same window. **Watch out for:** each
  stack measured itself differently (our protocol counts its payload, the MultiplayerAPI and netfox expose no byte
  counter, an in-game conditioner wraps only the stack written with one), so the numbers could not sit side by side.
  **Seen:** Deadnight #38, 2026-11-01 (fix: `spikes/net-compare/tools/run_scenario.py`).
- **Approach:** Measure the network with a small external probe (Python `websockets`) that joins as a silent player,
  pings every 50 ms and timestamps every snapshot with `perf_counter`; quote the probe for the network and the clients
  for what the game feels, with a local server as the baseline. **Watch out for:** `WebSocketPeer` is polled on the
  30 Hz physics tick, so every arrival rounds to a tick (34 ms round trips and 100 to 235 ms "stalls" against localhost
  as often as against the hosted server) and a late frame looks like a late packet. **Seen:** Deadnight, 2026-11-01
  (fix: the probe, quoted beside the clients' numbers).
- **Approach:** Measure what a field costs on the real object (the room's own `_welcome_snapshot()` with four seats,
  with and without the key), put the line in the test's log and the numbers in the pull request. **Watch out for:** a
  hand-made three-key snapshot sat on the other side of `NetWire.COMPRESS_FROM` (256 bytes), so the WELCOME read 22
  bytes shorter with a new `levels` table (173 to 151): two sizes either side of a threshold are not the field's cost.
  **Seen:** Deadnight #1077, 2026-11-04 (fix: 1017 to 1052, +35 for the WELCOME, 110 to 154 for the event).

- **Approach:** When a harness starts a Godot server and client from Python, send each one's output to a file and
  read the files after, and count bytes with the 60-line asyncio proxy of `sandbox/template-net/tools/run.py` (copy it,
  keep it throwaway); keep a first cell that reports 0 bytes as a failed run, not a result. **Watch out for:** with
  `stdout=subprocess.PIPE` the same client never connected to a server that a shell-started client reached at once
  (0 bytes, no error; cause not found), and the first matrix of the spike held cells from a script that failed with
  `SCRIPT ERROR` while the process went on running. **Seen:** gdstudio #883, 2026-11-10 (fix: log files, and the
  harness prints any `ERROR` or `WARNING` line of either log).

## Web export {#web-export}

- Single-threaded export (`variant/thread_support=false`) needs no cross-origin isolation headers and works in an
  iframe. The cost is that threads and some audio features are unavailable; networking is unaffected.
- The page address is the web build's command line: read it with `JavaScriptBridge.eval("window.location.search")` and
  parse it like arguments (`?url=wss://host&bot-seed=3`). Behind an `https` page the socket must be `wss://`.
- The release `.wasm` is about 39 MB uncompressed; serve it compressed.

## Headless server image {#headless-server-image}

`debian:bookworm-slim`, download the Linux Godot binary for the pinned version and verify its SHA-512 (the values are in
`tools.toml`), copy the project, run `godot --headless --path /app --import` once **at build time**, then
`godot --headless --path /app -- --server`. The app folder must be owned by the non-root user or the import cannot
write `.godot/`. Read `$PORT` (Railway) and bind plain `ws://`: TLS ends at the platform's edge.
Process 1 is `tini`, which passes the platform's SIGTERM on (Godot as process 1 ignores it and is killed after the
grace period). Deploying and testing it on Railway: [Railway](../../studio/railway.md). The 3D Third Person server
starts with `godot --headless --path game -- --server` ([The game server](third-person/game-server.md#template-server))
and its image, deploy and numbers are the template's `server/` ([The server image](third-person/game-server.md#server-image)).

- **Approach:** Read a procfs file with `get_line()` (it is one line), treat an empty result as no data, and test
  Linux-only paths in the Docker image. **Watch out for:** procfs files report a length of 0 and
  `FileAccess.get_as_text()` reads `get_length()` bytes, so `/proc/self/stat` came back empty and a headless server
  logged `Out of bounds get index '11'` every 5 s; on Windows the path does not exist, so it showed only in the
  container. **Seen:** Deadnight, 2026-11-01 (fix: `get_line()` and an empty check).
- **Approach:** Cap Godot's worker pool in a server image (`threading/worker_pool/max_threads=2` in an `override.cfg`
  the Dockerfile writes) and read the process's processor share beside the step time. **Watch out for:** the pool has
  a thread a core and Jolt hands every physics step to all of them: an idle 3D Third Person server took 24% of a core
  on a 16-core machine (16 workers at 1.1% each) and 30% with 8 bots while its step read 0.6 ms; two threads gave 1.9%
  and 6.7% with the same step times, and Railway's hosts have 48 cores. **Seen:** gdstudio #910, 2026-11-11 (the
  template's `server/Dockerfile`).

## Small things that cost time {#small-things-that-cost-time}

- Check a port before choosing it (`netstat -ano | grep :<port>`): on Windows a second listener can bind a port
  silently and clients reach the wrong one. 9080 is the Godot editor MCP bridge here.
- `var x := array.back()[0]` cannot be inferred; write the type.
- Several Godot jobs at once on one machine starve each other: software-rendered web tabs and headless servers drop to
  a fraction of their frame rate, which looks like a bug. Measure when the machine is quiet.
- A puppet body (a player on another machine, drawn by the same scene as a played one) that must not simulate needs
  its `_physics_process` to return early: `set_physics_process(false)` before the node is ready is undone, because the
  engine turns physics processing on again for a node with a `_physics_process` when it becomes ready. The puppet then
  simulated with an idle command, found no floor (its collision mask was 0) and read as always falling.
- A phase that freezes the server (the end of the night, Deadnight #973) skips every per-tick step, so what a tick
  used to end by itself stays on in the frozen frame: a revive hold is stopped by the downed reviver's own `_act`,
  and the last player down is both the reviver and the game over. End such state once, on the first frozen tick
  (`ReviveChannel.end_all`), and read the frozen frame in the test.

- **Approach:** When one person fails and probes pass, compare what their account holds with the probe's and probe with
  a full account; give a size limit and what fills it one test across both sides, and log why a check drops a message.
  **Watch out for:** the cause was chased in the proxy and the client; the ticket carried finished challenges for a
  player wearing a card, emblem or frame, which put the hello past its 1024-byte limit, the server dropped it unanswered
  (logged `SILENT`), and every probe was a fresh guest. **Seen:** Deadnight #1366, 2026-11-06 (fix: the
  limit and the socket buffer hold the longest ticket the backend signs, and the refusal is logged; see
  [Netcode](../../gamedev/netcode.md#client-input)).
