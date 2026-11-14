class_name PeekModifier
extends SkeletonModifier3D
## Bends the hips, the spine and the neck to one side after the clips, for the peek lean
## (gdstudio #1400): each bone of `chain` turns its share of one roll about the way the model
## faces, so the upper body tilts from the hips; the bones in `keep` (the thighs) are turned back
## by the turn above them, so the pelvis stays where it is and the legs keep the clips' pose. The
## roll is solved so the head bone goes `shift` to the side (in the world's axes, metres), the
## same shift the body's eye point and its shape take in the step, so what a shot meets and what
## the camera sees agree with what is drawn. A second pass corrects the first's guess. Each bone is
## written once. `PeekLayer` makes it and sets `angle` and `shift`; at 0 it is off.

## The bones that bend by default, from the hips up.
const CHAIN: Array[StringName] = [&"pelvis", &"spine_01", &"spine_02", &"spine_03", &"neck_01"]

## The bones that bend, from the hips up, and each one's share of the roll (adding up to 1).
@export var chain: Array[StringName] = CHAIN.duplicate():
	set(value):
		chain = value
		_bones.clear()
@export var weights := PackedFloat32Array([0.2, 0.25, 0.25, 0.18, 0.12])
## Children of the chain's first bone that keep their turn in the world (the legs, under the
## pelvis): the pelvis tilts, the thighs do not.
@export var keep: Array[StringName] = [&"thigh_l", &"thigh_r"]:
	set(value):
		keep = value
		_bones.clear()
## The bone whose place the roll is solved for.
@export var head: StringName = &"Head":
	set(value):
		head = value
		_bones.clear()
## The roll's first guess, radians, positive to the model's right (its -X).
var angle := 0.0
## Where the head should go from where the clips put it, in the skeleton's parent's space (the
## world's axes, metres).
var shift := Vector3.ZERO
## The way the body faces, in the world's axes: the roll is about it.
var facing := Vector3.BACK
## The roll the last update used, radians (for a test).
var solved_angle := 0.0

var _bones: PackedInt32Array = []
var _kept: PackedInt32Array = []
var _head := -1


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_bones.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or is_zero_approx(angle) or not _find(skeleton):
		solved_angle = 0.0
		return
	var parent := skeleton.get_bone_parent(_bones[0])
	var base := skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var locals: Array[Transform3D] = []
	for bone in _bones:
		locals.append(skeleton.get_bone_pose(bone))
	var head_local := skeleton.get_bone_pose(_head)
	var to_skeleton := skeleton.global_basis.inverse()
	# The skeleton's axes may be turned and scaled inside the model.
	var forward := (to_skeleton * facing).normalized()
	var wanted := to_skeleton * shift
	var upright := _head_at(base, locals, head_local)
	var roll := angle
	for _pass in 2:
		var moved := _head_at(base, _rolled(base, locals, forward, roll), head_local) - upright
		var along := moved.dot(wanted.normalized()) if wanted.length() > 0.0001 else 0.0
		if absf(along) < 0.0001:
			break
		roll *= clampf(wanted.length() / along, 0.25, 4.0)
	roll = clampf(roll, -PI / 2.0, PI / 2.0)
	var bent := _rolled(base, locals, forward, roll)
	for index in _bones.size():
		skeleton.set_bone_pose_rotation(
			_bones[index], bent[index].basis.orthonormalized().get_rotation_quaternion()
		)
	# The first bone's turn taken back from the bones that keep theirs.
	var undo := bent[0].basis.orthonormalized().inverse() * locals[0].basis.orthonormalized()
	for bone in _kept:
		var local := skeleton.get_bone_pose(bone)
		var spin := (undo * local.basis.orthonormalized()).get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(bone, spin)
		skeleton.set_bone_pose_position(bone, undo * local.origin)
	solved_angle = roll


# The chain's local poses with each bone turned its share of `roll` about `axis` (skeleton space).
func _rolled(
	base: Transform3D, locals: Array[Transform3D], axis: Vector3, roll: float
) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var above := base
	for index in locals.size():
		var share := weights[index] if index < weights.size() else 0.0
		var local := locals[index]
		if share != 0.0:
			var part := Basis(axis, roll * share)
			var posed := above.basis.orthonormalized() * local.basis.orthonormalized()
			var turned := above.basis.orthonormalized().inverse() * part * posed
			var spin := turned.orthonormalized().get_rotation_quaternion()
			local = Transform3D(Basis(spin).scaled(local.basis.get_scale()), local.origin)
		result.append(local)
		above = above * local
	return result


func _head_at(base: Transform3D, locals: Array[Transform3D], head_local: Transform3D) -> Vector3:
	var at := base
	for local in locals:
		at = at * local
	return (at * head_local).origin


# The chain's bones (each the child of the one before) and the head under the last.
func _find(skeleton: Skeleton3D) -> bool:
	if not _bones.is_empty():
		return _head >= 0
	for bone_name in chain:
		var found := skeleton.find_bone(bone_name)
		if found < 0 or (not _bones.is_empty() and skeleton.get_bone_parent(found) != _bones[-1]):
			_bones.clear()
			return false
		_bones.append(found)
	_head = skeleton.find_bone(head)
	if _bones.is_empty() or _head < 0 or skeleton.get_bone_parent(_head) != _bones[-1]:
		_bones.clear()
		_head = -1
		return false
	_kept.clear()
	for bone_name in keep:
		var found := skeleton.find_bone(bone_name)
		if found >= 0 and skeleton.get_bone_parent(found) == _bones[0]:
			_kept.append(found)
	return true
