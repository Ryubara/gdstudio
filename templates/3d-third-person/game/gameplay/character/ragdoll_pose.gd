class_name RagdollPose
extends RefCounted
## Where the ragdoll's bones are in the animated pose over the last two physics ticks, in the
## skeleton's own space: what `CharacterRagdoll` samples every tick while the character is alive,
## so a death can give each body the velocity the animation gave it. The character's own motion
## is not in it: the ragdoll adds the character's velocity. A body moved every few ticks (an AI
## at the director's Reduced tier is stepped every fourth, with the missed time) jumps in world
## space, so a world sample read either no motion or four ticks of it as one, and one death in four
## of a running far AI left at four times its speed (gdstudio #1343).
##
## The pose moves when its animation runs, not on every physics tick: the character's tree runs on
## idle frames, so a slow frame is followed by two or three ticks in a row with no frame between
## them, and a throttled tree is moved every few ticks by the time it missed. A tick whose pose is
## the one read before is not a motion: the two poses kept are the last two that differed, with the
## ticks between them, so a death on any tick gets the speed the animation had (a death on a tick
## of a slow frame left with no limb speed, one on the tick after with two ticks' motion as one,
## gdstudio #1359). A pose unchanged for longer than a frame can hold ticks has stopped.
##
## It reads the skeleton, not the physical bones, so it works before they exist (they are made on
## the first death), and it keeps the poses in arrays it made once, by bone index: a tick
## costs one read of each bone and no allocation.

var _skeleton: Skeleton3D
var _names: Array[StringName] = []
var _slots: Dictionary[StringName, int] = {}
var _indices := PackedInt32Array()
var _now: Array[Transform3D] = []
var _before: Array[Transform3D] = []
var _read: Array[Transform3D] = []
var _samples := 0
var _basis := Basis.IDENTITY
# Ticks between the two poses kept, and ticks since the last one with the same pose.
var _span := 1
var _still := 0


## Samples the skeleton bone of each of `bodies` (`CharacterRagdoll.BODIES`: its `bone`).
func _init(bodies: Array = []) -> void:
	for entry: Dictionary in bodies:
		_slots[entry.bone] = _names.size()
		_names.append(entry.bone)
	_now.resize(_names.size())
	_before.resize(_names.size())
	_read.resize(_names.size())


## Reads the pose `skeleton` has now, once a physics tick; when it differs from the last one read,
## that one becomes the pose before. A new skeleton (the model was swapped) starts the count again.
## Returns false, reading nothing, when the skeleton lacks one of the bones.
func sample(skeleton: Skeleton3D) -> bool:
	if skeleton != _skeleton and not _bind(skeleton):
		return false
	_basis = skeleton.global_basis.orthonormalized()
	var moved := _samples == 0
	for slot in _indices.size():
		_read[slot] = skeleton.get_bone_global_pose(_indices[slot])
		moved = moved or _read[slot] != _now[slot]
	if not moved:
		_still += 1
		return true
	var spare := _before
	_before = _now
	_now = _read
	_read = spare
	if _samples > 0:
		_span = _still + 1
	_still = 0
	_samples += 1
	return true


## True once two different poses were read from the same skeleton.
func is_ready() -> bool:
	return _samples >= 2


## Forgets what was read (the body went limp, or got up).
func clear() -> void:
	_samples = 0
	_span = 1
	_still = 0


## The bone `bone` in the skeleton's space at the last tick read (the bone, not its body: a caller
## puts the body's offset on it).
func now(bone: StringName) -> Transform3D:
	return _now[_slots[bone]]


## The bone `bone` in the skeleton's space one tick before the last one read.
func before(bone: StringName) -> Transform3D:
	return _before[_slots[bone]]


## The ticks between the two poses kept (1 when the animation moves every tick).
func span() -> int:
	return _span


## True when the pose has not moved for longer than one frame can hold ticks
## (`Engine.max_physics_steps_per_frame`) and longer than its last motion took: it stopped.
func is_still() -> bool:
	return _still > maxi(_span, Engine.max_physics_steps_per_frame)


## The velocity the animation gave the body of `bone` (`offset` from the bone, as a
## `PhysicalBone3D.body_offset`) between the two poses kept, ticks of `step` seconds apart,
## against the character and turned to the world as the skeleton faces now: linear, then angular
## (radians a second); zero for a pose that stopped. Empty when it moved faster than `fastest`
## (m/s): a jump of the pose, not a motion.
func body_velocity(
	bone: StringName, offset: Transform3D, step: float, fastest: float
) -> PackedVector3Array:
	if is_still():
		return PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	step *= _span
	var now_at := now(bone) * offset
	var before_at := before(bone) * offset
	var linear := _basis * (now_at.origin - before_at.origin) / step
	if linear.length() > fastest:
		return PackedVector3Array()
	var turn := Quaternion(
		now_at.basis.orthonormalized() * before_at.basis.orthonormalized().inverse()
	)
	if turn.w < 0.0:
		turn = -turn
	var angular := Vector3.ZERO
	if turn.get_angle() > 0.00001:
		angular = _basis * turn.get_axis() * (turn.get_angle() / step)
	return PackedVector3Array([linear, angular])


func _bind(skeleton: Skeleton3D) -> bool:
	_skeleton = null
	clear()
	_indices.resize(_names.size())
	for slot in _names.size():
		_indices[slot] = skeleton.find_bone(_names[slot])
		if _indices[slot] < 0:
			return false
	_skeleton = skeleton
	return true
