class_name NetEntity
extends Node
## Puts the map component it sits under (its parent: a `Door`, a `MovingPlatform`, a `Pickup`, a
## `PhysicsProp`, a `Target`) in an online game. `net_entity.tscn` is in each component's scene, so
## every door, platform, pickup, prop and target of a map is networked; offline it does nothing. A
## pressure pad's `TriggerZone` is put online by `TriggerZoneNet` (`trigger_zone_net.tscn`, a
## `NetEntity` of kind `pad`) placed under it in the map, since a camera zone's `TriggerZone` stays
## one screen's own.
##
## The node is in the group `net_part` with its `net_kind` metadata, so the map's parts make the
## world hash (`NetServer.world_hash_of`). A `NetWorld` gives it an `id` (its rank among the
## map's parts by path, the same on every peer of one build) and a `role`: on the server the
## component runs its own rules and says each change (`changed`, `taken`), on a client it runs none
## and shows what the server's records say.
##
## The component hands over its functions in its `_ready` (`serve`): how it writes its state as at a
## server tick (at most `NetLimits.MAX_ENTITY_STATE` bytes) and reads it back, what it does when it
## is given a role; a part that moves by the tick (`Door`, `MovingPlatform`) how it is put at a
## tick, and a pickup how it is taken. A part the server simulates (a `PhysicsProp`) also says
## whether its state goes in this TICK (`streams`): its records ride every TICK while it moves.

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
const KINDS := {&"door": 1, &"platform": 2, &"pickup": 3, &"pad": 4, &"prop": 5, &"target": 6}

## `func(at_tick: int) -> PackedByteArray`: the part's state as at a server tick.
var write_state := Callable()
## `func(state: PackedByteArray, at_tick: int) -> bool`: reads a state written as at a tick.
var read_state := Callable()
## `func(role: Role)`: the part is given a role.
var take_role := Callable()
## `func(tick: int)`: puts a part that moves by the tick where it is at `tick` (empty: it does not).
var place := Callable()
## `func(by: Node3D)`: the server says a pickup was taken (empty: not a pickup).
var take := Callable()
## `func() -> bool`, on the server: whether the part's state rides this TICK (empty: it never
## does; its changes are `entity` events).
var stream := Callable()
## On: a client plays the part's `entity` events when the puppets are drawn at their tick, with the
## shots and hits (a target that falls as the hit lands), not at once.
var with_puppets := false
## The part's id in its map (`NetWorld` numbers the parts by path), or -1 outside one.
var id := -1
var role := Role.OFFLINE
## The world that numbered it (null offline).
var world: NetWorld


## Hands over the component's functions (see the fields of the same names).
func serve(
	writer: Callable,
	reader: Callable,
	role_taker: Callable,
	placer := Callable(),
	taker := Callable()
) -> void:
	write_state = writer
	read_state = reader
	take_role = role_taker
	place = placer
	take = taker


## The networked part under `component`, or null.
static func of(component: Node) -> NetEntity:
	for child in component.get_children():
		if child is NetEntity:
			return child
	return null


## The kind byte of this part (0 for a `net_kind` this build does not know).
func kind() -> int:
	return KINDS.get(StringName(get_meta(&"net_kind", "")), 0)


## Hands over `streamer` (see `stream`): the part's state rides each TICK it answers true.
func streams(streamer: Callable) -> void:
	stream = streamer


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
