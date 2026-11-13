class_name AimUprightModifier
extends SkeletonModifier3D
## Stands the chest up while the character aims a weapon the aim offset does not turn (kit
## #1351): the fists, which have no muzzle. Our crouch idle folds the trunk so the chest
## (`spine_03`) leans about 81 degrees forward, which suits a body ducking low; aiming from it, the
## head dropped to the bottom of the shoulder camera's frame. A weapon with a muzzle has its chest
## stood up by the aim clips and the aim offset (`AimOffsetModifier`: 16 to 29 degrees crouched);
## this does the same for the rest, without clips.
##
## It reads the chest's line (from `spine_03` to the neck) in this very update and, where it leans
## forward more than `max_lean` about the model's side axis, turns the chain back by the
## difference, each bone by its share about the same axis, so the shares add up to it exactly and
## the head, the arms and the hands ride along. Each bone is written once, so `influence` fades
## the turn. A chest leaning back or less than `max_lean` is left as it is. It reads no clock.

## The bones that turn, from the hips up (each turns its share in the skeleton's space).
@export var chain: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]:
	set(value):
		chain = value
		_bones.clear()
## Each bone's share of the turn, in the order of `chain`; they should add up to 1.
@export var weights := PackedFloat32Array([0.3, 0.3, 0.4])
## The bones that keep the way they point in the model's space while the chest stands up (the
## upper arms): the crouch's arms hang toward the knees, and turned back with the chest they
## swung out and up, a hand by the face.
@export var steady: Array[StringName] = [&"upperarm_l", &"upperarm_r"]:
	set(value):
		steady = value
		_bones.clear()
## The most the chest may lean forward off upright, in degrees.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var max_lean := 30.0

## The turn back of the last update, in degrees, before `influence` (0: the chest was upright
## enough).
var turn := 0.0

var _bones := PackedInt32Array()
var _neck := -1
var _steady := PackedInt32Array()


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_bones.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	turn = 0.0
	if skeleton == null or not _find_bones(skeleton):
		return
	var last := _bones[_bones.size() - 1]
	var chest := HandPoseModifier.global_pose(skeleton, last)
	var line := chest.basis * skeleton.get_bone_pose_position(_neck)
	# The model faces +Z: a chest leaning forward has its neck ahead of it.
	var lean := rad_to_deg(atan2(line.z, line.y))
	if lean <= max_lean:
		return
	turn = lean - max_lean
	var back := -deg_to_rad(turn)
	# Each bone turns by its share about the same axis, so the turns above it and its own add up
	# in the skeleton's space: its new local turn is its old global turn turned by its own share,
	# put back on its parent's old global turn (the parent's own turn cancels out).
	var globals: Array[Quaternion] = []
	var parents: Array[Quaternion] = []
	var above := Quaternion.IDENTITY
	var parent := skeleton.get_bone_parent(_bones[0])
	if parent >= 0:
		above = HandPoseModifier.global_pose(skeleton, parent).basis.get_rotation_quaternion()
	# The chain is one line of bones, each the parent of the next.
	for bone in _bones:
		parents.append(above)
		above = above * skeleton.get_bone_pose_rotation(bone)
		globals.append(above)
	# The steady bones' old global turns and their parents', read before the chain is written.
	var steady_globals: Array[Quaternion] = []
	var steady_parents: Array[Quaternion] = []
	for bone in _steady:
		var parent_pose := HandPoseModifier.global_pose(skeleton, skeleton.get_bone_parent(bone))
		var parent_turn := parent_pose.basis.get_rotation_quaternion()
		steady_parents.append(parent_turn)
		steady_globals.append(parent_turn * skeleton.get_bone_pose_rotation(bone))
	var total := 0.0
	for index in _bones.size():
		var weight := weights[index] if index < weights.size() else 0.0
		total += weight
		var share := Quaternion(Vector3.RIGHT, back * weight)
		var local := parents[index].inverse() * share * globals[index]
		skeleton.set_bone_pose_rotation(_bones[index], local.normalized())
	# A steady bone's parent rides the whole turn: its own turn takes it back out.
	var undo := Quaternion(Vector3.RIGHT, -back * total)
	for index in _steady.size():
		var local := steady_parents[index].inverse() * undo * steady_globals[index]
		skeleton.set_bone_pose_rotation(_steady[index], local.normalized())


# Looks the chain's bones (each the parent of the next) and the neck (the last bone's child whose
# name starts with `neck`, else its first) up once.
func _find_bones(skeleton: Skeleton3D) -> bool:
	if not _bones.is_empty():
		return _neck >= 0
	_steady.clear()
	for bone_name in steady:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0 and skeleton.get_bone_parent(bone) >= 0:
			_steady.append(bone)
	for bone_name in chain:
		var bone := skeleton.find_bone(bone_name)
		var linked := _bones.is_empty() or skeleton.get_bone_parent(bone) == _bones[-1]
		if bone < 0 or not linked:
			_bones.clear()
			return false
		_bones.append(bone)
	var children := skeleton.get_bone_children(_bones[_bones.size() - 1])
	_neck = children[0] if not children.is_empty() else -1
	for child in children:
		if skeleton.get_bone_name(child).begins_with("neck"):
			_neck = child
	return _neck >= 0
