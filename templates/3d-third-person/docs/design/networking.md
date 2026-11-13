# Networking

What the template gives an online game so far: the **link** that carries packets between a client and a server, the
packets above it (`NetWire`, `CommandCodec`, `SnapshotCodec`), the **game server** that admits players and steps
their bodies, the **client** that predicts its body and draws the others, and the **online game** a player starts
from the menu.

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
`command_ticks`, `silent_seconds`, `hello_seconds`, the spawn group and seed, and the body scene; its AI group says
how often each client hears of each AI character by distance (`ai_rates`), where positions are measured from
(`ai_section_origin`), which profiles map to which look (`ai_variants`), and whether the AI sees the players
(`ai_sees_players`). The AI runs here and nowhere else. A player's shot on an AI character is met where that
player's screen drew the character, a few tenths of a second ago (the server keeps each character's body for
`ai_rewind_seconds`, and a round meets the drawn characters for its first `ai_rewind_flight_seconds`): aim at the
guard you see. Only the body a shot meets is wound back, never what the AI thinks or where it goes; another player is
met where the server has them.

## The client

A `NetClient` node (`game/gameplay/net/net_client.gd`) joins a server and plays the local `Player` at once: each
physics step it samples the player's controller, sends the command and steps the body with exactly the numbers the
server will read, so the body moves the moment the key goes down. When a TICK says where the server's body stands after
a command, a `Reconciler` slides the local body toward it a quarter of the way a frame (and puts it there at once when
it is more than 2.5 m off, or when a quarter would put the body inside a ledge, `BodyOverlap`); a `StallGuard` notices
the game froze (a hidden tab) and skips the burst of catch-up steps, and a `SilenceWalk` steps the body as the server
stepped its own meanwhile (it walks on a moment, then stands), so both come out of the freeze at the same speed.
The other players are drawn by `RemotePlayers` (`remote_players.gd`): one puppet `Player` a slot, the same
`player.tscn` with no input, collision or simulation, a tenth of a second behind the newest TICK and smoothly between
the two TICKs around that moment, so they walk, run, crouch, aim, jump and land with the same clips as the local body.
A vault or a mantle is planned again on this screen when a puppet's state turns to one (`PuppetVault`, also used by
the AI's puppets), so its clip plays as on the body that steps it with nothing more sent, and its planted hand rests
on the obstacle's top on every screen (`tests/gameplay/test_net_puppet_vault.gd`). A puppet's starts and stops are
picked from where its TICKs head and the entry's `halt` flag (the player asked for no move), so it plays the stop the
stepping body plays instead of sliding in one (`tests/gameplay/test_net_puppet_gait.gd`). Nothing that only looks
(a footstep, a hand pose, a muzzle flash) crosses the network.

The AI characters run on the server only. When the client joins, its own map's AI (the director and every AI
character, with their senses, brain, tasks and navigator) stands down before it runs a frame, and an `AiReplica`
(`ai_replica.gd`) draws the server's characters from the few bytes each TICK carries for this client: each one a
dressed character with no AI and no collision, walked evenly from one row to the next a tenth of a second behind, its
animation from the row (walking, running, crouching, aiming), its death a ragdoll this screen makes itself from one
event, its shot a muzzle flash this screen plays. A crowd that arrives at once (the join, a crowd walking into range)
is made and shown a few characters a frame, the nearest first, so joining does not freeze the screen. Characters
farther away are sent less often (`ai_tier_rates.tres`
on the server), and none past the interest radius. A browser among the players caps how many characters run for
everyone.

Inspector: `NetClient` `player`, `remote_players`, `ai_replica`, `world_root`, `join_on_ready`, `player_name`,
`spawn_group`, `spawn_seed`, `rejoins`; `RemotePlayers` `puppet_scene`, `delay`; `AiReplica` `interp_delay`,
`extrapolate_seconds`, `glide_max_jump`, `extrapolate_mask`, `section_origin`, `variant_scenes`, `puppets_per_frame`,
`puppet_budget_usec`, `puppets_shown_per_frame`, `viewer`.

## Playing online

`game/online_main.tscn` is the online game: the offline game (`main.tscn`, unchanged) with a `NetClient`, the
`RemotePlayers`, the `AiReplica` and an `OnlineStatus` overlay (`game/ui/online/`). Three ways in:

- The main menu's **Play online** loads it and joins the address under the button. That field is a developer's: it
  shows in a debug build (the editor, a debug export) and never in a release, where the menu's `server_address` is the
  only address (set it to your deployed server, `wss://...`). `address_field` on `MainMenu` forces it on or off.
- `godot --path game -- --connect ws://host:8910 [--name Ada]`: the project's first scene sees the address and goes
  straight to the online game. Back to the menu from it shows the menu.
- On the web, the page's address: `index.html?url=wss://host&name=Ada`. A page served over `https` can only open
  `wss://`.

The overlay says **Connecting** until the server seats the player, then hides. It says the server runs another version
(reload the page, or update the game), that the game is full, that the server runs another map, that nobody answered
within `connect_seconds`, or **Connection lost**, each with **Back to menu**; while it shows, the player's input is off.
Its texts are exports of `online_status.tscn`. A server that hangs up on a hello that came too late (a browser
compiling the game's shaders on its first visit holds its page for seconds) gets a new socket, up to `rejoins` times,
while the overlay still says Connecting.

`--bot route` or `--bot watch` (`?bot=route` on the web) hands the player to a `PlayerBot`, which presses the same
actions a person would and turns the camera as the mouse does: `route` walks to the main door, opens it, comes back,
fires past the other player and stands; `watch` keeps the nearest other player in view and, after `fire_after`
seconds, shoots at it. Two clients and a server, one bot each, are the online game's capture.

```text
godot --headless --path game -- --server --port 8910
godot --path game -- --connect ws://127.0.0.1:8910 --bot watch --name Two
godot --path game -- --connect ws://127.0.0.1:8910 --bot route --name One
```

`--onlineprobe` (`?onlineprobe` on the web) prints what the client measured once a second (`ONLINE_PROBE {...}`: round
trip, corrections, the gap to the server's point, players, frame time) or writes it to `window.gdonline`.

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
- `game/tools/web_smoke/online.py` opens two pages of the web build against a server through a 100 ms relay, each with
  a bot, and checks that both are seated and see each other; with `--other-version` the server is of the next
  protocol version and every page must say so.
- `game/tools/web_smoke/step_trace.py` steps a body through the map with scripted commands in the web build and on
  the desktop (`?steptrace`, `-- --play --steptrace`) and compares the positions: they are the same floats, so a
  browser predicts exactly what a server steps.

The numbers and the engine behaviour the link was built around are in the kit's `docs/engines/godot/multiplayer.md`
(The template's transport).
