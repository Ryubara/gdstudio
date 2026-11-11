# Networked map parts

<!-- new section: the game-server and online-client pages hold the players; nothing held how the map's doors,
     platforms and pickups are owned by the server and shown by a predicting client (gdstudio #907) -->

How the 3D Third Person map's doors, moving platforms, pickups, pushed props and targets work in an online game: the
server owns them, a predicting client meets the same panel, rides the same slab and pushes against the server's crate,
and a late joiner sees them as they are. Part of
[the 3D Third Person template](../third-person-template.md); the players are [the game server](game-server.md) and
[the online client](online-client.md), the packets [the template's packets](../multiplayer.md#template-packets).

## What it does {#net-world}

<!-- new section: what the parts send, how both worlds hold the same moving solid things, and what it costs -->

`NetEntity` (`gameplay/net/net_entity.tscn`) is a child of `door.tscn`, `moving_platform.tscn` and `pickup.tscn`, in
the group `net_part` with its `net_kind` (`door`, `platform`, `pickup`), so every such part of a map is in the world
hash and a client of another map is `REFUSED(world)`. `NetWorld` (`net_world.gd`) numbers the parts by their path from
the map node (`world_root`, the same root the hash uses since #1066): the id is the rank, the same on every peer of a
build. Offline a part does what it always did.

- **The server owns every part.** `NetServer` makes a `NetWorld` in the role `SERVER`: the part runs its rules (a
  door's interact, `auto_open_range`, `close_after`; a platform's ride; a pickup's touch) and says each change. A
  change becomes an `entity` event (id, the server tick, the new state) to every client; a pickup taken by a player's
  body becomes a `pickup` event (id, slot). The client's `NetWorld` is `CLIENT`: its parts run no rule (`open()` and a
  touch do nothing) and show the server's records.
- **A panel and a slab are a function of the tick.** `Door.openness_at(tick)` and `MovingPlatform.position_at(tick)`
  (a ping-pong with waits in closed form, `ride_at`) replace the per-frame sums; a change starts a new motion at a tick
  and keeps the one before for earlier ticks. Offline the part counts its own ticks.
- **Both worlds put them at the command's tick.** The client numbers its commands by the server tick each is expected
  to be stepped at (`NetClient.first_seq`: the WELCOME's tick and the round trip; renumbered forward after a stall
  by the smallest recent round trip, `numbering_rtt_ms`). Before it predicts command `seq` it puts every moving part
  at tick `seq`; the server, before it steps a body with command `seq`, puts them at the same tick
  (`NetServer.command_tick`, held within 4 s behind and 1 s ahead of its step), and at its own tick after the bodies.
  The two bodies meet the same panel and stand on the same slab.
- **Online the parts are static bodies.** `net_set_role` turns the panel's and the slab's `AnimatableBody3D` into a
  static body, moved with `force_update_transform()`, which the physics queries of the same frame see; a rider is
  carried by `PlatformRider` (`Character._move`: what the slab moved between the tick of the body's last step and this
  one), the same on both sides. Offline they stay kinematic and the engine carries the rider.
- **A change starts later than it is decided** (`NetServer.entity_lead_ticks`, 12 steps): a client hears of a closing
  door before its predicted commands reach the tick it starts at. 12 covers a round trip of about 200 ms.
- **Pickups.** Only the server's copy senses a body; the first server body to touch it takes it (the item goes to that
  body, `collected` fires on the server). Every client hides it and plays its sound when the `pickup` event comes; the
  client whose slot took it gives its own player the item (`collected`, `item_collected`, the HUD). A part stays in the
  map when taken (its id is its place); its return is an `entity` event.
- **Late joiners.** The WELCOME carries the table: each part's state written as at the WELCOME's tick, so a door that
  opened before is open on the first frame, not closed and then opening.
- **The pressure pad.** `trigger_zone_net.tscn` (`TriggerZoneNet`, a `NetEntity` of kind `pad`) sits under the map's
  `Triggers/PressurePad` instance, not in `trigger_zone.tscn`: a camera zone's `TriggerZone` follows one screen's own
  player and stays local. The server's copy senses the bodies, opens the door through its `activated` signal and says
  each press and release; a client's copy has `TriggerZone.sensing` off (no monitoring, no signal) and paints its
  plate from the state (`show_active`), so player two sees the pad pressed by player one's puppet, a round trip late
  for the player on it. Not solid, so no lead: the state is said at the server's tick.
- **Puppets on a slab.** A client draws the slab at its predicted tick and a puppet 100 ms behind the newest TICK;
  `RemotePlayers` moves a puppet that stands on a slab by what the slab moves between the two moments, so player two
  sees the rider standing still on the slab it draws.

State bytes (at most `NetLimits.MAX_ENTITY_STATE`, 8): a door 4 (flags opening and locked, u16 the openness the motion
starts from, u8 the ticks to its start), a platform 6 (flags running and direction, u16 the distance, u16 the ticks it
still waits, u8 the ticks to its start), a pickup 1 (available), a pad 1 (pressed). The server rounds a new motion's
start as the wire carries it, so both sides compute the same function; a WELCOME row is rebased to its tick (0.06 mm
off at most).

Measured (Windows, Godot 4.7.2, one process with the server and its clients over a real socket on 127.0.0.1;
`test_net_map_parts.gd`, `test_net_platform_ride.gd`, `test_net_door_prediction.gd`, `test_net_server_cost.gd`, `test_net_pressure_pad.gd`):

| What | Number |
| --- | --- |
| Parts in the prototype map (doors, platforms, pickups, the pad, the pathing section's) | 18, 6 of them moving |
| WELCOME with the table, no player | 129 bytes (15 without it) |
| `entity` event of a door / `pickup` event | 12 / 4 bytes |
| Putting the 6 moving parts at a tick | 17 µs (once a step on a client; 8 players: 9 times a server step) |
| Server step, 8 bots in the map, p50 / p95 | 0.78 / 1.23 ms |
| A rider over two whole ping-pongs (840 ticks), localhost and 100 ms each way | 0 corrections, worst error 3.3 mm (the TICK's centimetres) |
| The rider's puppet on player two's slab, worst off its place over 8 m of ride | 3.4 mm (17 cm without the slab's shift) |
| Walking into a closing door, 200 ticks, 50 ms each way, lead 12 | 0 corrections, worst 6.6 mm |
| The same, 250 ms each way: lead 0 / lead 36 | 29 corrections, 15.6 cm / 0 corrections, 3.3 mm |

- **Approach:** Move a solid thing that both worlds hold by a pure function of a tick, and put it at the command's tick
  on both sides before the body steps that command; number the commands by the server tick they are expected at.
  **Watch out for:** the parity test matched moving bodies by path only, and the client's platform ran on its own
  clock, so a predicted body on it stood on a slab the server's was not on; the server's tick is not the client's
  command number either, since a command reaches the server half a round trip later. **Seen:** gdstudio #907,
  2026-11-11 (`test_net_platform_ride.gd`: 0 corrections over 840 ticks).
- **Approach:** Online, make a moved solid thing a static body and move it with `force_update_transform()` when a
  body of the same frame must meet it at once; carry its riders yourself. **Watch out for:** in Godot 4.7.2 with Jolt a
  kinematic body (`AnimatableBody3D`) set by its transform is moved only in the next physics step, and even a static
  body's new transform is not seen by `move_and_collide` until the transform notifications are flushed: a spike
  teleported each kind in a frame and only the static ones with `force_update_transform()` blocked a test move at once.
  **Seen:** gdstudio #907, 2026-11-11.
- **Approach:** Start a change the server decides a lead after it, longer than the round trip of the slowest client
  you support, and prove it with a control at a longer round trip with no lead. **Watch out for:** at 100 ms the door
  test passed with no lead at all (the panel met the body 16 ticks after it started, the client knew after 6), so a
  test at one round trip proves nothing about the lead; at 500 ms lead 0 gave 29 corrections. **Seen:** gdstudio #907,
  2026-11-11 (`test_net_door_prediction.gd`).

## A network-ready component {#network-ready-component}

<!-- new section: issue #907 asked for the checklist a map component meets before it plays online -->

A map component plays online when it answers each line; the three of #907, the pressure pad (#1074), and
the props and targets of #1073 ([below](#props)) do.

1. **State:** what a late joiner needs, in at most `NetLimits.MAX_ENTITY_STATE` bytes (12), written as at a tick
   (`net_write`) and read back (`net_read`).
2. **Owner:** the server runs the rules; a client's copy runs none and senses nothing (`net_set_role`).
3. **Solid and moving:** a pure function of the tick (`net_place`), static online, riders carried by the same function;
   a solid thing the server simulates (a prop) is streamed instead (`NetEntity.streams`) and put at the predicted tick
   from its records.
4. **Changes:** start `entity_lead_ticks` after they are decided when a body can meet them; said with
   `NetEntity.report()`.
5. **Once only:** who did it (a pickup's taker) comes from the server's word (`report_taken`, a `pickup` event), never
   from a client's touch.
6. **Cosmetic:** spin, bob, sound and signals that only draw stay local.
7. **In the scene:** `net_entity.tscn` as a child with its `net_kind`, so the world hash and the ids see it, and the
   component hands it its functions in `_ready` (`NetEntity.serve`: no part finds another by a method name). A
   component whose script is the synced `addons/gds_game/` (which knows no `NetEntity`) gets a template subclass of
   `NetEntity` that serves for it through the addon's public methods (`TriggerZoneNet`).
8. **Drawn with a hit:** a change that a shot causes (a target falling) sets `NetEntity.with_puppets`, so a client
   plays it when the puppets are drawn at its tick, with the hit, not a round trip early.

## Pushed props online {#props}

<!-- new section: net-world covered the parts that are a function of the tick; nothing held how a part the server
     simulates with physics is sent, shown and pushed against by a predicting client (gdstudio #1073) -->

A `PhysicsProp` (`physics_prop.tscn`, its `NetEntity` of kind `prop`) is a rigid body that only the server simulates:
the server's bodies push it (`CharacterPush` on the server's body), shots and falls move it, and below `fall_limit` it
goes back to its start on the server. Nothing about it is a function of the tick, so it is **streamed**:

- **The record** (`PropState`, 11 bytes): the position in centimetres, the rotation as the smallest three of its
  quaternion in 32 bits (0.18 degrees at most), and two flags, asleep and jumped (a return to the start, so a client
  does not slide it across the map). The WELCOME's table carries every prop's record (a late joiner sees each where it
  is on the first frame); a TICK carries the record of every awake prop (`NetWorld.stream_rows`: u16 id, u8 length, the
  state, 14 bytes a prop) and one more as it falls asleep, at most `NetLimits.MAX_STREAMED_PARTS` (8) a TICK, the
  others taking turns. A prop at rest costs no byte. A client whose TICK the socket refused is sent every prop's record
  over the next TICKs (`PeerSlot.stream_all`), since the asleep record may have been in the lost one.
- **The client's copy** is frozen as a static body (`freeze_mode` static), so its own predicted body collides with it
  and never moves it (`CharacterPush` skips a frozen prop, but still caps the body's speed at a slow prop's
  `push_speed`, as the server's does). `NetWorld.place` puts it, with the doors, at the tick of the command the client
  predicts (`PropTrack`): blended between records, moved on past the newest at the speed of the last two for at most
  250 ms, held at an asleep record. That tick is about a round trip ahead of the newest record, so the predicted body
  meets the crate about where the server's body does; a body pushing still differs from the server's by what the guess
  misses (when the crate starts, stops or turns), and the `Reconciler` corrects it (counted).
- **On player two's screen** the crate is at the same predicted tick, so it is where the server has it now, not where
  the pusher's puppet (drawn 100 ms in the past) is: a puppet pushing a fast crate shows a gap of the crate's speed times
  the puppet's delay and the round trip.

Measured (Windows, Godot 4.7.2, one process with the server and two clients over a real socket on 127.0.0.1, physics
stepped by `--fixed-fps 60`; `test_net_props.gd`, `test_net_prop_wire.gd`; 2.5 s of pushing north, then 2.5 s at rest):

| What | 5 kg crate (no `push_speed`) | 60 kg cube (`push_speed` 1.2) |
| --- | --- | --- |
| Moved on the server | 8.4 m | 2.2 m |
| The pusher's corrections and worst error, localhost | 11 to 48, 3 to 10 cm | 47, 4.4 cm |
| The same, 100 ms each way (10 ms jitter) | 75, 32.9 cm | 55, 8.3 cm |
| Player two's copy off the server's prop at the same tick, worst while moving, localhost / 100 ms | 18 cm / 104 cm | 5 to 7 cm / 25 cm |
| Player two's copy off the server's, at rest | 2.3 mm (0.9 mm at 100 ms) | 0.2 mm (3.8 mm at 100 ms) |

| Cost | Number |
| --- | --- |
| Props and targets in the prototype map | 12 props, 4 targets (34 parts in all, with the pressure pad) |
| WELCOME with the table, no player | 324 bytes before the pressure pad (124 before the props and targets) |
| A moving prop in a TICK / 8 of them | 14 / 112 bytes |
| A client's step, every prop moving: reading the rows / putting the 12 props at the tick | 19.5 / 43.8 µs (none at rest) |
| The server's rows of a TICK (8 props) | 50 µs |

- **Approach:** Stream a part the server simulates (its state in each TICK while it is awake, one record more as it
  falls asleep, every record in the WELCOME), freeze the client's copy as a static body and put it at the predicted
  command's tick by moving the records on at their speed; accept and count the corrections a push costs. **Watch out
  for:** a copy drawn at the interpolated past (as the puppets are) is a round trip and the interpolation delay behind
  the crate the server's body pushes, so the pusher is held back by that much on every answer; and a client's
  `PropTrack` holds an asleep record, so a guess never carries a stopped crate on. **Seen:** gdstudio #1073,
  2026-11-11 (`test_net_props.gd`: worst 33 cm at 100 ms each way on the 5 kg crate, the pin is 0.5 m).
- **Approach:** Take the turn between two records from its vector part (the axis `xyz` normalized, the angle
  `2 atan2(|xyz|, w)`), and grep a new net suite's log for `ERROR` as well as its count. **Watch out for:**
  `get_axis()` of a turn of a few thousandths of a degree is zero while `get_angle()` is not, so `Quaternion(axis,
  angle)` printed `must be normalized` every step; the suites passed, and only the bad-network gate (any `ERROR` in
  the client's log fails it) caught it. **Seen:** gdstudio #1073, 2026-11-11 (the gate's first CI run on #1099).
- **Approach:** When a TICK grows a section, size its limit against the socket buffer's pin (`test_net_limits.gd`: ten
  seconds of the longest TICKs in `NetLimits.BUFFER_SIZE`) before choosing it. **Watch out for:** 32 streamed rows of
  15 bytes took the longest TICK from 715 to 1196 bytes and broke the pin; 8 rows keep it (868 bytes, with the
  longest event now an `entity` of a 12-byte state, 20 bytes, one past a `joined`), and more moving props take turns.
  **Seen:** gdstudio #1073, 2026-11-11.

## Targets online {#targets}

<!-- new section: shots and hits (#906) put a target's health on a client from the HIT; nothing held who stands a
     target up, what a late joiner sees, or when a client shows the fall (gdstudio #1073) -->

A `Target` (`target.tscn`, its `NetEntity` of kind `target`) falls and stands on the server: its `Health` reaches zero
on the server's shot (or an AI's, or a script's `kill()`), and it stands after `reset_time` by the server's clock. Each
change is an `entity` event of one byte (down; 9 bytes in the TICK), and the WELCOME's table carries it, so a late
joiner sees a board that is down lying down. A client's board falls when the HIT's health reaches zero or its record
says so, and stands only when its record says so: it counts no `reset_time` of its own. The event is played with the
puppets (`NetEntity.with_puppets`: `ClientCombat` queues it after the HIT of the same TICK), so a board falls as the
impact lands, not a round trip before it.

- **Approach:** Give a part whose change a shot causes the server's word for both the change and its undoing, and play
  its event at the moment the shot's hit is drawn. **Watch out for:** before #1073 each client stood its board up by its
  own `reset_time`, so a board the server held down stood on every screen, and a late joiner saw every board standing.
  **Seen:** gdstudio #1073, 2026-11-11 (`test_net_props.gd`).
