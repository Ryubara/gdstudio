# Networking

What the template gives an online game so far: the **link** that carries packets between a client and a server, the
packets above it (`NetWire`, `CommandCodec`, `SnapshotCodec`), and the **game server** that admits players and steps
their bodies. The client that predicts its body and draws the others is still to come.

## The link

`game/gameplay/net/` holds it. Every link carries `PackedByteArray`s in order and never reads them:

- `WebSocketLink` is the client, the same on desktop and in the web build. `connect_to_url("ws://host:8910")`, then
  `poll()` once per physics tick; `packet_received`, `connected` and `closed` say what happened. Where to connect
  comes from `WebSocketLink.server_url()`: `-- --connect ws://host:8910` on the command line, or `?url=wss://host` in
  the web page's address. A page served over `https` can only reach a `wss://` server.
- `WsListener` is the server's side (desktop and headless; a web build cannot listen): `listen(port)`, `poll()` once
  per physics tick, `send(peer_id, bytes)`, which says false when that client stopped reading and its buffer is full.
- `LoopbackLink.pair()` gives two ends in one process, for tests and for a server run inside the game.
- `LinkConditioner.new(link, 0.1)` puts a bad network around any link: a delay each way, jitter and stalls, on your
  own clock and with a seed, so a run repeats.

A WebSocket is TCP: nothing is lost or reordered, so a bad network shows as a stall followed by a burst. Send state
that a later packet can repair, not changes that must each arrive.

## The command

What a client will send each physics tick is a `PlayerCommand` (`game/gameplay/player/player_command.gd`), and it is
already what moves the character offline: `Player.step(command, delta)` is the only thing that moves a body, and the
body reads no key and no camera. A server steps the same body with the commands it receives
(`set_physics_process(false)`, then `step`), with `ragdoll_by_command` off and its own answer to `fell`.
`CommandCodec` writes a command in 15 bytes, 27 with the crosshair's ray, which rides only on a tick where a shot can
leave. The fields are in [the character page](character.md#commands).

## The server

`godot --headless --path game -- --server --port 8910` starts it: the main scene sees `--server` and opens
`game/gameplay/net/net_server.tscn` (the map and a `NetServer`) instead of the menu. Each player who says hello gets
the lowest free slot and a body (`character.tscn`, the body alone) at the slot's spawn point, and every client gets a
TICK of all players thirty times a second. The server applies each client's commands once and in order; a command a
step late is waited for (up to four steps) rather than guessed at, a client that goes quiet keeps walking for half a
second, then stands, and after 15 s it is hung up on. A client of another version or
map, or one over `max_players`, is refused; one that floods or sends what no client sends is hung up on. It prints one
JSON line for each player who comes or goes and every 10 s its numbers (players, bytes out a second, the step's time).

Its numbers are on the `NetServer` node in the inspector (`net_server.tscn`): `max_players`, `hold_ticks`,
`command_ticks`, `silent_seconds`, `hello_seconds`, the spawn group and seed, and the body scene.

## The client

A `NetClient` node (`game/gameplay/net/net_client.gd`) joins a server and plays the local `Player` at once: each
physics step it samples the player's controller, sends the command and steps the body with exactly the numbers the
server will read, so the body moves the moment the key goes down. When a TICK says where the server's body stands after
a command, a `Reconciler` slides the local body toward it a quarter of the way a frame (and puts it there at once when
it is more than 2.5 m off); a `StallGuard` notices the game froze (a hidden tab) and skips the burst of catch-up steps.
The other players are drawn by `RemotePlayers` (`remote_players.gd`): one puppet `Player` a slot, the same
`player.tscn` with no input, collision or simulation, a tenth of a second behind the newest TICK and smoothly between
the two TICKs around that moment, so they walk, run, crouch, aim, jump and land with the same clips as the local body.
Nothing that only looks (a footstep, a hand pose, a muzzle flash) crosses the network.

The offline game (`main.tscn`) has no client yet: the online entry of the menu adds one. Until then
`game/tests/fixtures/online_arena.tscn` holds a map, a `PlayerRig`, `RemotePlayers` and a `NetClient`. Inspector:
`NetClient` `player`, `remote_players`, `world_root`, `join_on_ready`, `player_name`, `spawn_group`, `spawn_seed`;
`RemotePlayers` `puppet_scene`, `delay`.

## The server image

`server/` (beside `game/`) runs the server in a container and deploys it:

- `server/stage.sh <folder>` makes the build context: the `Dockerfile`, `railway.toml` and `game/` without the tests,
  the tools and the import cache. `docker build -t game-server <folder>`, then
  `docker run --rm -e PORT=8910 -p 8910:8910 game-server`.
- The image is debian-slim with the Godot version the kit pins, imports the project at build time, and runs
  `godot --headless --path /app -- --server` as the user `game` under `tini`, on `$PORT`. It speaks plain `ws://`:
  the platform in front of it (Railway) ends TLS, so players connect with `wss://`.
- `server/deploy.sh <service>` uploads it to a Railway service and waits until it is live. Run it from a folder linked
  to the Railway project (`railway link`), never from the game's checkout. Deploy the web build and the server from one
  commit: a client of another protocol version is refused at its hello.
- `server/check.sh <url> [bots] [seconds]` plays bots against a server (`ws://127.0.0.1:8910` for the image,
  `wss://<service>.up.railway.app` for a deployment) and fails when one is not welcomed or loses its connection, then
  checks that a client of an older version is refused.

On Linux the server's `stats` line also carries its memory (`rss_mb`, `anon_mb`) and its share of a core
(`cpu_pct`). What it costs, measured, is in the kit's `docs/engines/godot/third-person/game-server.md` (The server
image).

## Trying it

- `game/tools/net/echo_server.gd` is a bare server that answers every packet; `game/tools/net/relay.py` adds a delay
  each way between a client and it. Their headers say how to run them.
- `game/tools/net/server_bot.gd` plays bots against a server you started (with `--moves` they slide, vault, mantle and
  switch and reload their weapons on the map), and `game/tools/bench/server_bench.tscn` times the server's step with
  one to eight of them; their headers say how to run them.
- `game/tools/net/predict_bot.gd` is a predicting client against a server you started, with an optional delay and
  freezes of its own thread; it prints how much it had to correct and what it costs a step.
- `game/tools/capture/online_tour.tscn` records two clients side by side (Ada's own screen and Bo's, where she is a
  puppet).
- `game/tools/web_smoke/net_link_smoke.py` opens the web build against the echo server in a headless browser.

The numbers and the engine behaviour the link was built around are in the kit's `docs/engines/godot/multiplayer.md`
(The template's transport).
