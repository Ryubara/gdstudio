extends SkeletonModifier3D
## The first of a `TwoHandHold`'s modifiers, made by it at run time. It turns the chest about the
## model's up axis, split evenly over the hold's spine bones, until the chest stands at the
## hold's `chest_turn` from the model's front (by `chest_weight()`: not while the left hand is
## away for an action): the turn the clip of this frame already has is
## taken off, so a walk or a run that swings the shoulders leaves the left shoulder forward and
## the left hand in reach of the hand guard. The turn goes by the hold's weight (a switch eases it
## in and out), and the head is turned back by as much, so it keeps the facing the clip gives it:
## a run counters its swing of the shoulders in the neck, and a head left on a chest whose swing
## was taken off swung 109 degrees from side to side at every stride (kit #1333). Then it asks the
## hold to place the shoulder's pocket and the gun from the chest bone's pose of this frame; the
## hold gives each arm's `HoldArm`, which runs after this, its hand's place on the gun just placed,
## so the hands are on the gun in the pose of this very update.

## The head's bone: it is turned back by the chest's turn, so the head stays on the locomotion
## clip. The head and not the neck under it: the neck carries skin at the collar, and turning it
## put that skin 12 to 24 mm into the stock in the crouch (`test_rifle_hold.gd`).
const HEAD := &"Head"

## The hold that made it.
var hold: TwoHandHold

var _head := -2


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_head = -2


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or hold == null:
		return
	_turn_chest(skeleton)
	_straighten_chest(skeleton)
	hold.place(skeleton)


func _turn_chest(skeleton: Skeleton3D) -> void:
	var bones := hold.spine_indices()
	if bones.is_empty():
		return
	var degrees := (hold.chest_turn - _chest_yaw(skeleton, bones[-1])) * hold.chest_weight()
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
	if _head == -2:
		_head = skeleton.find_bone(HEAD)
	if _head < 0:
		return
	var neck := HandPoseModifier.global_pose(skeleton, skeleton.get_bone_parent(_head))
	var head := neck * skeleton.get_bone_pose(_head)
	var back := Basis(Vector3.UP, -deg_to_rad(degrees))
	skeleton.set_bone_pose(
		_head, neck.affine_inverse() * Transform3D(back * head.basis, head.origin)
	)


# Raises a chest that leans more than the hold's `aim_lean_limit` toward that limit as the gun comes
# up (a crouch's hunch would put the stock in the collarbone and the head over the receiver),
# split evenly over the spine bones like the turn.
func _straighten_chest(skeleton: Skeleton3D) -> void:
	var bones := hold.spine_indices()
	var share := hold.raised_amount() * hold.weight()
	if bones.is_empty() or share <= 0.0 or bones[-1] < 0:
		return
	var top := bones[-1]
	var posed := HandPoseModifier.global_pose(skeleton, top).basis.orthonormalized()
	var rest := skeleton.get_bone_global_rest(top).basis.orthonormalized()
	var up := (posed * rest.inverse()) * Vector3.UP
	var lean := up.angle_to(Vector3.UP)
	var limit := deg_to_rad(hold.aim_lean_limit)
	if lean <= limit:
		return
	var axis := up.cross(Vector3.UP)
	if axis.length_squared() < 1e-10:
		return
	var turn := Basis(axis.normalized(), (lean - limit) * share / bones.size())
	# From the local poses up the parents, as the turn above.
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
