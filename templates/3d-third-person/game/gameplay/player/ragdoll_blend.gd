@tool
class_name RagdollBlend
extends SkeletonModifier3D
## Blends the skeleton from a pose it was in (the ragdoll lying on the floor) back into whatever
## the animation plays, so a character that gets up does not snap. `PlayerRagdoll` makes it as a
## child of the skeleton, hands it the pose when the body stands up and lowers `weight` from 1 to
## 0.
##
## It runs after the animation has written its pose: each bone's pose is the animation's, moved
## toward the held pose by `weight` (position by a straight line, rotation by a slerp).

## How much of the held pose is kept: 1 is all of it, 0 none (the animation alone).
var weight := 0.0

var _held: Array[Transform3D] = []


## Holds the pose `world_poses` (one transform per bone, in world space, as
## `PlayerRagdoll.snapshot()` reads them) and starts at `weight` 1.
func hold(world_poses: Array[Transform3D]) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or world_poses.size() != skeleton.get_bone_count():
		return
	var inverse := skeleton.global_transform.affine_inverse()
	var global_poses: Array[Transform3D] = []
	_held.clear()
	for bone in skeleton.get_bone_count():
		var global := inverse * world_poses[bone]
		global_poses.append(global)
		var parent := skeleton.get_bone_parent(bone)
		_held.append(global_poses[parent].affine_inverse() * global if parent >= 0 else global)
	weight = 1.0


## Lets go of the held pose.
func release() -> void:
	weight = 0.0
	_held.clear()


## True while a pose is held and still counts.
func is_blending() -> bool:
	return weight > 0.0 and not _held.is_empty()


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not is_blending() or _held.size() != skeleton.get_bone_count():
		return
	for bone in skeleton.get_bone_count():
		var now := skeleton.get_bone_pose(bone)
		var held := _held[bone]
		skeleton.set_bone_pose_position(bone, now.origin.lerp(held.origin, weight))
		skeleton.set_bone_pose_rotation(
			bone,
			now.basis.get_rotation_quaternion().slerp(held.basis.get_rotation_quaternion(), weight)
		)
