# Shots, hits and deaths online

<!-- new section: the game-server and online-client pages say how bodies move; nothing said who decides a hit online,
     what travels for a shot or a death, or what each screen makes itself (gdstudio #906) -->

The server of [the game server](game-server.md#template-server) owns every hit and every health; the clients of [the
online client](online-client.md#template-client) send presses and play small events. Part of [the 3D Third Person
template](../third-person-template.md); the bytes are [the template's packets](../multiplayer.md#template-packets).

## Who decides what {#template-shots}

<!-- new section: the server's rules for a shot and the events it sends, with the client's side of each -->

`ServerCombat` (`gameplay/net/server_combat.gd`, one on each `NetServer`) and `ClientCombat`
(`gameplay/net/client_combat.gd`, one on each `NetClient`); what a HIT names is `NetHits` (`net_hits.gd`).

- **The server fires the real shot.** Its bodies' weapons are the real ones (`Weapon.authoritative` on) with no
  flash, sound or mark (`Weapon.effects` off): the body fires along the command's shot block inside its own `step`,
  as offline, and its `Projectile` (a body on the server only) hits through `HitZones` or a `Health` as offline. The
  server's bodies have no model, so no hit zones: a shot on a body is a hit on the whole body (no head multiplier).
- **Before a step the server judges the shot block** (`ServerCombat.judge`): numbers that are not finite, an origin
  farther than `origin_slack` (4 m) from the body's eye, or fire pressed while the weapon cools down are refused. The
  shot block and the fire presses come off the command, nothing fires, and the sender alone gets `REJECTED` (its
  command's `seq`, the `ServerCombat.Reason`). A client cannot even send a number that is not finite
  (`CommandCodec.encode` refuses it), so that rule is for a hand-made packet.
- **Events.** A shot that leaves is a `SHOT` (slot, the low 16 bits of the command's `seq`, the loadout slot + 1, where
  it left, the way it went after the spread) to every other player, never back to the shooter. What it meets is a
  `HIT` (the point, the normal, the kind, the id, the health it left) to everyone. A body whose health reaches zero is a
  `DIED` (slot, the velocity of its last step, the cause); after `revive_seconds` (3 s) the server gets it up where it
  died (or at its spawn point with `revive_at_spawn`), in whole centimetres, and sends `REVIVED` with that point.
- **Ids.** A player is `0xFF00 + slot` (the body carries the meta `net_slot` on every peer), a `Target` `0xFE00 +` its
  place among the map's targets (the group `target`) by node path in its viewport; anything else has no id and the
  client finds the surface with a 10 cm ray along the normal. The world table of #907 takes the low ids.
- **The spread is seeded by the slot and the command's number** (`Weapon.seed_base`, `shot_seq`), so a predicting
  client draws the same pellet as the server whatever either fired before; the puppets copy the server's heading.
- **No rewind.** The server checks a shot against its world as it is: a projectile flies for many ticks, so the
  frame the shooter saw (`view_tick`, in the command) cannot decide what it meets. At 200 ms each way a shot at a
  running player drawn 1.3 m behind missed, the same shot at one who stood hit, on every screen
  (`test_at_200_ms_each_way_the_server_decides_what_a_shot_hit`).

What each screen makes itself (`ClientCombat`), never sent: the shooter's own flash, sound, recoil and round at once
(its weapon is cosmetic: `authoritative` off, the round stops at its first contact and changes nothing); a puppet's
shot from its own muzzle along the event's heading with the weapon the event names (`Weapon.fire_cosmetic`,
`WeaponLoadout.equip_now`); the impact of the surface at the server's point (mark, effect, sound) and a cosmetic round
on its way there ends there (`Projectile.stop_at`); the health on the player or target (`Health.set_wire_value`: a
target at zero falls, a player's zero waits for its `DIED`); the flinch on the part this screen's pose has at the point;
the ragdoll, from the pose the body is in and the event's velocity; the get-up, the body standing at the server's point
at once and the pose blending there over `get_up_time` (`Character.revive_at`). Events about the local player play at
once; the rest wait until the puppets are drawn at their TICK's time (`RemotePlayers.drawn_time`), so a puppet's
shot leaves where the puppet is drawn and its hit lands as the round gets there. A dead puppet is left to its ragdoll
(`PlayerPuppet.place`); a ragdoll that falls out of the map waits for the server's `REVIVED`.

## What it measured {#shot-costs}

<!-- new section: the numbers the bad-network proof (#908) builds on -->

MEASUREMENTS
