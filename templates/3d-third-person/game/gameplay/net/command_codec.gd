class_name CommandCodec
extends RefCounted
## A `PlayerCommand` on the wire (the COMMAND layout of `NetWire`), and the steps every number is
## snapped to: a stick axis is one signed byte (1/127), a heading two bytes (a turn in 65536
## steps), a pitch two signed bytes (a quarter turn in 32767 steps either way), a point two signed
## bytes a coordinate in centimetres (`NetLimits.POSITION_RANGE` either way).
##
## Every `snap_*` is the decode of the encode, so a client that predicts with `quantized(command)`
## moves its body with exactly the numbers the server reads. Kept in a file of its own so the
## command's fields (issue #901) change here and nowhere else.

const MOVE_STEPS := 127
const TURN_STEPS := 65536
const LOOK_STEPS := 32767
const YAW_STEP := TAU / TURN_STEPS
const LOOK_STEP := (PI / 2.0) / LOOK_STEPS
const POINT_MAX := 32767

# The bits of a command's flags.
const F_SPRINT := 1 << 0
const F_WALK := 1 << 1
const F_CROUCH := 1 << 2
const F_AIM := 1 << 3
const F_FIRE := 1 << 4
const F_JUMP := 1 << 5
const F_JUMP_PRESSED := 1 << 6
const F_FIRE_PRESSED := 1 << 7
const F_INTERACT_PRESSED := 1 << 8
const F_RAGDOLL_PRESSED := 1 << 9
## A shot block follows the 15 bytes.
const F_SHOT := 1 << 10
## The weapon presses (gdstudio #887): reload, next weapon, previous weapon, the empty hands.
const F_RELOAD_PRESSED := 1 << 11
const F_NEXT_WEAPON_PRESSED := 1 << 12
const F_PREVIOUS_WEAPON_PRESSED := 1 << 13
const F_UNARMED_PRESSED := 1 << 14
## Held while lying down (gdstudio #1012).
const F_PRONE := 1 << 15
## Bits no build of this version sets: a command with one of them is refused (none are left).
const F_UNUSED := 0xFFFF & ~((F_UNARMED_PRESSED << 1) - 1) & ~F_PRONE

# --- The command ---


## The packet of a command (15 bytes, 27 with a shot block), or an empty array (counted as
## `not_finite`) when a number in it is not finite.
static func encode(command: PlayerCommand, drops: NetDrops = null) -> PackedByteArray:
	if not command.all_finite():
		NetDrops.note(drops, NetDrops.NOT_FINITE)
		return PackedByteArray()
	var out := PackedByteArray()
	out.resize(NetWire.COMMAND_SHOT_SIZE if command.has_shot else NetWire.COMMAND_SIZE)
	out[0] = NetWire.Type.COMMAND
	out.encode_u32(1, command.seq & 0xFFFFFFFF)
	var push := move_bytes(command.move)
	out.encode_s8(5, push.x)
	out.encode_s8(6, push.y)
	out.encode_u16(7, yaw_step(command.yaw))
	out.encode_s16(9, look_step(command.pitch))
	out.encode_u16(11, _flags(command))
	if command.has_shot:
		out.encode_s16(15, point_step(command.origin.x))
		out.encode_s16(17, point_step(command.origin.y))
		out.encode_s16(19, point_step(command.origin.z))
		out.encode_u16(21, yaw_step(command.shot_yaw))
		out.encode_s16(23, look_step(command.shot_pitch))
		out.encode_u16(25, command.view_tick & 0xFFFF)
	return out


