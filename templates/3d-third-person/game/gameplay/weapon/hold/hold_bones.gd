class_name HoldBones
extends RefCounted
## The bone poses a `TwoHandHold` works out in the skeleton's update, from the local ones up the
## parents (kit #1347): the parents read once from the skeleton, and the pose of the spine's top
## bone that the stance has from its turn, so the chest and the left shoulder under it are
## worked out from there and not from every pose up to the root again. The web build pays for
## each step up in GDScript.

## Every bone's parent (below 0 for a root), read by `read()`.
var parents := PackedInt32Array()
## The bone whose pose `top_pose` is, this update (below 0: none is known).
var top := -1
var top_pose := Transform3D.IDENTITY


## Reads the parents of the skeleton's bones (when the model is put in).
func read(skeleton: Skeleton3D) -> void:
	parents.resize(skeleton.get_bone_count())
	for bone in parents.size():
		parents[bone] = skeleton.get_bone_parent(bone)
	top = -1


## `HandPoseModifier.global_pose()` with the parents read once: the same products in the same order.
func global_pose(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var posed := skeleton.get_bone_pose(bone)
	var parent := parents[bone]
	while parent >= 0:
		posed = skeleton.get_bone_pose(parent) * posed
		parent = parents[parent]
	return posed


## The pose of `bone` in the skeleton's space: from `top_pose` and the local poses under `top` when
## the bone is under it, else from every pose up to the root.
func from_top(skeleton: Skeleton3D, bone: int) -> Transform3D:
	if top >= 0:
		var posed := Transform3D.IDENTITY
		var cursor := bone
		while cursor >= 0 and cursor != top:
			posed = skeleton.get_bone_pose(cursor) * posed
			cursor = parents[cursor]
		if cursor == top:
			return top_pose * posed
	return global_pose(skeleton, bone)
