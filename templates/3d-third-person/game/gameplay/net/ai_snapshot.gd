class_name AiSnapshot
extends RefCounted
## The AI characters as bytes, at the end of every TICK (gdstudio #970): what each client needs to
## draw them, compact, and a delta against the snapshot it already holds. The server builds one
## block a client (`encode`, from that client's `AiPeerView` and the `AiTierRates`); a client
## keeps an `AiSnapshot` and applies each block to it (`apply`). Plain code with no node.
##
## A block, little-endian:
##
##   u8 mode (`Mode`)
##   NONE   nothing changed for this client                                         1 byte
##   FULL   u8 seq, u16 count, the rows: the whole population within the interest
##          radius; the client drops every character it is not in                 4 + 14 n
##   DELTA  u8 seq, u8 base (the seq it applies on), u16 count, the rows that
##          changed, u16 move count, the moves, u16 gone count, the ids that
##          left                                               9 + 14 n + 8 moves + 2 gone
##
## A row (`AiRow`): u16 id, s16 x/y/z (cm from the section's origin), u8 yaw (256 steps), u8 speed
## (0.05 m/s), u8 mode (bits 0-2 the situation, 3-6 the body's state, 7 aiming), u16 target (a
## HIT's id, `NO_TARGET`), u8 variant. 14 bytes.
##
## A move: a held character whose target and look did not change and whose place moved at most
## 1.27 m each way: u16 id, s8 x/y/z (cm from the place held), u8 yaw, u8 speed, u8 mode. 8 bytes:
## a walking crowd costs little more than half what its rows would.
##
## Limits, pinned by `test_net_ai_snapshot.gd`: an id past `NetLimits.MAX_AI_ID` or a number that
## is not finite is refused (the block is not made); a position past
## `NetLimits.POSITION_RANGE` from the origin is held at the edge; a speed past 12.75 m/s is held
## at it; a situation past 7 or a state past 15 is refused. The decoder checks every count against
## the bytes left before it reads, refuses a repeated id, and refuses a delta whose base is not the
## sequence it holds (`NetDrops.NO_BASELINE`), keeping what it had until a full snapshot comes.

enum Mode { NONE = 0, FULL = 1, DELTA = 2 }

const ROW_SIZE := 14
const MOVE_SIZE := 8
const NONE_SIZE := 1
const FULL_HEADER := 4
## The header, the move count and the gone count.
const DELTA_HEADER := 9
## The most centimetres a move carries each way.
const MOVE_REACH := 127
## Numbers a move takes in `Block.moves`: id, x, y, z, yaw step, speed step, mode.
const MOVE_FIELDS := 7
const MAX_BLOCK := DELTA_HEADER + NetLimits.MAX_AI_ROWS * (ROW_SIZE + 2)
const YAW_STEPS := 256
const SPEED_STEP := 0.05
const MAX_SPEED := 255 * SPEED_STEP
const NO_TARGET := 0xFFFF
const SITUATION_BITS := 0x07
const STATE_SHIFT := 3
const STATE_BITS := 0x0F
const AIM_BIT := 0x80

## The sequence of the snapshot held, -1 before the first full one.
var seq := -1
## The characters held, by id.
var rows: Dictionary[int, AiRow] = {}
## After an `apply`: the ids it added or changed, and the ids it took out.
var changed: Array[int] = []
var gone: Array[int] = []
## Blocks applied and refused (a delta with no baseline) since the start.
var applied := 0
var refused := 0


## A block, read.
class Block:
	extends RefCounted
	var mode := Mode.NONE
	var seq := 0
	var base := 0
	var rows: Array[AiRow] = []
	## `MOVE_FIELDS` numbers a move: id, x, y, z (cm), yaw step, speed step, mode.
	var moves: PackedInt32Array = PackedInt32Array()
	var gone: PackedInt32Array = PackedInt32Array()


# --- The server's side ---


