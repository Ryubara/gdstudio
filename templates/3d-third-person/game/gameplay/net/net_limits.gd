class_name NetLimits
extends RefCounted
## The numbers an online game of this template is built around, in one place: every other file of
## `gameplay/net/` reads them from here, and `test_net_limits.gd` pins each copy (the physics tick
## rate of `project.godot`, the byte widths that must hold them) so a change here cannot leave an
## old number behind (docs: gamedev/netcode.md#limits).

## Players in one game. A slot is a byte (0 to MAX_PLAYERS - 1).
const MAX_PLAYERS := 8
## The longest name, in UTF-8 bytes (a HELLO and a `joined` event carry it).
const NAME_BYTES := 16
## A position is centimetres in a signed 16-bit number: this far from the origin either way, metres.
const POSITION_RANGE := 327.67
## Centimetres a metre (the step of a position on the wire).
const POSITION_STEPS_PER_METRE := 100.0
## The server steps every body this many times a second (`physics_ticks_per_second`); a client
## sends one command a step.
const TICK_RATE := 60
## The server sends a TICK this many times a second (every second step).
const SNAPSHOT_RATE := 30
## Pings a client sends a second.
const PING_RATE := 2
## Events one TICK may carry; more wait for the next.
const MAX_EVENTS := 32
## Networked world parts (doors, platforms, pickups, targets, props) one map may have.
const MAX_ENTITIES := 128
## The longest state one world part writes (an `entity` event, a WELCOME row, a TICK's streamed
## row), bytes: a pushed prop's is 11 (`PropState`).
const MAX_ENTITY_STATE := 12
## Streamed parts (moving props) one TICK carries; more take turns, each in every other TICK or so.
## 8 keeps ten seconds of the longest TICKs inside `BUFFER_SIZE`.
const MAX_STREAMED_PARTS := 8
## Bytes a socket buffers each way, the one size the transport reads (`WebSocketLink` inbound,
## `WsListener` outbound): 256 KB holds a 5 s frozen tab of a 35 KB/s stream (175 KB) and ten
## seconds of the longest TICKs at the snapshot rate; the engine's 64 KB lost packets there.
const BUFFER_SIZE := 1 << 18
## Seconds of a stall the per-connection command budget takes in one burst (`PeerLimits`).
const STALL_SECONDS := 4
