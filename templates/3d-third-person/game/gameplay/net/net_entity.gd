class_name NetEntity
extends Node
## Puts the map component it sits under (its parent: a `Door`, a `MovingPlatform`, a `Pickup`) in
## an online game. `net_entity.tscn` is in each component's scene, so every door, platform and
## pickup of a map is networked; offline it does nothing.
##
## The node is in the group `net_part` with its `net_kind` metadata, so the map's parts make the
## world hash (`NetServer.world_hash_of`). A `NetWorld` gives it an `id` (its rank among the
## map's parts by path, the same on every peer of one build) and a `role`: on the server the
## component runs its own rules and says each change (`changed`, `taken`), on a client it runs none
## and shows what the server's records say.
##
## The component implements, by name: `net_set_role(role)`, `net_write(at_tick) ->
## PackedByteArray` (its state as at that server tick, at most `NetLimits.MAX_ENTITY_STATE`
## bytes), `net_read(state, at_tick)`; a part that moves by the tick (`Door`, `MovingPlatform`)
## also `net_place(tick)`, and a pickup `net_take(by)`.

## The server's copy of the part changed state; the server sends the new state to every client.
signal changed(entity: NetEntity)
## The server's copy of a pickup was taken by `by` (a body); the server says who to every client.
signal taken(entity: NetEntity, by: Node3D)

## Who runs the part.
enum Role {
	OFFLINE,  ## A game with no server: the part runs as it always did.
	SERVER,  ## The game server: the part runs its rules and says every change.
	CLIENT,  ## A client: the part runs no rule and shows the server's records.
}

## The kind byte of each part on the wire, by its `net_kind` metadata.
const KINDS := {&"door": 1, &"platform": 2, &"pickup": 3}

## The part's id in its map (`NetWorld` numbers the parts by path), or -1 outside one.
var id := -1
var role := Role.OFFLINE
## The world that numbered it (null offline).
var world: NetWorld


## The networked part under `component`, or null.
static func of(component: Node) -> NetEntity:
	for child in component.get_children():
		if child is NetEntity:
			return child
	return null


## The kind byte of this part (0 for a `net_kind` this build does not know).
func kind() -> int:
	return KINDS.get(StringName(get_meta(&"net_kind", "")), 0)


## The component this node networks.
func part() -> Node:
	return get_parent()


## Whether the part is driven by a server (on the server, or on a client).
func is_online() -> bool:
	return role != Role.OFFLINE


## The tick a change decided now starts at: the server's tick and the world's lead, so a client
## hears of a moving door before its predicted body meets it (third-person/net-world.md).
func start_tick() -> int:
	return world.tick + world.lead_ticks if world != null else 0


## The tick the part's world is at (the server's step, or the client's predicted command).
func now() -> int:
	return world.tick if world != null else 0


## Says that the server's copy changed state (nothing offline or on a client).
func report() -> void:
	if role == Role.SERVER:
		changed.emit(self)


## Says that the server's copy of a pickup was taken by `by`.
func report_taken(by: Node3D) -> void:
	if role == Role.SERVER:
		taken.emit(self, by)
