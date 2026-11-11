class_name RagdollPose
extends RefCounted
## Where the ragdoll's bones are in the animated pose over the last two physics ticks, in world
## space: what `CharacterRagdoll` samples every tick while the character is alive, so a death can
## give each body the velocity the animation gave it.
##
## It reads the skeleton, not the physical bones, so it works before they exist (they are made on
## the first death), and it keeps the two ticks in arrays it made once, by bone index: a tick
## costs one read of each bone and no allocation.

var _skeleton: Skeleton3D
var _names: Array[StringName] = []
var _slots: Dictionary[StringName, int] = {}
var _indices := PackedInt32Array()
var _now: Array[Transform3D] = []
var _before: Array[Transform3D] = []
var _samples := 0


## Samples the skeleton bone of each of `bodies` (`CharacterRagdoll.BODIES`: its `bone`).
func _init(bodies: Array = []) -> void:
	for entry: Dictionary in bodies:
		_slots[entry.bone] = _names.size()
		_names.append(entry.bone)
	_now.resize(_names.size())
	_before.resize(_names.size())


## Reads the pose `skeleton` has now; the one read before becomes the tick before. A new skeleton
## (the model was swapped) starts the count again. Returns false, reading nothing, when the
## skeleton lacks one of the bones.
func sample(skeleton: Skeleton3D) -> bool:
	if skeleton != _skeleton and not _bind(skeleton):
		return false
	var swap := _before
	_before = _now
	_now = swap
	var at := skeleton.global_transform
	for slot in _indices.size():
		_now[slot] = at * skeleton.get_bone_global_pose(_indices[slot])
	_samples += 1
	return true


## True once two ticks were read from the same skeleton.
func is_ready() -> bool:
	return _samples >= 2


## Forgets what was read (the body went limp, or got up).
func clear() -> void:
	_samples = 0


## The bone `bone` in world space at the last tick read (the bone, not its body: a caller puts
## the body's offset on it).
func now(bone: StringName) -> Transform3D:
	return _now[_slots[bone]]


## The bone `bone` in world space one tick before the last one read.
func before(bone: StringName) -> Transform3D:
	return _before[_slots[bone]]


## The velocity the animation gave the body of `bone` (`offset` from the bone, as a
## `PhysicalBone3D.body_offset`) over the last tick of `step` seconds: linear, then angular
## (radians a second). Empty when it moved faster than `fastest` (m/s): a jump of the character,
## not a motion.
func body_velocity(
	bone: StringName, offset: Transform3D, step: float, fastest: float
) -> PackedVector3Array:
	var now_at := now(bone) * offset
	var before_at := before(bone) * offset
	var linear := (now_at.origin - before_at.origin) / step
	if linear.length() > fastest:
		return PackedVector3Array()
	var turn := Quaternion(
		now_at.basis.orthonormalized() * before_at.basis.orthonormalized().inverse()
	)
	if turn.w < 0.0:
		turn = -turn
	var angular := Vector3.ZERO
	if turn.get_angle() > 0.00001:
		angular = turn.get_axis() * (turn.get_angle() / step)
	return PackedVector3Array([linear, angular])


func _bind(skeleton: Skeleton3D) -> bool:
	_skeleton = null
	_samples = 0
	_indices.resize(_names.size())
	for slot in _names.size():
		_indices[slot] = skeleton.find_bone(_names[slot])
		if _indices[slot] < 0:
			return false
	_skeleton = skeleton
	return true
