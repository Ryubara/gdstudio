class_name SnapshotCodec
extends RefCounted
## The server's messages that carry state: a TICK (the events since the last one, every player,
## then the moving props: `NetWorld.stream_rows`) and a WELCOME (the world table and every
## player, for a client that joins at any time). The layouts are in `NetWire` and `NetEvent`.
## Snapshots are full: eight players are 96 bytes a tick (104 with all of them aiming), and a full
## snapshot repairs whatever a stall delayed.
##
## A decoder checks a count against the bytes left before it reads a single entry (never
## allocating by what a packet claims) and answers null, with the reason counted, for anything
## that is not exactly one message.

## A player entry's bytes; an aiming player's carries `AIM_YAW_SIZE` more (the aim's heading off
## the body, kit #1277).
const PLAYER_SIZE := 12
const AIM_YAW_SIZE := 1
const MAX_PLAYER_SIZE := PLAYER_SIZE + AIM_YAW_SIZE
## A player's aim pitch is a signed byte over a quarter turn either way.
const PITCH_STEPS := 127
const PITCH_STEP := (PI / 2.0) / PITCH_STEPS
## The aim's heading off the body is a signed byte over a half turn either way.
const AIM_YAW_STEP := PI / PITCH_STEPS

const F_CROUCH := 1 << 0
const F_AIM := 1 << 1
const F_SPRINT := 1 << 2
const F_AIR := 1 << 3
const F_RISING := 1 << 4
const F_DEAD := 1 << 5

## The shortest event (a kind and one byte) and the longest: an ENTITY with the longest state (20
## bytes), one longer than a JOINED with the longest name (19).
const MIN_EVENT_SIZE := 2
const MAX_EVENT_SIZE := 8 + NetLimits.MAX_ENTITY_STATE
const MAX_TICK := (
	NetWire.TICK_HEADER
	+ NetLimits.MAX_EVENTS * MAX_EVENT_SIZE
	+ NetLimits.MAX_PLAYERS * MAX_PLAYER_SIZE
	+ NetWire.TICK_TAIL
	+ NetLimits.MAX_STREAMED_PARTS * (NetWire.STREAM_ROW_HEADER + NetLimits.MAX_ENTITY_STATE)
	+ AiSnapshot.MAX_BLOCK
)
## A world row: u16 id, u8 kind, u8 state length (then the state).
const ENTITY_HEADER := 4
## A WELCOME player: the entry and the name's length (then the name).
const WELCOME_PLAYER_HEADER := PLAYER_SIZE + 1
const MAX_WELCOME_PLAYER := MAX_PLAYER_SIZE + 1
const MAX_WELCOME := (
	NetWire.WELCOME_HEADER
	+ 2
	+ NetLimits.MAX_ENTITIES * (ENTITY_HEADER + NetLimits.MAX_ENTITY_STATE)
	+ 1
	+ NetLimits.MAX_PLAYERS * (MAX_WELCOME_PLAYER + NetLimits.NAME_BYTES)
)


## A TICK, read.
class Tick:
	extends RefCounted
	var server_tick := 0
	## The last command seq the server applied for this client.
	var ack := 0
	var events: Array[NetEvent] = []
	var players: Array[PlayerEntry] = []
	## The moving props' rows (an id and a state each; the kind is left 0).
	var parts: Array[EntityEntry] = []
	## The AI characters for this client (`AiSnapshot`): NONE when nothing changed.
	var ai := AiSnapshot.Block.new()


## A WELCOME, read.
class Welcome:
	extends RefCounted
	var version := 0
	var slot := 0
	var tick_rate := 0
	var server_tick := 0
	var world_hash := 0
	var entities: Array[EntityEntry] = []
	var players: Array[PlayerEntry] = []


# --- TICK ---


