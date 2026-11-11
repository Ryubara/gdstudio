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
##
## A part the server simulates (a pushed prop) is streamed instead: its state rides each TICK while
## it moves (`stream_rows`, read back with `read_stream`), at most `NetLimits.MAX_STREAMED_PARTS`
## a TICK, the rest in the next ones (third-person/net-world.md#props).

## The parts, by id.
var entities: Array[NetEntity] = []
var role := NetEntity.Role.OFFLINE
## The tick the parts are at: the server's step, or the command a client predicts.
var tick := 0
## Ticks between a change the server decides and its start.
var lead_ticks := 0

# The parts that move by the tick (`net_place`).
var _movers: Array[NetEntity] = []
# The parts whose state rides the TICKs (`NetEntity.stream`), and where the next TICK starts
# among them when more want to ride than one carries.
var _streamers: Array[NetEntity] = []
var _stream_from := 0
var _all_from := 0


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
		if entity.take_role.is_valid():
			entity.take_role.call(as_role)
		if entity.place.is_valid():
			_movers.append(entity)
		if entity.stream.is_valid():
			_streamers.append(entity)


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


## The parts whose state rides the TICKs (props).
func streamers() -> Array[NetEntity]:
	return _streamers


## The rows of this TICK, written as at `at_tick`: every streamed part that says it rides, at most
## `limit`; the next call starts after the last one taken, so none waits for long. `all`: the next
## `limit` streamed parts whether they ride or not, in turn (`all_ticks` calls give every one), for
## a client whose TICK was refused.
func stream_rows(
	at_tick: int, all := false, limit := NetLimits.MAX_STREAMED_PARTS
) -> Array[EntityEntry]:
	var out: Array[EntityEntry] = []
	var count := _streamers.size()
	var from := _all_from if all else _stream_from
	var index := 0
	while index < count and out.size() < limit:
		var entity := _streamers[(from + index) % count]
		index += 1
		if all or entity.stream.call():
			var state: PackedByteArray = entity.write_state.call(at_tick)
			out.append(EntityEntry.make(entity.id, entity.kind(), state))
	if count > 0 and all:
		_all_from = (from + index) % count
	elif count > 0:
		_stream_from = (from + index) % count
	return out


## The TICKs a client takes to be sent every streamed part (`stream_rows` with `all`).
func all_ticks(limit := NetLimits.MAX_STREAMED_PARTS) -> int:
	return ceili(float(_streamers.size()) / float(limit))


## Reads a TICK's streamed rows (an id and a state each), written as at `at_tick`; false when one is
## not this map's.
func read_stream(rows: Array[EntityEntry], at_tick: int) -> bool:
	var whole := true
	for row in rows:
		var entity := by_id(row.id)
		whole = entity != null and read_state(row.id, entity.kind(), row.state, at_tick) and whole
	return whole


## Whether a client plays the `entity` event with the puppets (`NetEntity.with_puppets`).
func plays_with_puppets(event: NetEvent) -> bool:
	var entity := by_id(event.id)
	return entity != null and entity.with_puppets


## The part of `id`, or null.
func by_id(id: int) -> NetEntity:
	return entities[id] if id >= 0 and id < entities.size() else null


## Puts every part that moves by the tick where it is at `at_tick`.
func place(at_tick: int) -> void:
	for entity in _movers:
		entity.place.call(at_tick)


## Every part's state as at `at_tick` (a WELCOME's table).
func table(at_tick: int) -> Array[EntityEntry]:
	var out: Array[EntityEntry] = []
	for entity in entities:
		var state: PackedByteArray = entity.write_state.call(at_tick)
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
	if entity == null or entity.kind() != kind or not entity.read_state.is_valid():
		return false
	return entity.read_state.call(state, at_tick)


## A `pickup` event: the part is taken, and `by` (this client's own body when the slot is its own,
## else null) is given what it holds.
func read_pickup(event: NetEvent, by: Node3D) -> NetEntity:
	var entity := by_id(event.id)
	if entity == null or not entity.take.is_valid():
		return null
	entity.take.call(by)
	return entity
