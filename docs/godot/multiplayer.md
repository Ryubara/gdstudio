# Multiplayer in Godot (web, server-authoritative)

What we learned building the Deadnight net spike (Godot 4.7.2, Compatibility renderer, web first). Game-specific
numbers and the architecture we chose live in that game's `docs/research/multiplayer.md`; this page is what any
GDStudio game can reuse.

## Why our own protocol: the comparison

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

## The constraint that decides everything

A web client (and a Discord Activity inside an iframe) can only open **WebSockets** (and HTTP). No raw TCP/UDP, no
WebRTC through Discord's proxy. So the shape is: one authoritative server that clients reach over a WebSocket
(`wss://` in production). WebSocket runs over TCP: delivery is reliable and ordered, so packet loss never shows up as
a missing packet, it shows up as a **stall** (head-of-line blocking) followed by a burst. Design for stalls: tolerate
late data, send state (snapshots) rather than events that must each arrive, and never let the sim wait for a client.

## A client that freezes, measured on the live server

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

## Godot's raw WebSocket, without the high-level multiplayer

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

## The pattern that worked (own protocol over that transport)

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

## Godot's high-level multiplayer: what to know before using it

`MultiplayerSynchronizer` / `MultiplayerSpawner` / RPC work over `WebSocketMultiplayerPeer` and are quick to start
with, but, measured in the spike (4 clients, each client-owned input synchronizer at 30 Hz and a server-owned position
synchronizer at 20 Hz): the server **relays** client-owned synchronizer data to every other client, so traffic grows
with the square of the player count (per-client upstream 1.8 KB/s with 2 players, 3.7 with 4, 6.1 with 8) unless you
restrict visibility by hand (`public_visibility = false` and `set_visibility_for`). There is no snapshot
acknowledgement,
no prediction and no interpolation hook; node paths must match between peers; and `WebSocketMultiplayerPeer` ids are
random 31-bit numbers. Fine for a prototype; for a game with a real tick, own the protocol.

## Web export

- Single-threaded export (`variant/thread_support=false`) needs no cross-origin isolation headers and works in an
  iframe. The cost is that threads and some audio features are unavailable; networking is unaffected.
- The page address is the web build's command line: read it with `JavaScriptBridge.eval("window.location.search")` and
  parse it like arguments (`?url=wss://host&bot-seed=3`). Behind an `https` page the socket must be `wss://`.
- The release `.wasm` is about 39 MB uncompressed; serve it compressed.

## Headless server image

`debian:bookworm-slim`, download the Linux Godot binary for the pinned version and verify its SHA-512 (the values are in
`tools.toml`), copy the project, run `godot --headless --path /app --import` once **at build time**, then
`godot --headless --path /app -- --server`. The app folder must be owned by the non-root user or the import cannot
write `.godot/`. Read `$PORT` (Railway) and bind plain `ws://`: TLS ends at the platform's edge.

## Small things that cost time

- Check a port before choosing it (`netstat -ano | grep :<port>`): on Windows a second listener can bind a port
  silently and clients reach the wrong one. 9080 is the Godot editor MCP bridge here.
- `var x := array.back()[0]` cannot be inferred; write the type.
- Several Godot jobs at once on one machine starve each other: software-rendered web tabs and headless servers drop to
  a fraction of their frame rate, which looks like a bug. Measure when the machine is quiet.