## The TICK packet, or an empty array (counted in `drops`) when what it would carry cannot travel
## (too many events, players or parts, a slot out of range, a number that is not finite).
static func tick(
	server_tick: int,
	ack: int,
	events: Array[NetEvent],
	players: Array[PlayerEntry],
	drops: NetDrops = null,
	parts: Array[EntityEntry] = [],
	ai := PackedByteArray()
) -> PackedByteArray:
	if events.size() > NetLimits.MAX_EVENTS or players.size() > NetLimits.MAX_PLAYERS:
		NetDrops.note(drops, NetDrops.TOO_MANY)
		return PackedByteArray()
	if parts.size() > NetLimits.MAX_STREAMED_PARTS:
		NetDrops.note(drops, NetDrops.TOO_MANY)
		return PackedByteArray()
	var out := StreamPeerBuffer.new()
	out.put_u8(NetWire.Type.TICK)
	out.put_u32(server_tick & 0xFFFFFFFF)
	out.put_u32(ack & 0xFFFFFFFF)
	out.put_u8(events.size())
	for event in events:
		var reason := write_event(out, event)
		if reason != &"":
			NetDrops.note(drops, reason)
			return PackedByteArray()
	out.put_u8(players.size())
	for player in players:
		var reason := write_player(out, player)
		if reason != &"":
			NetDrops.note(drops, reason)
			return PackedByteArray()
	out.put_u8(parts.size())
	for row in parts:
		if row.id < 0 or row.id > 0xFFFF:
			NetDrops.note(drops, NetDrops.BAD_VALUE)
			return PackedByteArray()
		if row.state.size() > NetLimits.MAX_ENTITY_STATE:
			NetDrops.note(drops, NetDrops.TOO_LONG)
			return PackedByteArray()
		out.put_u16(row.id)
		out.put_u8(row.state.size())
		out.put_data(row.state)
	# The AI block, made by `AiSnapshot.encode` for this client (NONE when there is none).
	if ai.is_empty():
		out.put_u8(AiSnapshot.Mode.NONE)
	elif ai.size() > AiSnapshot.MAX_BLOCK:
		NetDrops.note(drops, NetDrops.TOO_LONG)
		return PackedByteArray()
	else:
		out.put_data(ai)
	return out.data_array


## The TICK in a packet, or null (counted in `drops`).
static func read_tick(data: PackedByteArray, drops: NetDrops = null) -> Tick:
	if data.is_empty():
		return _drop(drops, NetDrops.EMPTY)
	if data[0] != NetWire.Type.TICK:
		return _drop(drops, NetDrops.UNKNOWN_TYPE)
	if data.size() < NetWire.TICK_HEADER + NetWire.TICK_TAIL:
		return _drop(drops, NetDrops.TOO_SHORT)
	if data.size() > MAX_TICK:
		return _drop(drops, NetDrops.TOO_LONG)
	var reader := WireReader.new(data, 1)
	var result := Tick.new()
	result.server_tick = reader.u32()
	result.ack = reader.u32()
	var event_count := reader.u8()
	if event_count > NetLimits.MAX_EVENTS:
		return _drop(drops, NetDrops.TOO_MANY)
	# Each event is at least two bytes, and the player count follows them.
	if event_count * MIN_EVENT_SIZE > reader.left() - 1:
		return _drop(drops, NetDrops.COUNT_PAST_END)
	for _index in event_count:
		var event := read_event(reader, drops)
		if event == null:
			return null
		result.events.append(event)
	if not reader.has(1):
		return _drop(drops, NetDrops.COUNT_PAST_END)
	var players := _read_players(reader, drops)
	if players == null:
		return null
	result.players = players.players
	var part_count := reader.u8()
	if not reader.ok:
		return _drop(drops, NetDrops.COUNT_PAST_END)
	if part_count > NetLimits.MAX_STREAMED_PARTS:
		return _drop(drops, NetDrops.TOO_MANY)
	# The rows, then at least the AI block's mode.
	if part_count * NetWire.STREAM_ROW_HEADER > reader.left() - 1:
		return _drop(drops, NetDrops.COUNT_PAST_END)
	for _index in part_count:
		var row := EntityEntry.new()
		row.id = reader.u16()
		var state_size := reader.u8()
		if state_size > NetLimits.MAX_ENTITY_STATE:
			return _drop(drops, NetDrops.BAD_VALUE)
		row.state = reader.take(state_size)
		if not reader.ok:
			return _drop(drops, NetDrops.COUNT_PAST_END)
		result.parts.append(row)
	var block := AiSnapshot.read_block(reader, drops)
	if block == null:
		return null
	result.ai = block
	if reader.left() != 0:
		return _drop(drops, NetDrops.TOO_LONG)
	return result


# --- WELCOME ---