## The block for one client: `characters` are the rows of every character the server sends (each
## with its id, in metres from the section's origin), `view` what that client holds (changed
## here, as if the block arrived), `rates` the tiers, `tick` the server tick. Full when the client
## holds nothing, a keyframe is due, or `full` is asked; a delta of what is due and changed
## otherwise; NONE when nothing is. Rows that cannot travel are left out and counted in `drops`.
static func encode(
	characters: Array[AiRow],
	view: AiPeerView,
	rates: AiTierRates,
	tick: int,
	drops: NetDrops = null,
	full := false
) -> PackedByteArray:
	var keyframe := rates.keyframe_ticks()
	var make_full := (
		full or not view.has_baseline() or (keyframe > 0 and tick - view.full_tick >= keyframe)
	)
	var intervals := PackedInt32Array(
		[
			rates.interval_ticks(AiTierRates.Tier.FULL),
			rates.interval_ticks(AiTierRates.Tier.REDUCED),
			rates.interval_ticks(AiTierRates.Tier.DORMANT),
		]
	)
	var full_reach := rates.full_radius * rates.full_radius
	var reduced_reach := rates.reduced_radius * rates.reduced_radius
	var interest := rates.interest_radius * rates.interest_radius
	# Who is in this client's interest, nearest first when there are more than it may hold.
	var wanted: Array[AiRow] = []
	var tiers: Dictionary[int, int] = {}
	for row in characters:
		var away := row.position.distance_squared_to(view.viewer)
		if away > interest:
			continue
		tiers[row.id] = 0 if away <= full_reach else (1 if away <= reduced_reach else 2)
		wanted.append(row)
	var limit := mini(view.cap, NetLimits.MAX_AI_ROWS)
	if wanted.size() > limit:
		var viewer := view.viewer
		wanted.sort_custom(
			func(a: AiRow, b: AiRow) -> bool:
				return (
					a.position.distance_squared_to(viewer) < b.position.distance_squared_to(viewer)
				)
		)
		wanted.resize(limit)
	var bytes_of: Dictionary[int, PackedByteArray] = {}
	for row in wanted:
		var bytes := row.bytes if not row.bytes.is_empty() else row_bytes(row, drops)
		if not bytes.is_empty():
			bytes_of[row.id] = bytes
	if make_full:
		return _full(view, bytes_of, tick)
	var out_rows: Array[int] = []
	var out_moves: Array[int] = []
	for id: int in bytes_of:
		var held: PackedByteArray = view.sent.get(id, PackedByteArray())
		if held.is_empty():
			out_rows.append(id)
			continue
		if tick - int(view.sent_tick.get(id, 0)) < intervals[tiers[id]]:
			continue
		var bytes := bytes_of[id]
		if held == bytes:
			continue
		if _is_move(held, bytes):
			out_moves.append(id)
		else:
			out_rows.append(id)
	var left: Array[int] = []
	for id: int in view.sent:
		if not bytes_of.has(id):
			left.append(id)
	if out_rows.is_empty() and out_moves.is_empty() and left.is_empty():
		return PackedByteArray([Mode.NONE])
	var out := StreamPeerBuffer.new()
	var base := view.seq
	view.seq = (view.seq + 1) & 0xFF
	out.put_u8(Mode.DELTA)
	out.put_u8(view.seq)
	out.put_u8(base)
	out.put_u16(out_rows.size())
	for id in out_rows:
		out.put_data(bytes_of[id])
		view.sent[id] = bytes_of[id]
		view.sent_tick[id] = tick
	out.put_u16(out_moves.size())
	for id in out_moves:
		var held: PackedByteArray = view.sent[id]
		var bytes := bytes_of[id]
		out.put_u16(id)
		for at in [2, 4, 6]:
			out.put_8(bytes.decode_s16(at) - held.decode_s16(at))
		out.put_u8(bytes[8])
		out.put_u8(bytes[9])
		out.put_u8(bytes[10])
		view.sent[id] = bytes
		view.sent_tick[id] = tick
	out.put_u16(left.size())
	for id in left:
		out.put_u16(id)
		view.sent.erase(id)
		view.sent_tick.erase(id)
	return out.data_array


# Whether a move can carry what changed from `held` to `bytes`: the place within `MOVE_REACH` cm
# each way, the yaw, the speed and the mode; the target and the look the same.
static func _is_move(held: PackedByteArray, bytes: PackedByteArray) -> bool:
	for at in range(11, ROW_SIZE):
		if held[at] != bytes[at]:
			return false
	for at in [2, 4, 6]:
		if absi(bytes.decode_s16(at) - held.decode_s16(at)) > MOVE_REACH:
			return false
	return true


static func _full(
	view: AiPeerView, bytes_of: Dictionary[int, PackedByteArray], tick: int
) -> PackedByteArray:
	view.sent.clear()
	view.sent_tick.clear()
	view.seq = (maxi(view.seq, -1) + 1) & 0xFF
	view.full_tick = tick
	var out := StreamPeerBuffer.new()
	out.put_u8(Mode.FULL)
	out.put_u8(view.seq)
	out.put_u16(bytes_of.size())
	for id: int in bytes_of:
		out.put_data(bytes_of[id])
		view.sent[id] = bytes_of[id]
		view.sent_tick[id] = tick
	return out.data_array


