# Networked map parts

<!-- new section: the game-server and online-client pages hold the players; nothing held how the map's doors,
     platforms and pickups are owned by the server and shown by a predicting client (gdstudio #907) -->

How the 3D Third Person map's doors, moving platforms and pickups work in an online game: the server owns them, a
predicting client meets the same panel and rides the same slab, and a late joiner sees them as they are. Part of
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
  to be stepped at (`NetClient.first_seq`: the WELCOME's tick and the round trip; renumbered forward after a stall).
  Before it predicts command `seq` it puts every moving part at tick `seq`; the server, before it steps a body with
  command `seq`, puts them at the same tick (`NetServer.command_tick`, held within 4 s behind and 1 s ahead of its
  step), and at its own tick after the bodies. The two bodies meet the same panel and stand on the same slab.
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
- **Puppets on a slab.** A client draws the slab at its predicted tick and a puppet 100 ms behind the newest TICK;
  `RemotePlayers` moves a puppet that stands on a slab by what the slab moves between the two moments, so player two
  sees the rider standing still on the slab it draws.

State bytes (at most `NetLimits.MAX_ENTITY_STATE`, 8): a door 4 (flags opening and locked, u16 the openness the motion
starts from, u8 the ticks to its start), a platform 6 (flags running and direction, u16 the distance, u16 the ticks it
still waits, u8 the ticks to its start), a pickup 1 (available). The server rounds a new motion's start as the wire
carries it, so both sides compute the same function; a WELCOME row is rebased to its tick (0.06 mm off at most).

Measured (Windows, Godot 4.7.2, one process with the server and its clients over a real socket on 127.0.0.1;
`test_net_map_parts.gd`, `test_net_platform_ride.gd`, `test_net_door_prediction.gd`, `test_net_server_cost.gd`):

| What | Number |
| --- | --- |
| Parts in the prototype map (doors, platforms, pickups, the pathing section's included) | 17, 6 of them moving |
| WELCOME with the table, no player | 124 bytes (15 without it) |
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

A map component plays online when it answers each line; the three of #907 do, props and targets are the next.

1. **State:** what a late joiner needs, in at most 8 bytes, written as at a tick (`net_write`) and read back
   (`net_read`).
2. **Owner:** the server runs the rules; a client's copy runs none and senses nothing (`net_set_role`).
3. **Solid and moving:** a pure function of the tick (`net_place`), static online, riders carried by the same function.
4. **Changes:** start `entity_lead_ticks` after they are decided when a body can meet them; said with
   `NetEntity.report()`.
5. **Once only:** who did it (a pickup's taker) comes from the server's word (`report_taken`, a `pickup` event), never
   from a client's touch.
6. **Cosmetic:** spin, bob, sound and signals that only draw stay local.
7. **In the scene:** `net_entity.tscn` as a child with its `net_kind`, so the world hash and the ids see it.