## The command in a packet, or null (counted in `drops`) when the packet is not exactly one:
## 15 bytes without the shot flag, 27 with it, and no flag this version does not know. Every
## field is an integer step, so nothing decoded is a NaN or an infinity, and a move is never
## longer than 1.
static func decode(data: PackedByteArray, drops: NetDrops = null) -> PlayerCommand:
	if data.is_empty():
		NetDrops.note(drops, NetDrops.EMPTY)
		return null
	if data[0] != NetWire.Type.COMMAND:
		NetDrops.note(drops, NetDrops.UNKNOWN_TYPE)
		return null
	if data.size() < NetWire.COMMAND_SIZE:
		NetDrops.note(drops, NetDrops.TOO_SHORT)
		return null
	if data.size() > NetWire.COMMAND_SHOT_SIZE:
		NetDrops.note(drops, NetDrops.TOO_LONG)
		return null
	var flags := data.decode_u16(11)
	if flags & F_UNUSED != 0:
		NetDrops.note(drops, NetDrops.BAD_VALUE)
		return null
	var shot := flags & F_SHOT != 0
	if data.size() != (NetWire.COMMAND_SHOT_SIZE if shot else NetWire.COMMAND_SIZE):
		NetDrops.note(drops, NetDrops.WRONG_SIZE)
		return null
	var result := PlayerCommand.new()
	result.seq = data.decode_u32(1)
	result.move = move_from_bytes(data.decode_s8(5), data.decode_s8(6))
	result.yaw = yaw_from_step(data.decode_u16(7))
	result.pitch = look_from_step(data.decode_s16(9))
	result.sprint = flags & F_SPRINT != 0
	result.walk = flags & F_WALK != 0
	result.crouch = flags & F_CROUCH != 0
	result.prone = flags & F_PRONE != 0
	result.aim = flags & F_AIM != 0
	result.fire = flags & F_FIRE != 0
	result.jump = flags & F_JUMP != 0
	result.jump_pressed = flags & F_JUMP_PRESSED != 0
	result.fire_pressed = flags & F_FIRE_PRESSED != 0
	result.interact_pressed = flags & F_INTERACT_PRESSED != 0
	result.ragdoll_pressed = flags & F_RAGDOLL_PRESSED != 0
	result.reload_pressed = flags & F_RELOAD_PRESSED != 0
	result.next_weapon_pressed = flags & F_NEXT_WEAPON_PRESSED != 0
	result.previous_weapon_pressed = flags & F_PREVIOUS_WEAPON_PRESSED != 0
	result.unarmed_pressed = flags & F_UNARMED_PRESSED != 0
	result.has_shot = shot
	if shot:
		result.origin = Vector3(
			point_from_step(data.decode_s16(15)),
			point_from_step(data.decode_s16(17)),
			point_from_step(data.decode_s16(19))
		)
		result.shot_yaw = yaw_from_step(data.decode_u16(21))
		result.shot_pitch = look_from_step(data.decode_s16(23))
		result.view_tick = data.decode_u16(25)
	return result


## The command as the server will read it, or null when a number in it is not finite.
static func quantized(command: PlayerCommand) -> PlayerCommand:
	var packet := encode(command, NetDrops.new())
	return null if packet.is_empty() else decode(packet)


static func _flags(command: PlayerCommand) -> int:
	var flags := 0
	flags |= F_SPRINT if command.sprint else 0
	flags |= F_WALK if command.walk else 0
	flags |= F_CROUCH if command.crouch else 0
	flags |= F_PRONE if command.prone else 0
	flags |= F_AIM if command.aim else 0
	flags |= F_FIRE if command.fire else 0
	flags |= F_JUMP if command.jump else 0
	flags |= F_JUMP_PRESSED if command.jump_pressed else 0
	flags |= F_FIRE_PRESSED if command.fire_pressed else 0
	flags |= F_INTERACT_PRESSED if command.interact_pressed else 0
	flags |= F_RAGDOLL_PRESSED if command.ragdoll_pressed else 0
	flags |= F_SHOT if command.has_shot else 0
	flags |= F_RELOAD_PRESSED if command.reload_pressed else 0
	flags |= F_NEXT_WEAPON_PRESSED if command.next_weapon_pressed else 0
	flags |= F_PREVIOUS_WEAPON_PRESSED if command.previous_weapon_pressed else 0
	flags |= F_UNARMED_PRESSED if command.unarmed_pressed else 0
	return flags


