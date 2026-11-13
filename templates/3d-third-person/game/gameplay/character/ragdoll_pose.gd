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
## It reads the skeleton, not the physical bones, so it works before they exist (they are made on
## the first death), and it keeps the two ticks in arrays it made once, by bone index: a tick
## costs one read of each bone and no allocation.
##
## Only two reads on consecutive physics ticks make a velocity, and only while the last one is from
## this tick or the one before: a sampler paused for a while (the animation throttle turns
## `pose_velocity` off while it holds the tree) kept its last read, and the first read after the
## hand-back paired with it as one tick, so a death on the next tick left at the speed of seconds
## of motion: 27 m/s on a bone of a 4 m/s run (gdstudio #1388).

var _skeleton: Skeleton3D
var _names: Array[StringName] = []
var _slots: Dictionary[StringName, int] = {}
var _indices := PackedInt32Array()
var _now: Array[Transform3D] = []
var _before: Array[Transform3D] = []
var _samples := 0
# The physics tick (`Engine.get_physics_frames()`) of the last read.
var _tick := -1
var _basis := Basis.IDENTITY


## Samples the skeleton bone of each of `bodies` (`CharacterRagdoll.BODIES`: its `bone`).
func _init(bodies: Array = []) -> void:
	for entry: Dictionary in bodies:
		_slots[entry.bone] = _names.size()
		_names.append(entry.bone)
	_now.resize(_names.size())
	_before.resize(_names.size())


## Reads the pose `skeleton` has now; the one read before becomes the tick before. A new skeleton
## (the model was swapped), or a tick missed since the last read, starts the count again. Returns
## false, reading nothing, when the skeleton lacks one of the bones.
func sample(skeleton: Skeleton3D) -> bool:
	if skeleton != _skeleton and not _bind(skeleton):
		return false
	var tick := Engine.get_physics_frames()
	if tick != _tick + 1:
		_samples = 0
	_tick = tick
	var swap := _before
	_before = _now
	_now = swap
	_basis = skeleton.global_basis.orthonormalized()
	for slot in _indices.size():
		_now[slot] = skeleton.get_bone_global_pose(_indices[slot])
	_samples += 1
	return true


## True once two consecutive ticks were read from the same skeleton, the last of them this tick or
## the one before.
func is_ready() -> bool:
	return _samples >= 2 and Engine.get_physics_frames() - _tick <= 1


## Forgets what was read (the body went limp, or got up).
func clear() -> void:
	_samples = 0


## The bone `bone` in the skeleton's space at the last tick read (the bone, not its body: a caller
## puts the body's offset on it).
func now(bone: StringName) -> Transform3D:
	return _now[_slots[bone]]


## The bone `bone` in the skeleton's space one tick before the last one read.
func before(bone: StringName) -> Transform3D:
	return _before[_slots[bone]]


## The velocity the animation gave the body of `bone` (`offset` from the bone, as a
## `PhysicalBone3D.body_offset`) over the last tick of `step` seconds, against the character and
## turned to the world as the skeleton faces now: linear, then angular (radians a second). Empty
## when it moved faster than `fastest` (m/s): a jump of the pose, not a motion.
func body_velocity(
	bone: StringName, offset: Transform3D, step: float, fastest: float
) -> PackedVector3Array:
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
	_samples = 0
	_indices.resize(_names.size())
	for slot in _names.size():
		_indices[slot] = skeleton.find_bone(_names[slot])
		if _indices[slot] < 0:
			return false
	_skeleton = skeleton
	return true