## The WELCOME packet for a client given `slot`, or an empty array (counted in `drops`) when the
## world table or the players cannot travel.
static func welcome(
	slot: int,
	server_tick: int,
	world_hash: int,
	entities: Array[EntityEntry],
	players: Array[PlayerEntry],
	drops: NetDrops = null
) -> PackedByteArray:
	if slot < 0 or slot >= NetLimits.MAX_PLAYERS:
		NetDrops.note(drops, NetDrops.BAD_VALUE)
		return PackedByteArray()
	if entities.size() > NetLimits.MAX_ENTITIES or players.size() > NetLimits.MAX_PLAYERS:
		NetDrops.note(drops, NetDrops.TOO_MANY)
		return PackedByteArray()
	var out := StreamPeerBuffer.new()
	out.put_u8(NetWire.Type.WELCOME)
	out.put_u8(NetWire.VERSION)
	out.put_u8(slot)
	out.put_u8(NetLimits.TICK_RATE)
	out.put_u32(server_tick & 0xFFFFFFFF)
	out.put_u32(world_hash & 0xFFFFFFFF)
	out.put_u16(entities.size())
	for entry in entities:
		if entry.id < 0 or entry.id > 0xFFFF or entry.kind < 0 or entry.kind > 0xFF:
			NetDrops.note(drops, NetDrops.BAD_VALUE)
			return PackedByteArray()
		if entry.state.size() > NetLimits.MAX_ENTITY_STATE:
			NetDrops.note(drops, NetDrops.TOO_LONG)
			return PackedByteArray()
		out.put_u16(entry.id)
		out.put_u8(entry.kind)
		out.put_u8(entry.state.size())
		out.put_data(entry.state)
	out.put_u8(players.size())
	for player in players:
		var reason := write_player(out, player)
		if reason != &"":
			NetDrops.note(drops, reason)
			return PackedByteArray()
		var name_bytes := NetWire.clip_name(player.player_name)
		out.put_u8(name_bytes.size())
		out.put_data(name_bytes)
	return out.data_array


## The WELCOME in a packet, or null (counted in `drops`). The version is checked first.
static func read_welcome(data: PackedByteArray, drops: NetDrops = null) -> Welcome:
	if data.is_empty():
		return _drop(drops, NetDrops.EMPTY)
	if data[0] != NetWire.Type.WELCOME:
		return _drop(drops, NetDrops.UNKNOWN_TYPE)
	if data.size() <= NetWire.VERSION_AT:
		return _drop(drops, NetDrops.TOO_SHORT)
	if not NetWire.accepts(data[NetWire.VERSION_AT]):
		return _drop(drops, NetDrops.BAD_VERSION)
	# The header, the entity count and the player count.
	if data.size() < NetWire.WELCOME_HEADER + 3:
		return _drop(drops, NetDrops.TOO_SHORT)
	if data.size() > MAX_WELCOME:
		return _drop(drops, NetDrops.TOO_LONG)
	var reader := WireReader.new(data, 1)
	var result := Welcome.new()
	result.version = reader.u8()
	result.slot = reader.u8()
	result.tick_rate = reader.u8()
	result.server_tick = reader.u32()
	result.world_hash = reader.u32()
	if result.slot >= NetLimits.MAX_PLAYERS or result.tick_rate == 0:
		return _drop(drops, NetDrops.BAD_VALUE)
	var entity_count := reader.u16()
	if entity_count > NetLimits.MAX_ENTITIES:
		return _drop(drops, NetDrops.TOO_MANY)
	if entity_count * ENTITY_HEADER > reader.left() - 1:
		return _drop(drops, NetDrops.COUNT_PAST_END)
	for _index in entity_count:
		var entry := EntityEntry.new()
		entry.id = reader.u16()
		entry.kind = reader.u8()
		var state_size := reader.u8()
		if state_size > NetLimits.MAX_ENTITY_STATE:
			return _drop(drops, NetDrops.BAD_VALUE)
		entry.state = reader.take(state_size)
		if not reader.ok:
			return _drop(drops, NetDrops.COUNT_PAST_END)
		result.entities.append(entry)
	var player_count := reader.u8()
	if not reader.ok:
		return _drop(drops, NetDrops.COUNT_PAST_END)
	if player_count > NetLimits.MAX_PLAYERS:
		return _drop(drops, NetDrops.TOO_MANY)
	if player_count * WELCOME_PLAYER_HEADER > reader.left():
		return _drop(drops, NetDrops.COUNT_PAST_END)
	var seen := 0
	for _index in player_count:
		var player := read_player(reader)
		var name_size := reader.u8()
		if not reader.ok:
			return _drop(drops, NetDrops.COUNT_PAST_END)
		if name_size > NetLimits.NAME_BYTES:
			return _drop(drops, NetDrops.NAME_TOO_LONG)
		var name_bytes := reader.take(name_size)
		if not reader.ok:
			return _drop(drops, NetDrops.COUNT_PAST_END)
		if not NetWire.valid_name(name_bytes):
			return _drop(drops, NetDrops.BAD_NAME)
		if player.slot >= NetLimits.MAX_PLAYERS or seen & (1 << player.slot) != 0:
			return _drop(drops, NetDrops.BAD_VALUE)
		seen |= 1 << player.slot
		player.player_name = name_bytes.get_string_from_utf8()
		result.players.append(player)
	if reader.left() != 0:
		return _drop(drops, NetDrops.TOO_LONG)
	return result


