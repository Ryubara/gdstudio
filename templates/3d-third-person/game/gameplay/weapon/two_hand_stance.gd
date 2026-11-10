extends SkeletonModifier3D
## The first of a `TwoHandHold`'s modifiers, made by it at run time: it asks the hold to place the
## shoulder's pocket and the gun from the chest bone's pose of this frame (the clip's, before any
## other modifier), then turns the chest about the model's up axis, split evenly over the hold's
## spine bones, by the hold's `chest_turn` times its weight (a switch putting the gun away eases
## the turn out). The arms' IK modifiers after it read the hands' targets on the gun just placed.

## The hold that made it.
var hold: TwoHandHold


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or hold == null:
		return
	hold.place(skeleton, delta)
	var bones := hold.spine_bones
	if bones.is_empty():
		return
	var degrees := hold.chest_turn * hold.weight()
	var turn := Basis(Vector3.UP, deg_to_rad(degrees / bones.size()))
	for bone_name in bones:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
		skeleton.set_bone_pose(
			bone, parent.affine_inverse() * Transform3D(turn * pose.basis, pose.origin)
		)
