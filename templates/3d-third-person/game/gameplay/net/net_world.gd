class_name NetWorld
extends RefCounted
## The networked parts of one map on one peer (`NetEntity`), numbered by path so every peer of a
## build gives a part the same id, and the clock they move by.
##
## The clock is a server tick. A door's panel and a platform's slab are a pure function of it
## (`Door.openness_at`, `MovingPlatform.position_at`), so a peer can put them where they are at any
## tick: the server puts them at a command's tick before it steps that command's body, and a client
## at the same tick before it predicts the command (`place`). Both bodies then meet the same panel
## and ride the same slab (multiplayer.md#the-two-worlds-must-hold-the-same-solid-things).
##
## A change the server decides starts `lead_ticks` later than the tick it was decided at, so a
## client hears of it before its predicted commands reach that tick.

## The parts, by id.
var entities: Array[NetEntity] = []
var role := NetEntity.Role.OFFLINE
## The tick the parts are at: the server's step, or the command a client predicts.
var tick := 0
## Ticks between a change the server decides and its start.
var lead_ticks := 0

# The parts that move by the tick (`net_place`).
var _movers: Array[NetEntity] = []


## Numbers the parts under `root` (the map node) and gives each `as_role`.
func _init(root: Node = null, as_role := NetEntity.Role.OFFLINE, lead := 0) -> void:
	role = as_role
	lead_ticks = lead
	if root == null:
		return
	entities = parts_under(root)
	for index in entities.size():
		var entity := entities[index]
		entity.id = index
		entity.world = self
		entity.role = as_role
		var part := entity.part()
		if part.has_method(&"net_set_role"):
			part.call(&"net_set_role", as_role)
		if part.has_method(&"net_place"):
			_movers.append(entity)


## The networked parts under `root`, sorted by their path from it (their ids).
static func parts_under(root: Node) -> Array[NetEntity]:
	var found: Array[NetEntity] = []
	for node in root.find_children("*", "", true, false):
		var entity := node as NetEntity
		if entity != null and entity.kind() != 0:
			found.append(entity)
	found.sort_custom(
		func(a: NetEntity, b: NetEntity) -> bool:
			return str(root.get_path_to(a)) < str(root.get_path_to(b))
	)
	return found


## The parts that move by the tick (doors, platforms).
func movers() -> Array[NetEntity]:
	return _movers


## The part of `id`, or null.
func by_id(id: int) -> NetEntity:
	return entities[id] if id >= 0 and id < entities.size() else null


## Puts every part that moves by the tick where it is at `at_tick`.
func place(at_tick: int) -> void:
	for entity in _movers:
		entity.part().call(&"net_place", at_tick)


## Every part's state as at `at_tick` (a WELCOME's table).
func table(at_tick: int) -> Array[EntityEntry]:
	var out: Array[EntityEntry] = []
	for entity in entities:
		var state: PackedByteArray = entity.part().call(&"net_write", at_tick)
		out.append(EntityEntry.make(entity.id, entity.kind(), state))
	return out


## Reads a WELCOME's table, written as at `at_tick`; false when it is not this map's (a row of
## another kind or an unknown id: the world hash should have refused that client).
func read_table(rows: Array[EntityEntry], at_tick: int) -> bool:
	var whole := true
	for row in rows:
		whole = read_state(row.id, row.kind, row.state, at_tick) and whole
	return whole


## Reads an `entity` event's new state.
func read_event(event: NetEvent) -> bool:
	var entity := by_id(event.id)
	return entity != null and read_state(event.id, entity.kind(), event.state, event.tick)


## Reads one part's state, written as at `at_tick`.
func read_state(id: int, kind: int, state: PackedByteArray, at_tick: int) -> bool:
	var entity := by_id(id)
	if entity == null or entity.kind() != kind:
		return false
	return entity.part().call(&"net_read", state, at_tick)


## A `pickup` event: the part is taken, and `by` (this client's own body when the slot is its own,
## else null) is given what it holds.
func read_pickup(event: NetEvent, by: Node3D) -> NetEntity:
	var entity := by_id(event.id)
	if entity == null or not entity.part().has_method(&"net_take"):
		return null
	entity.part().call(&"net_take", by)
	return entity
