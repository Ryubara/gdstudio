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
	var bones := hold.spine_indices()
	if bones.is_empty():
		return
	var degrees := (hold.chest_turn - _chest_yaw(skeleton, bones[-1])) * hold.weight()
	var turn := Basis(Vector3.UP, deg_to_rad(degrees / bones.size()))
	# The poses come from the local ones up the parents (`HandPoseModifier.global_pose`): asking
	# the skeleton for a global pose after a bone was set makes it work out every bone under
	# that one again, three times a frame for the spine.
	var parent_bone := -2
	var parent := Transform3D.IDENTITY
	for bone in bones:
		if bone < 0:
			continue
		var above := skeleton.get_bone_parent(bone)
		if above != parent_bone:
			parent_bone = above
			parent = HandPoseModifier.global_pose(skeleton, above) if above >= 0 else Transform3D()
		var pose := parent * skeleton.get_bone_pose(bone)
		var turned := Transform3D(turn * pose.basis, pose.origin)
		skeleton.set_bone_pose(bone, parent.affine_inverse() * turned)
		parent_bone = bone
		parent = turned


# How far the clip has the chest turned from the model's front now, in degrees about the up axis
# (the way `chest_turn` counts): where the turn from the bone's rest sends the model's front.
func _chest_yaw(skeleton: Skeleton3D, bone: int) -> float:
	if bone < 0:
		return 0.0
	var posed := HandPoseModifier.global_pose(skeleton, bone).basis.orthonormalized()
	var rest := skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	var ahead := (posed * rest.inverse()) * Vector3.BACK
	return rad_to_deg(atan2(ahead.x, ahead.z))