## The 14 bytes of `row`, or an empty array (counted in `drops`) when it cannot travel.
static func row_bytes(row: AiRow, drops: NetDrops = null) -> PackedByteArray:
	var reason := _row_fault(row)
	if reason != &"":
		NetDrops.note(drops, reason)
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(ROW_SIZE)
	out.encode_u16(0, row.id)
	out.encode_s16(2, CommandCodec.point_step(row.position.x))
	out.encode_s16(4, CommandCodec.point_step(row.position.y))
	out.encode_s16(6, CommandCodec.point_step(row.position.z))
	out[8] = yaw_step(row.yaw)
	out[9] = speed_step(row.speed)
	out[10] = (row.situation | (row.state << STATE_SHIFT) | (AIM_BIT if row.aiming else 0))
	out.encode_u16(11, row.target)
	out[13] = row.variant
	return out


## The row as a client reads it (the decode of the encode), or null when it cannot travel.
static func snap_row(row: AiRow) -> AiRow:
	var bytes := row_bytes(row, NetDrops.new())
	return null if bytes.is_empty() else read_row(WireReader.new(bytes))


static func _row_fault(row: AiRow) -> StringName:
	if not row.all_finite():
		return NetDrops.NOT_FINITE
	if row.id < 0 or row.id > NetLimits.MAX_AI_ID:
		return NetDrops.BAD_VALUE
	if row.situation < 0 or row.situation > SITUATION_BITS:
		return NetDrops.BAD_VALUE
	if row.state < 0 or row.state > STATE_BITS:
		return NetDrops.BAD_VALUE
	if row.target < 0 or row.target > 0xFFFF or row.variant < 0 or row.variant > 0xFF:
		return NetDrops.BAD_VALUE
	return &""


static func yaw_step(yaw: float) -> int:
	return roundi(wrapf(yaw, 0.0, TAU) / TAU * YAW_STEPS) % YAW_STEPS


static func yaw_from_step(step: int) -> float:
	return wrapf(step * TAU / YAW_STEPS, -PI, PI)


static func speed_step(speed: float) -> int:
	return clampi(roundi(speed / SPEED_STEP), 0, 255)


# --- Reading ---


## Reads one row (the caller checked that `ROW_SIZE` bytes are left).
static func read_row(reader: WireReader) -> AiRow:
	var row := AiRow.new()
	row.id = reader.u16()
	var x := CommandCodec.point_from_step(reader.s16())
	var y := CommandCodec.point_from_step(reader.s16())
	var z := CommandCodec.point_from_step(reader.s16())
	row.position = Vector3(x, y, z)
	row.yaw = yaw_from_step(reader.u8())
	row.speed = reader.u8() * SPEED_STEP
	var mode := reader.u8()
	row.situation = mode & SITUATION_BITS
	row.state = (mode >> STATE_SHIFT) & STATE_BITS
	row.aiming = mode & AIM_BIT != 0
	row.target = reader.u16()
	row.variant = reader.u8()
	return row


## Reads a block from `reader` (the rest of a TICK), or null (counted in `drops`): an unknown mode,
## a count past the bytes left or past `NetLimits.MAX_AI_ROWS`, an id past `NetLimits.MAX_AI_ID`
## or twice in one block.
static func read_block(reader: WireReader, drops: NetDrops = null) -> Block:
	var block := Block.new()
	var mode := reader.u8()
	if not reader.ok:
		return _drop(drops, NetDrops.COUNT_PAST_END)
	if mode == Mode.NONE:
		return block
	if mode != Mode.FULL and mode != Mode.DELTA:
		return _drop(drops, NetDrops.BAD_VALUE)
	block.mode = mode as Mode
	block.seq = reader.u8()
	if mode == Mode.DELTA:
		block.base = reader.u8()
	var count := reader.u16()
	if not reader.ok:
		return _drop(drops, NetDrops.COUNT_PAST_END)
	if count > NetLimits.MAX_AI_ROWS:
		return _drop(drops, NetDrops.TOO_MANY)
	if count * ROW_SIZE > reader.left():
		return _drop(drops, NetDrops.COUNT_PAST_END)
	var seen: Dictionary[int, bool] = {}
	for _index in count:
		var row := read_row(reader)
		if row.id > NetLimits.MAX_AI_ID or seen.has(row.id):
			return _drop(drops, NetDrops.BAD_VALUE)
		seen[row.id] = true
		block.rows.append(row)
	if mode == Mode.DELTA:
		var move_count := reader.u16()
		if not reader.ok:
			return _drop(drops, NetDrops.COUNT_PAST_END)
		if move_count > NetLimits.MAX_AI_ROWS:
			return _drop(drops, NetDrops.TOO_MANY)
		if move_count * MOVE_SIZE > reader.left():
			return _drop(drops, NetDrops.COUNT_PAST_END)
		for _index in move_count:
			var id := reader.u16()
			if id > NetLimits.MAX_AI_ID or seen.has(id):
				return _drop(drops, NetDrops.BAD_VALUE)
			seen[id] = true
			block.moves.append_array(
				[id, reader.s8(), reader.s8(), reader.s8(), reader.u8(), reader.u8(), reader.u8()]
			)
		var gone_count := reader.u16()
		if not reader.ok:
			return _drop(drops, NetDrops.COUNT_PAST_END)
		if gone_count > NetLimits.MAX_AI_ROWS:
			return _drop(drops, NetDrops.TOO_MANY)
		if gone_count * 2 > reader.left():
			return _drop(drops, NetDrops.COUNT_PAST_END)
		for _index in gone_count:
			var id := reader.u16()
			if id > NetLimits.MAX_AI_ID or seen.has(id):
				return _drop(drops, NetDrops.BAD_VALUE)
			seen[id] = true
			block.gone.append(id)
	return block


