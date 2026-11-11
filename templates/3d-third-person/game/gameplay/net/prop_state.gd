class_name PropState
extends RefCounted
## Where a pushed prop (`PhysicsProp`) is, as the server sends it: in a WELCOME's table and in each
## TICK while it is awake (third-person/net-world.md#props). 11 bytes: s16 x, y, z (centimetres,
## as a player's), u32 the rotation as the smallest three of its quaternion (2 bits the index of
## the largest, 3 x 10 bits the others over -1/sqrt(2) to 1/sqrt(2): 0.16 degrees at most), u8
## flags (`ASLEEP`: it stopped and no record follows until it wakes; `JUMPED`: it was put back at
## its start, so a client does not slide it there). Plain code with no node.

const SIZE := 11
const ASLEEP := 1 << 0
const JUMPED := 1 << 1
## The steps of one of the three smaller components (10 bits).
const COMPONENT_STEPS := 1023
const COMPONENT_RANGE := 1.0 / sqrt(2.0)

var position := Vector3.ZERO
var rotation := Quaternion.IDENTITY
var asleep := false
var jumped := false


static func make(
	at: Vector3, turned: Quaternion, is_asleep := false, has_jumped := false
) -> PropState:
	var state := PropState.new()
	state.position = at
	state.rotation = turned
	state.asleep = is_asleep
	state.jumped = has_jumped
	return state


## The 11 bytes.
func write() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SIZE)
	out.encode_s16(0, CommandCodec.point_step(position.x))
	out.encode_s16(2, CommandCodec.point_step(position.y))
	out.encode_s16(4, CommandCodec.point_step(position.z))
	out.encode_u32(6, pack_rotation(rotation))
	out[10] = (ASLEEP if asleep else 0) | (JUMPED if jumped else 0)
	return out


## The state in `bytes`, or null when they are not 11.
static func read(bytes: PackedByteArray) -> PropState:
	if bytes.size() != SIZE:
		return null
	var state := PropState.new()
	state.position = Vector3(
		CommandCodec.point_from_step(bytes.decode_s16(0)),
		CommandCodec.point_from_step(bytes.decode_s16(2)),
		CommandCodec.point_from_step(bytes.decode_s16(4))
	)
	state.rotation = unpack_rotation(bytes.decode_u32(6))
	state.asleep = bytes[10] & ASLEEP != 0
	state.jumped = bytes[10] & JUMPED != 0
	return state


## A rotation in 32 bits: the index of its largest component and the other three, the sign made
## positive (q and -q are the same rotation). A rotation that is not finite is the identity.
static func pack_rotation(turned: Quaternion) -> int:
	var q := Quaternion.IDENTITY
	if turned.is_finite() and turned.length_squared() > 0.0:
		q = turned.normalized()
	var parts := PackedFloat64Array([q.x, q.y, q.z, q.w])
	var largest := 0
	for index in 4:
		if absf(parts[index]) > absf(parts[largest]):
			largest = index
	var flip := -1.0 if parts[largest] < 0.0 else 1.0
	var packed := largest
	for index in 4:
		if index == largest:
			continue
		var unit := clampf(parts[index] * flip / COMPONENT_RANGE, -1.0, 1.0)
		packed = (packed << 10) | roundi((unit + 1.0) * 0.5 * COMPONENT_STEPS)
	return packed


static func unpack_rotation(packed: int) -> Quaternion:
	var largest := (packed >> 30) & 3
	var parts := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var shift := 20
	var sum := 0.0
	for index in 4:
		if index == largest:
			continue
		var step := (packed >> shift) & COMPONENT_STEPS
		shift -= 10
		var value := (float(step) / COMPONENT_STEPS * 2.0 - 1.0) * COMPONENT_RANGE
		parts[index] = value
		sum += value * value
	parts[largest] = sqrt(maxf(1.0 - sum, 0.0))
	return Quaternion(parts[0], parts[1], parts[2], parts[3]).normalized()
