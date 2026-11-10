class_name HitRecord
extends RefCounted
## One hit on a character: how much damage, which body part, where and which way, how hard. It is
## the whole of what a game's networking sends for a hit: every peer gives it to its own copy of
## the character (`Character.take_hit()`), which takes the damage and makes the flinch, the
## death push or the push on a lying body itself, so a ragdoll or a flinch is never sent.
##
## `encode()` packs the sent part into a few bytes and `decode()` reads it back; `source`,
## `knockback` and `killed` stay on the peer that made the record.

## The damage, with the zone's multiplier already applied (0: a push and no harm).
var damage := 0.0
## The hit zone's name (`&"head"`, `&"chest"`, ...), empty when the hit found no zone (a body
## with no hit zones, a lying body).
var zone: StringName = &""
## The skeleton bone that was hit (`&"Head"`, `&"spine_03"`, ...): the ragdoll body that is
## pushed. Empty: the body is hit as a whole.
var bone: StringName = &""
## Where the hit landed, world space, metres; `Vector3.INF` when it has no point (a blow).
var point := Vector3.INF
## The way the hit travelled (length 1), or zero for a blow with no direction.
var direction := Vector3.ZERO
## How hard it pushes, newton seconds (a shot's impulse).
var strength := 0.0
## Who or what hit (the shooter). Local only, never sent.
var source: Node3D
## On: the old blow (`Character.hit(amount, source)`): it stops the character for the tuning's
## `hit_stun_time` and throws it away from `source`. A shot leaves it off. Local only.
var knockback := false
## Set by the character when this hit killed it. Local only: each peer finds it from its own
## health.
var killed := false


## A shot that landed on `zone` (its `bone`) at `at`, travelling along `along`.
static func shot(
	amount: float,
	zone_name: StringName,
	bone_name: StringName,
	at: Vector3,
	along: Vector3,
	push: float,
	by: Node3D = null
) -> HitRecord:
	var record := HitRecord.new()
	record.damage = amount
	record.zone = zone_name
	record.bone = bone_name
	record.point = at
	record.direction = along.normalized() if along.length_squared() > 0.0 else Vector3.ZERO
	record.strength = push
	record.source = by
	return record


## A blow of `amount` from `by` with no point (what `Character.hit(amount, source)` makes): it
## stops and throws the character as hits always did.
static func blow(amount: float, by: Node3D = null) -> HitRecord:
	var record := HitRecord.new()
	record.damage = amount
	record.source = by
	record.knockback = true
	return record


## True when the hit has a point and a direction (a shot), so it can push a body part.
func has_point() -> bool:
	return point.is_finite() and not direction.is_zero_approx()


## The sent part as bytes: damage and strength (f32), the point and the direction (3 x f32
## each), the zone and the bone (a length byte and UTF-8, up to 255 bytes each). About 40 bytes
## for a shot on the head.
func encode() -> PackedByteArray:
	var bytes := PackedByteArray()
	var zone_bytes := String(zone).to_utf8_buffer().slice(0, 255)
	var bone_bytes := String(bone).to_utf8_buffer().slice(0, 255)
	bytes.resize(32 + 2 + zone_bytes.size() + bone_bytes.size())
	bytes.encode_float(0, damage)
	bytes.encode_float(4, strength)
	var at := point if point.is_finite() else Vector3(INF, INF, INF)
	for axis in 3:
		bytes.encode_float(8 + axis * 4, at[axis])
		bytes.encode_float(20 + axis * 4, direction[axis])
	bytes[32] = zone_bytes.size()
	var cursor := 33
	for index in zone_bytes.size():
		bytes[cursor + index] = zone_bytes[index]
	cursor += zone_bytes.size()
	bytes[cursor] = bone_bytes.size()
	cursor += 1
	for index in bone_bytes.size():
		bytes[cursor + index] = bone_bytes[index]
	return bytes


## The record `encode()` made, or null when `bytes` is too short or a number is not finite where
## it must be.
static func decode(bytes: PackedByteArray) -> HitRecord:
	if bytes.size() < 34:
		return null
	var record := HitRecord.new()
	record.damage = bytes.decode_float(0)
	record.strength = bytes.decode_float(4)
	var at := Vector3.ZERO
	var along := Vector3.ZERO
	for axis in 3:
		at[axis] = bytes.decode_float(8 + axis * 4)
		along[axis] = bytes.decode_float(20 + axis * 4)
	if not (is_finite(record.damage) and is_finite(record.strength) and along.is_finite()):
		return null
	record.point = at if at.is_finite() else Vector3.INF
	record.direction = along.normalized() if along.length_squared() > 0.0001 else Vector3.ZERO
	var zone_size := bytes[32]
	var cursor := 33
	if bytes.size() < cursor + zone_size + 1:
		return null
	record.zone = StringName(bytes.slice(cursor, cursor + zone_size).get_string_from_utf8())
	cursor += zone_size
	var bone_size := bytes[cursor]
	cursor += 1
	if bytes.size() < cursor + bone_size:
		return null
	record.bone = StringName(bytes.slice(cursor, cursor + bone_size).get_string_from_utf8())
	return record
