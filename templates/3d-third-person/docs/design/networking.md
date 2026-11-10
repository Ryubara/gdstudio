# Networking

What the template gives an online game so far: the **link** that carries packets between a client and a server. The
packets themselves (what a command, a snapshot or an event holds) are a layer above, and the server and the client
that play the game are still to come.

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

## Trying it

- `game/tools/net/echo_server.gd` is a bare server that answers every packet; `game/tools/net/relay.py` adds a delay
  each way between a client and it. Their headers say how to run them.
- `game/tools/web_smoke/net_link_smoke.py` opens the web build against the echo server in a headless browser.

The numbers and the engine behaviour the link was built around are in the kit's `docs/engines/godot/multiplayer.md`
(The template's transport).