# --- Players ---


## Writes one player entry (12 bytes, 13 while aiming); answers the reason it cannot (`&""` when
## written).
static func write_player(out: StreamPeerBuffer, player: PlayerEntry) -> StringName:
	if not player.all_finite():
		return NetDrops.NOT_FINITE
	if player.slot < 0 or player.slot >= NetLimits.MAX_PLAYERS:
		return NetDrops.BAD_VALUE
	out.put_u8(player.slot)
	out.put_16(CommandCodec.point_step(player.position.x))
	out.put_16(CommandCodec.point_step(player.position.y))
	out.put_16(CommandCodec.point_step(player.position.z))
	out.put_u16(CommandCodec.yaw_step(player.yaw))
	out.put_u8(clampi(player.state, 0, 0xFF))
	out.put_u8(_player_flags(player))
	out.put_8(pitch_step(player.pitch))
	if player.aim:
		out.put_8(aim_yaw_step(player.aim_yaw))
	return &""


## Reads one player entry (the caller checked that 12 bytes are left; an aiming player's 13th is
## checked by the reader: the caller looks at `reader.ok`).
static func read_player(reader: WireReader) -> PlayerEntry:
	var player := PlayerEntry.new()
	player.slot = reader.u8()
	var x := CommandCodec.point_from_step(reader.s16())
	var y := CommandCodec.point_from_step(reader.s16())
	var z := CommandCodec.point_from_step(reader.s16())
	player.position = Vector3(x, y, z)
	player.yaw = CommandCodec.yaw_from_step(reader.u16())
	player.state = reader.u8()
	var flags := reader.u8()
	player.crouch = flags & F_CROUCH != 0
	player.aim = flags & F_AIM != 0
	player.sprint = flags & F_SPRINT != 0
	player.air = flags & F_AIR != 0
	player.rising = flags & F_RISING != 0
	player.dead = flags & F_DEAD != 0
	player.pitch = pitch_from_step(reader.s8())
	if player.aim:
		player.aim_yaw = aim_yaw_from_step(reader.s8())
	return player


## The bytes `player`'s entry takes on the wire.
static func player_size(player: PlayerEntry) -> int:
	return MAX_PLAYER_SIZE if player.aim else PLAYER_SIZE


## The entry as a client reads it (the decode of the encode), or null when it cannot travel.
static func snap_player(player: PlayerEntry) -> PlayerEntry:
	var out := StreamPeerBuffer.new()
	if write_player(out, player) != &"":
		return null
	var result := read_player(WireReader.new(out.data_array))
	result.player_name = player.player_name
	return result


static func pitch_step(pitch: float) -> int:
	if not is_finite(pitch):
		return 0
	return roundi(clampf(pitch, -PI / 2.0, PI / 2.0) / PITCH_STEP)


static func pitch_from_step(step: int) -> float:
	return clampi(step, -PITCH_STEPS, PITCH_STEPS) * PITCH_STEP


static func aim_yaw_step(aim_yaw: float) -> int:
	if not is_finite(aim_yaw):
		return 0
	return roundi(wrapf(aim_yaw, -PI, PI) / AIM_YAW_STEP)


