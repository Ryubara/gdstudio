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

3D Third Person runs the same proof as a gate with thresholds, native and in the browser, in CI
([the bad-network gate](third-person/online-client.md#bad-network-gate)).

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

**One socket buffer size: `NetLimits.BUFFER_SIZE` (1 MB since #970, 256 KB before).** `WebSocketLink.inbound_buffer` and
`WsListener.outbound_buffer` both start from it and neither file has a constant of its own; `test_net_limits.gd` pins
the value and that both read it. It was 1 MB in the transport and 256 KB in the packets' limits until #934 measured it
in the browser (`net_link_smoke.py --inbound <bytes>`, a 5 s frozen tab at 35 KB/s, so 175 KB wait): 256 KB lost
nothing in six runs (0 `Buffer payload full` errors, every packet in order), 1 MB the same in two, and the 64 KB
control lost packets in 7 of 9 pages (4 to 86 errors; two pages lost none, so the smoke tries the control up to three
times). A size above that bought nothing in a freeze that short until the AI rode the TICK (#970): ten seconds of the
longest TICK without AI and five of a full AI snapshot of the desktop population (120 characters) every TICK need
666 KB, so the size is 1 MB (16 MB of outbound buffers on a full server); a TICK the socket still refuses makes the
next AI block full, so a longer freeze costs a resend, never a wrong picture.

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
| HELLO with an 8-character name | 16 (8 + name; the world hash and the client's flags travel in it) | 3 + name |
| WELCOME, 1 player, no world parts | 30 | about 40 |
| WELCOME, longest (8 players with 16-byte names, 128 parts of 12 bytes) | 2295 | |
| REFUSED | 3 | 3 |
| COMMAND / with a shot block | 15 / 27 | 15 / 27 |
| TICK, 8 players, no events, no moving prop, no AI | 109 (the AI block's mode is 1 byte) | 107 |
| TICK, longest (32 events of 20 bytes, 8 players, 8 moving props) | 868 | |
| A moving prop in a TICK (streamed row, `PropState`) | 14 | |
| An AI character in a TICK: a row, a move (`AiSnapshot`) | 14, 7 | 13 (Deadnight) |
| AI block: full of 40 / 120 characters; a delta of 120 walking, every one near | 564 / 1684; 262 a TICK on average | 561 a tick at 120 |
| PING / PONG | 7 / 11 | 7 / 11 |
| Events: joined (4-letter name), left, shot, hit, died, revived, entity (3 bytes), pickup, rejected, AI | 7, 2, 15, 15, 9, 8, 11, 4, 6, 14 | shot about 17, hit about 12 |

What the command's fields mean, fixed by gdstudio #901: `move` is the push in the view's axes (`x` right, `y`
forward, no longer than 1), `yaw` the view's heading (0 looks along -Z, so the body's `facing` is `yaw + PI`), `pitch`
positive up; `crouch` is already the toggle's result; a press is true in one command. The shot block (`has_shot`) rides
only on a tick where a shot can leave (a press buffered or just made, or an automatic weapon held, and the weapon
ready), so fire held for three seconds measured 1302 B/s up for the pistol and 1346 B/s for an automatic one at four
shots a second (a command a tick and two pings, each with a 6-byte frame; 1286 with no block, 2006 if the block rode on
every held tick, against a budget of 2000). Flag bits 11 to 14 are the weapon presses (reload, next, previous,
the empty hands; gdstudio #887) and bit 15 is prone (#1012); no flag bit is free. `NetWire.VERSION` 4 (#906): a shot
carries the weapon and the low 16 bits of its `seq`, a hit the health it left
([shots online](third-person/online-shots.md#template-shots)). `NetWire.VERSION` 5 (#1073): a TICK ends with a count
and the rows of the moving props, and a world part's state may be 12 bytes
([pushed props online](third-person/net-world.md#props)). `NetWire.VERSION` 6 (#970): a TICK ends with the AI block
for its client (`AiSnapshot`: none, full or a delta of rows, moves and the ids that left), a HELLO carries a flags
byte (`F_WEB`: the client is a browser), an `AI` event (id, what happened, a point, a direction) and a HIT names an AI
as `NetHits.AI_BASE + id` ([the AI online](third-person/ai.md#replication)). The socket buffers are 1 MB since: five
seconds of a full AI snapshot of 120 characters every TICK is 252 KB.

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

Moved to [A room over a real socket, faster than real time (Deadnight #230)](multiplayer-server/rooms.md#room-over-socket).

## The two worlds must hold the same solid things {#the-two-worlds-must-hold-the-same-solid-things}

Moved to [The two worlds must hold the same solid things](multiplayer-server/rooms.md#the-two-worlds-must-hold-the-same-solid-things).

## Every client sees the same bodies {#appearance}

Moved to [Every client sees the same bodies](multiplayer-server/rooms.md#appearance).

## Events reach a client only through its command loop {#events-reach-a-client-only-through-its-command-loop}

Moved to [Events reach a client only through its command loop](multiplayer-server/rooms.md#events-reach-a-client-only-through-its-command-loop).

## A room test that needs a map or a fast round {#a-room-test-that-needs-a-map-or-a-fast-round}

Moved to [A room test that needs a map or a fast round](multiplayer-server/rooms.md#a-room-test-that-needs-a-map-or-a-fast-round).

## Act on a rules event where the rules say it, not in the list a step returns (Deadnight #1059) {#rules-events}

Moved to [Act on a rules event where the rules say it, not in the list a step returns (Deadnight #1059)](multiplayer-server/rooms.md#rules-events).

## What the last event of a night makes {#what-the-last-event-of-a-night-makes}

Moved to [What the last event of a night makes](multiplayer-server/rooms.md#what-the-last-event-of-a-night-makes).

## An end the server owns: intermission and return (Deadnight #973) {#server-owned-end}

Moved to [An end the server owns: intermission and return (Deadnight #973)](multiplayer-server/rooms.md#server-owned-end).

## A player's way in and out of a room {#player-states}

Moved to [A player's way in and out of a room](multiplayer-server/rooms.md#player-states).

## A feature that crosses services {#across-services}

Moved to [A feature that crosses services](multiplayer-server/rooms.md#across-services).

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
- **Approach:** When a harness counts bytes over a window and also reads a client's own report line, wait for the
  client's run to end (`wait` with a timeout) before stopping it, and fail a row whose report is missing. **Watch out
  for:** `tools/net/bandwidth.py` stopped the predicting client at the end of its window, before its `PREDICT_BOT` line,
  so the client's AI costs read `None` in every row of the first run. **Seen:** gdstudio #970, 2026-11-11 (fix: the
  client is waited for, up to 30 s).

## Web export {#web-export}

- Single-threaded export (`variant/thread_support=false`) needs no cross-origin isolation headers and works in an
  iframe. The cost is that threads and some audio features are unavailable; networking is unaffected.
- The page address is the web build's command line: read it with `JavaScriptBridge.eval("window.location.search")` and
  parse it like arguments (`?url=wss://host&bot-seed=3`). Behind an `https` page the socket must be `wss://`.
- The release `.wasm` is about 39 MB uncompressed; serve it compressed.
- The character's step under Jolt gives the same floats in the web build (wasm), on Windows and on Linux: 1800 steps
  of a scripted walk through 3D Third Person's map matched to nine decimals at every point (gdstudio #909,
  [Playing online](third-person/online-client.md#play-online)), so a browser client may predict with the server's own
  step; what it corrects is its page's hitches.

## Headless server image {#headless-server-image}

Moved to [Headless server image](multiplayer-server/server-image.md#headless-server-image).

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