## The block in `data` alone (a test's), or null.
static func read(data: PackedByteArray, drops: NetDrops = null) -> Block:
	var reader := WireReader.new(data)
	var block := read_block(reader, drops)
	if block != null and reader.left() != 0:
		return _drop(drops, NetDrops.TOO_LONG)
	return block


# --- The client's side ---


## Applies a block to what this client holds; `changed` and `gone` say what it did. Answers false
## (counted in `drops`) for a delta whose base is not the sequence held: nothing changes until a
## full snapshot comes. A NONE block changes nothing and answers true.
func apply(block: Block, drops: NetDrops = null) -> bool:
	changed.clear()
	gone.clear()
	if block == null:
		return false
	match block.mode:
		Mode.NONE:
			return true
		Mode.FULL:
			var kept: Dictionary[int, bool] = {}
			for row in block.rows:
				kept[row.id] = true
			for id: int in rows.keys():
				if not kept.has(id):
					rows.erase(id)
					gone.append(id)
		Mode.DELTA:
			if seq < 0 or block.base != seq or not _holds_moved(block):
				refused += 1
				NetDrops.note(drops, NetDrops.NO_BASELINE)
				return false
			_apply_moves(block)
			for id in block.gone:
				if rows.has(id):
					rows.erase(id)
					gone.append(id)
	for row in block.rows:
		rows[row.id] = row
		changed.append(row.id)
	seq = block.seq
	applied += 1
	return true


# Whether every character a delta moves is held (a move is from the place held).
func _holds_moved(block: Block) -> bool:
	for at in range(0, block.moves.size(), MOVE_FIELDS):
		if not rows.has(block.moves[at]):
			return false
	return true


# Each move, from the held place in whole centimetres, as the server's held bytes moved.
func _apply_moves(block: Block) -> void:
	for at in range(0, block.moves.size(), MOVE_FIELDS):
		var id := block.moves[at]
		var row: AiRow = rows[id].copy()
		row.position = Vector3(
			_moved(row.position.x, block.moves[at + 1]),
			_moved(row.position.y, block.moves[at + 2]),
			_moved(row.position.z, block.moves[at + 3])
		)
		row.yaw = yaw_from_step(block.moves[at + 4])
		row.speed = block.moves[at + 5] * SPEED_STEP
		var mode := block.moves[at + 6]
		row.situation = mode & SITUATION_BITS
		row.state = (mode >> STATE_SHIFT) & STATE_BITS
		row.aiming = mode & AIM_BIT != 0
		rows[id] = row
		changed.append(id)


# A held place `by` centimetres on, in whole centimetres.
static func _moved(metres: float, by: int) -> float:
	return CommandCodec.point_from_step(CommandCodec.point_step(metres) + by)


## Applies the bytes of one block (a test's).
func apply_bytes(data: PackedByteArray, drops: NetDrops = null) -> bool:
	return apply(read(data, drops), drops)


## Forgets everything held (the client left).
func clear() -> void:
	seq = -1
	rows.clear()
	changed.clear()
	gone.clear()


static func _drop(drops: NetDrops, reason: StringName) -> Variant:
	NetDrops.note(drops, reason)
	return null
