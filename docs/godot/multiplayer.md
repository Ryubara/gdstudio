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

### The same in the browser (Deadnight #502)

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
the server running, and the next run cannot open its log ([lesson](../lessons/2026-11-02-a-probe-left-its-game-server-running-after-it-was-killed.md)).

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

## A room over a real socket, faster than real time (Deadnight #230)

A soak of a game server's room with real clients (ten game minutes, two people and two bots) runs in about three
minutes of wall time on one headless Godot process: `--fixed-fps 60` makes each frame exactly one physics tick and
removes the pacing (no vsync headless), so the server, the clients and the bots step as fast as the machine allows. Two
things have to run on game time, or the run fails for a reason that is not the code: the server's connection rules (a
peer may send 90 commands a second: at fixed-fps the wall clock sees several hundred and kicks it), which take a
`clock` Callable (`NightHost.clock`, `Engine.get_physics_frames() / 60.0`), and the client link's own clock
(`WebSocketLink.clock`). Everything else already counts frames. The numbers: 36,000 ticks, server step 1.5 ms mean for
two autopilot clients and two bots, no engine error in the verbose log. The soak is
`tests/captures/bots_slots_soak.tscn` in Deadnight, a CI job of its own because it is too long for a test shard.

## The two worlds must hold the same solid things

A predicting client moves its body against its own copy of the map, the server moves the real one against the server's.
A solid thing that only one holds is a wall the other walks through, and the client's body then drifts metres from the
server's (Deadnight #748: a prize crane's cabinet, a `StaticBody3D` that the client-only drawing added to itself). Views
and drawings carry no collision; a solid thing is built into the world both sides build and moved there by the rules
(server) and the frame (client). The same goes for the bodies: the client draws the other players as puppets with no
collision, so the server's bodies must not block one another either (Deadnight #760: a body on layer 1 with a mask of 1
and 2 stopped at a teammate for good; players now sit on a layer of their own). Test it with a real client and host:
list every `CollisionObject3D` and colliding `CSGShape3D` under each side's viewport and compare them
(`tests/net/test_world_parity.gd`).

## Events reach a client only through its command loop

A test client that is driven by hand must still send its command every tick (`night.ticked` connected to
`link.send(command.to_dict())`): the server answers a command with the tick's events, and without one the client is
sent only the spawn requests. Fire with the same command a player's input makes (`NightCommand.aim_along`, `fire`),
never with `server._combat(...)` beside the step: the server refuses a shot whose view disagrees.

## An end the server owns: intermission and return (Deadnight #973)

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
- A puppet body (a player on another machine, drawn by the same scene as a played one) that must not simulate needs
  its `_physics_process` to return early: `set_physics_process(false)` before the node is ready is undone, because the
  engine turns physics processing on again for a node with a `_physics_process` when it becomes ready. The puppet then
  simulated with an idle command, found no floor (its collision mask was 0) and read as always falling.
- A phase that freezes the server (the end of the night, Deadnight #973) skips every per-tick step, so what a tick
  used to end by itself stays on in the frozen frame: a revive hold is stopped by the downed reviver's own `_act`,
  and the last player down is both the reviver and the game over. End such state once, on the first frozen tick
  (`ReviveChannel.end_all`), and read the frozen frame in the test.