# --- Move ---


## The two bytes of a stick push: each axis rounded to 1/127, then, if that lands outside the
## unit circle, the larger axis stepped back until it is inside (never a stronger push than the
## stick gave).
static func move_bytes(value: Vector2) -> Vector2i:
	if not value.is_finite():
		return Vector2i.ZERO
	var limited := value.limit_length(1.0)
	var bytes := Vector2i(roundi(limited.x * MOVE_STEPS), roundi(limited.y * MOVE_STEPS))
	while bytes.x * bytes.x + bytes.y * bytes.y > MOVE_STEPS * MOVE_STEPS:
		if absi(bytes.x) >= absi(bytes.y):
			bytes.x -= signi(bytes.x)
		else:
			bytes.y -= signi(bytes.y)
	return bytes


## The move two bytes mean: never longer than 1, so a hostile (127, 127) is a full push.
static func move_from_bytes(x: int, y: int) -> Vector2:
	var push := Vector2i(clampi(x, -MOVE_STEPS, MOVE_STEPS), clampi(y, -MOVE_STEPS, MOVE_STEPS))
	var bytes := move_bytes(Vector2(push) / MOVE_STEPS)
	return Vector2(bytes) / MOVE_STEPS


static func snap_move(value: Vector2) -> Vector2:
	var bytes := move_bytes(value)
	return move_from_bytes(bytes.x, bytes.y)


# --- Angles ---


## A heading (radians, any number of turns) as a step of the 65536 round a circle.
static func yaw_step(yaw: float) -> int:
	if not is_finite(yaw):
		return 0
	return posmod(roundi(yaw / YAW_STEP), TURN_STEPS)


## The heading a step means, in [-PI, PI).
static func yaw_from_step(step: int) -> float:
	var wrapped := posmod(step, TURN_STEPS)
	return (wrapped if wrapped < TURN_STEPS / 2 else wrapped - TURN_STEPS) * YAW_STEP


static func snap_yaw(yaw: float) -> float:
	return yaw_from_step(yaw_step(yaw))


## A pitch (radians, held to a quarter turn either way) as a signed step.
static func look_step(pitch: float) -> int:
	if not is_finite(pitch):
		return 0
	return roundi(clampf(pitch, -PI / 2.0, PI / 2.0) / LOOK_STEP)


static func look_from_step(step: int) -> float:
	return clampi(step, -LOOK_STEPS, LOOK_STEPS) * LOOK_STEP


static func snap_pitch(pitch: float) -> float:
	return look_from_step(look_step(pitch))


# --- Points and directions ---


## A coordinate in metres as centimetres, held to `NetLimits.POSITION_RANGE`.
static func point_step(metres: float) -> int:
	if not is_finite(metres):
		return 0
	return clampi(roundi(metres * NetLimits.POSITION_STEPS_PER_METRE), -POINT_MAX, POINT_MAX)


static func point_from_step(step: int) -> float:
	return clampi(step, -POINT_MAX, POINT_MAX) / NetLimits.POSITION_STEPS_PER_METRE


static func snap_point(value: Vector3) -> Vector3:
	return Vector3(
		point_from_step(point_step(value.x)),
		point_from_step(point_step(value.y)),
		point_from_step(point_step(value.z))
	)


## The heading and pitch of a direction (0 and 0 face -Z, as the camera's do).
static func direction_angles(direction: Vector3) -> Vector2:
	if not direction.is_finite() or direction.length() < 0.001:
		return Vector2.ZERO
	var unit := direction.normalized()
	return Vector2(atan2(-unit.x, -unit.z), asin(clampf(unit.y, -1.0, 1.0)))


## The unit direction a heading and a pitch make.
static func direction_from_angles(yaw: float, pitch: float) -> Vector3:
	var flat := cos(pitch)
	return Vector3(-sin(yaw) * flat, sin(pitch), -cos(yaw) * flat)