static func aim_yaw_from_step(step: int) -> float:
	return clampi(step, -PITCH_STEPS, PITCH_STEPS) * AIM_YAW_STEP


static func _player_flags(player: PlayerEntry) -> int:
	var flags := 0
	flags |= F_CROUCH if player.crouch else 0
	flags |= F_AIM if player.aim else 0
	flags |= F_SPRINT if player.sprint else 0
	flags |= F_AIR if player.air else 0
	flags |= F_RISING if player.rising else 0
	flags |= F_DEAD if player.dead else 0
	return flags


## The players of a TICK (u8 count, the entries), in a holder so null can mean a drop.
class PlayerList:
	extends RefCounted
	var players: Array[PlayerEntry] = []


static func _read_players(reader: WireReader, drops: NetDrops) -> PlayerList:
	var count := reader.u8()
	if count > NetLimits.MAX_PLAYERS:
		return _drop(drops, NetDrops.TOO_MANY)
	if count * PLAYER_SIZE > reader.left():
		return _drop(drops, NetDrops.COUNT_PAST_END)
	var result := PlayerList.new()
	var seen := 0
	for _index in count:
		var player := read_player(reader)
		if not reader.ok:
			return _drop(drops, NetDrops.COUNT_PAST_END)
		if player.slot >= NetLimits.MAX_PLAYERS or seen & (1 << player.slot) != 0:
			return _drop(drops, NetDrops.BAD_VALUE)
		seen |= 1 << player.slot
		result.players.append(player)
	return result


# --- Events ---


## Writes one event; answers the reason it cannot (`&""` when written).
static func write_event(out: StreamPeerBuffer, event: NetEvent) -> StringName:
	if not event.all_finite():
		return NetDrops.NOT_FINITE
	if event.slot < 0 or event.slot >= NetLimits.MAX_PLAYERS:
		return NetDrops.BAD_VALUE
	if event.id < 0 or event.id > 0xFFFF or event.code < 0 or event.code > 0xFF:
		return NetDrops.BAD_VALUE
	if event.amount < 0 or event.amount > 0xFF:
		return NetDrops.BAD_VALUE
	out.put_u8(event.kind)
	match event.kind:
		NetEvent.Kind.JOINED:
			var name_bytes := NetWire.clip_name(event.player_name)
			out.put_u8(event.slot)
			out.put_u8(name_bytes.size())
			out.put_data(name_bytes)
		NetEvent.Kind.LEFT:
			out.put_u8(event.slot)
		NetEvent.Kind.SHOT:
			out.put_u8(event.slot)
			out.put_u16(event.seq & 0xFFFF)
			out.put_u8(event.amount)
			_put_point(out, event.point)
			_put_direction(out, event.direction)
		NetEvent.Kind.HIT:
			_put_point(out, event.point)
			_put_direction(out, event.direction)
			out.put_u8(event.code)
			out.put_u16(event.id)
			out.put_u8(event.amount)
		NetEvent.Kind.DIED:
			out.put_u8(event.slot)
			_put_point(out, event.point)
			out.put_u8(event.code)
		NetEvent.Kind.REVIVED:
			out.put_u8(event.slot)
			_put_point(out, event.point)
		NetEvent.Kind.ENTITY:
			if event.state.size() > NetLimits.MAX_ENTITY_STATE:
				return NetDrops.TOO_LONG
			out.put_u16(event.id)
			out.put_u32(event.tick & 0xFFFFFFFF)
			out.put_u8(event.state.size())
			out.put_data(event.state)
		NetEvent.Kind.PICKUP:
			out.put_u16(event.id)
			out.put_u8(event.slot)
		NetEvent.Kind.REJECTED:
			out.put_u32(event.seq & 0xFFFFFFFF)
			out.put_u8(event.code)
		NetEvent.Kind.AI:
			if event.id > NetLimits.MAX_AI_ID:
				return NetDrops.BAD_VALUE
			out.put_u16(event.id)
			out.put_u8(event.code)
			_put_point(out, event.point)
			_put_direction(out, event.direction)
		_:
			return NetDrops.BAD_VALUE
	return &""


