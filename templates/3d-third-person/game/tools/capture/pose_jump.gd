class_name PoseJump
extends RefCounted
## The largest turn of one bone between two drawn poses of a skeleton, in degrees, and the bone
## that made it: what a snap from one clip to the next shows as (gdstudio #1416). It copies each
## bone's turn against its parent from the drawn pose (after every modifier, in the skeleton's
## `skeleton_updated`) and compares it with the copy before. The fingers, the twist and socket
## bones, the IK targets and the root are left out, as `MomentumBlend` leaves them.
##
## A capture or a test makes one per skeleton, reads `degrees` and `bone` after each frame, and
## calls `forget()` when the body is moved by hand (a teleport).

## Degrees of the largest bone turn between the last two drawn poses.
var degrees := 0.0
## The bone that turned the most.
var bone := ""
## How many poses it has copied.
var poses := 0

var _skeleton: Skeleton3D
var _followed := PackedInt32Array()
var _last: Array[Quaternion] = []


func _init(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	for index in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(index).to_lower()
		if MomentumBlend.SKIPPED.any(func(part: String) -> bool: return part in bone_name):
			continue
		_followed.append(index)
	skeleton.skeleton_updated.connect(_on_updated)


## Starts over: the next pose is compared with nothing.
func forget() -> void:
	_last.clear()
	degrees = 0.0
	bone = ""


func _on_updated() -> void:
	var turns: Array[Quaternion] = []
	turns.resize(_followed.size())
	for slot in _followed.size():
		var index := _followed[slot]
		var pose := _skeleton.get_bone_global_pose(index).basis
		var parent := _skeleton.get_bone_parent(index)
		if parent >= 0:
			pose = _skeleton.get_bone_global_pose(parent).basis.inverse() * pose
		turns[slot] = pose.orthonormalized().get_rotation_quaternion()
	if _last.size() == turns.size():
		degrees = 0.0
		for slot in turns.size():
			var angle := rad_to_deg(_last[slot].angle_to(turns[slot]))
			if angle > degrees:
				degrees = angle
				bone = _skeleton.get_bone_name(_followed[slot])
	_last = turns
	poses += 1
