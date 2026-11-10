class_name HandPoseModifier
extends SkeletonModifier3D
## Turns the bones of a hand to a `HandPose` after the clip (kit #1001): the clips hold one fist
## for every weapon, so the fingers are closed on the weapon here instead. A second pose can be
## blended over the first (the trigger finger moving from the frame to the trigger). The node's
## own `influence` fades the whole pose in and out; it reads no clock.

## The pose every named bone takes.
@export var pose: HandPose:
	set(value):
		pose = value
		_bones.clear()
## A pose blended over `pose` on the bones it names, by `second_weight`.
@export var second: HandPose
## How far the bones `second` names are on it (0 `pose`, 1 `second`).
@export_range(0.0, 1.0, 0.01) var second_weight := 0.0

# The skeleton's bone index for each name of `pose`, its rotations and then its turns.
var _bones: Dictionary[StringName, int] = {}
var _turned: Dictionary[StringName, int] = {}


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_bones.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or pose == null:
		return
	if _bones.is_empty():
		_turned.clear()
		for bone_name in pose.rotations:
			_bones[bone_name] = skeleton.find_bone(bone_name)
		for bone_name in pose.turns:
			_turned[bone_name] = skeleton.find_bone(bone_name)
	for bone_name in _turned:
		var bone := _turned[bone_name]
		if bone >= 0:
			skeleton.set_bone_pose_rotation(
				bone, skeleton.get_bone_pose_rotation(bone) * pose.turns[bone_name]
			)
	for bone_name in _bones:
		var bone := _bones[bone_name]
		if bone < 0:
			continue
		var turned := pose.rotations[bone_name]
		if second != null and second_weight > 0.0 and second.rotations.has(bone_name):
			turned = turned.slerp(second.rotations[bone_name], second_weight)
		skeleton.set_bone_pose_rotation(bone, turned)