## Reads one event, or null (counted in `drops`): an unknown kind, a slot out of range, a name or
## a state too long, or fields that run past the end of the packet.
static func read_event(reader: WireReader, drops: NetDrops = null) -> NetEvent:
	var event := NetEvent.new()
	var kind := reader.u8()
	match kind:
		NetEvent.Kind.JOINED:
			event.slot = reader.u8()
			var name_size := reader.u8()
			if name_size > NetLimits.NAME_BYTES:
				return _drop(drops, NetDrops.NAME_TOO_LONG)
			var name_bytes := reader.take(name_size)
			if reader.ok and not NetWire.valid_name(name_bytes):
				return _drop(drops, NetDrops.BAD_NAME)
			event.player_name = name_bytes.get_string_from_utf8() if reader.ok else ""
		NetEvent.Kind.LEFT:
			event.slot = reader.u8()
		NetEvent.Kind.SHOT:
			event.slot = reader.u8()
			event.seq = reader.u16()
			event.amount = reader.u8()
			event.point = _get_point(reader)
			event.direction = _get_direction(reader)
		NetEvent.Kind.HIT:
			event.point = _get_point(reader)
			event.direction = _get_direction(reader)
			event.code = reader.u8()
			event.id = reader.u16()
			event.amount = reader.u8()
		NetEvent.Kind.DIED:
			event.slot = reader.u8()
			event.point = _get_point(reader)
			event.code = reader.u8()
		NetEvent.Kind.REVIVED:
			event.slot = reader.u8()
			event.point = _get_point(reader)
		NetEvent.Kind.ENTITY:
			event.id = reader.u16()
			event.tick = reader.u32()
			var state_size := reader.u8()
			if state_size > NetLimits.MAX_ENTITY_STATE:
				return _drop(drops, NetDrops.BAD_VALUE)
			event.state = reader.take(state_size)
		NetEvent.Kind.PICKUP:
			event.id = reader.u16()
			event.slot = reader.u8()
		NetEvent.Kind.REJECTED:
			event.seq = reader.u32()
			event.code = reader.u8()
		NetEvent.Kind.AI:
			event.id = reader.u16()
			event.code = reader.u8()
			event.point = _get_point(reader)
			event.direction = _get_direction(reader)
			if reader.ok and event.id > NetLimits.MAX_AI_ID:
				return _drop(drops, NetDrops.BAD_VALUE)
		_:
			return _drop(drops, NetDrops.BAD_VALUE)
	if not reader.ok:
		return _drop(drops, NetDrops.COUNT_PAST_END)
	if event.slot >= NetLimits.MAX_PLAYERS:
		return _drop(drops, NetDrops.BAD_VALUE)
	event.kind = kind as NetEvent.Kind
	return event


## The event as a client reads it (the decode of the encode), or null when it cannot travel.
static func snap_event(event: NetEvent) -> NetEvent:
	var out := StreamPeerBuffer.new()
	if write_event(out, event) != &"":
		return null
	return read_event(WireReader.new(out.data_array), NetDrops.new())


## The bytes one event takes in a TICK, or -1 when it cannot travel.
static func event_size(event: NetEvent) -> int:
	var out := StreamPeerBuffer.new()
	return -1 if write_event(out, event) != &"" else out.data_array.size()


static func _put_point(out: StreamPeerBuffer, point: Vector3) -> void:
	out.put_16(CommandCodec.point_step(point.x))
	out.put_16(CommandCodec.point_step(point.y))
	out.put_16(CommandCodec.point_step(point.z))


static func _get_point(reader: WireReader) -> Vector3:
	var x := CommandCodec.point_from_step(reader.s16())
	var y := CommandCodec.point_from_step(reader.s16())
	var z := CommandCodec.point_from_step(reader.s16())
	return Vector3(x, y, z)


static func _put_direction(out: StreamPeerBuffer, direction: Vector3) -> void:
	var angles := CommandCodec.direction_angles(direction)
	out.put_u16(CommandCodec.yaw_step(angles.x))
	out.put_16(CommandCodec.look_step(angles.y))


static func _get_direction(reader: WireReader) -> Vector3:
	var yaw := CommandCodec.yaw_from_step(reader.u16())
	var pitch := CommandCodec.look_from_step(reader.s16())
	return CommandCodec.direction_from_angles(yaw, pitch)


static func _drop(drops: NetDrops, reason: StringName) -> Variant:
	NetDrops.note(drops, reason)
	return null
