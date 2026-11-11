extends SkeletonModifier3D
## The first of a `TwoHandHold`'s modifiers, made by it at run time. It turns the chest about the
## model's up axis, split evenly over the hold's spine bones, until the chest stands at the
## hold's `chest_turn` from the model's front: the turn the clip of this frame already has is
## taken off, so a walk or a run that swings the shoulders leaves the left shoulder forward and
## the left hand in reach of the hand guard. The turn goes by the hold's weight (a switch eases it
## in and out). Then it asks the hold to place the shoulder's pocket and the gun from the chest
## bone's pose of this frame; the hold gives each arm's `HoldArm`, which runs after this, its
## hand's place on the gun just placed, so the hands are on the gun in the pose of this very
## update.

## The hold that made it.
var hold: TwoHandHold


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or hold == null:
		return
	_turn_chest(skeleton)
	hold.place(skeleton)


func _turn_chest(skeleton: Skeleton3D) -> void:
	var bones := hold.spine_bones
	if bones.is_empty():
		return
	var degrees := (hold.chest_turn - _chest_yaw(skeleton, bones[-1])) * hold.weight()
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


# How far the clip has the chest turned from the model's front now, in degrees about the up axis
# (the way `chest_turn` counts): where the turn from the bone's rest sends the model's front.
func _chest_yaw(skeleton: Skeleton3D, bone_name: StringName) -> float:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return 0.0
	var posed := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	var rest := skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	var ahead := (posed * rest.inverse()) * Vector3.BACK
	return rad_to_deg(atan2(ahead.x, ahead.z))
