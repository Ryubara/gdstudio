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
## Over how long the trunk's lean is averaged before the upright carry takes off what it has over
## the hold's `carry_lean_limit`, in seconds: about a stride, so the run's own rise and fall of the
## trunk through a stride stays and only its standing lean is taken off.
const LEAN_SMOOTHING := 0.5

## The hold that made it.
var hold: TwoHandHold

var _head := -2
# The trunk's lean averaged over `LEAN_SMOOTHING`, in radians, and whether it has a value yet.
var _lean := 0.0
var _leaning := false


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_head = -2


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or hold == null:
		return
	_turn_chest(skeleton)
	_straighten_chest(skeleton)
	_carry_upright(skeleton, delta)
	hold.place(skeleton)


func _turn_chest(skeleton: Skeleton3D) -> void:
	var bones := hold.spine_indices()
	if bones.is_empty():
		return
	var degrees := (hold.chest_turn - _chest_yaw(skeleton, bones[-1])) * hold.chest_weight()
	_turn_spine(skeleton, bones, Basis(Vector3.UP, deg_to_rad(degrees / bones.size())))
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
	_turn_spine(skeleton, bones, Basis(axis.normalized(), (lean - limit) * share / bones.size()))


# Raises a trunk that leans forward more than the hold's `carry_lean_limit` at the low ready
# (`TwoHandHold.carry_amount()`; kit #1348) by what its lean, averaged over `LEAN_SMOOTHING`, has
# over it: the run's own trunk under the rifle's idle leaned 13 degrees and the sprint's 14. The
# lean is the line from the spine's parent (the pelvis) to the head's parent (the neck), forward
# in the model's space, the way the run test reads it. It is a turn about the model's side axis
# spread evenly over the spine bones, so it adds no twist (kit #1379); the head keeps the facing
# the clip gave it, as for the chest's turn.
func _carry_upright(skeleton: Skeleton3D, delta: float) -> void:
	var bones := hold.spine_indices()
	var share := hold.carry_amount()
	if bones.is_empty() or share <= 0.0 or bones[0] < 0 or _head < 0:
		_leaning = false
		return
	var root := skeleton.get_bone_parent(bones[0])
	var neck := skeleton.get_bone_parent(_head)
	if root < 0 or neck < 0:
		return
	var lean := _trunk_lean(skeleton, root, neck)
	if not _leaning:
		_lean = lean
		_leaning = true
	_lean = lerpf(_lean, lean, 1.0 - exp(-delta / LEAN_SMOOTHING))
	var wanted := (_lean - deg_to_rad(hold.carry_lean_limit)) * share
	if wanted <= 0.0:
		return
	var head_before := HandPoseModifier.global_pose(skeleton, _head).basis
	# The spine turns about its own bones, above the pelvis, so the trunk's line turns by less
	# than the spine (about half); the first pass measures by how much and the second takes the
	# rest at that rate.
	_turn_spine(skeleton, bones, Basis(Vector3.RIGHT, -wanted / bones.size()))
	var moved := lean - _trunk_lean(skeleton, root, neck)
	if moved > wanted * 0.1:
		var rest := wanted - moved
		var spine := rest * wanted / moved
		_turn_spine(skeleton, bones, Basis(Vector3.RIGHT, -spine / bones.size()))
	var neck_pose := HandPoseModifier.global_pose(skeleton, neck)
	var head := neck_pose * skeleton.get_bone_pose(_head)
	skeleton.set_bone_pose(
		_head, neck_pose.affine_inverse() * Transform3D(head_before, head.origin)
	)


# The trunk's forward lean, in radians: the line from `root` to `neck` in the skeleton's space.
func _trunk_lean(skeleton: Skeleton3D, root: int, neck: int) -> float:
	var trunk := (
		HandPoseModifier.global_pose(skeleton, neck).origin
		- HandPoseModifier.global_pose(skeleton, root).origin
	)
	return atan2(trunk.z, trunk.y)


# Turns each of `bones` by `turn` in the skeleton's space. The poses come from the local ones up the
# parents (`HandPoseModifier.global_pose`): asking the skeleton for a global pose after a bone was
# set makes it work out every bone under that one again, three times a frame for the spine.
func _turn_spine(skeleton: Skeleton3D, bones: PackedInt32Array, turn: Basis) -> void:
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
		var moved := Transform3D(turn * pose.basis, pose.origin)
		skeleton.set_bone_pose(bone, parent.affine_inverse() * moved)
		parent_bone = bone
		parent = moved


# How far the clip has the chest turned from the model's front now, in degrees about the up axis
# (the way `chest_turn` counts): where the turn from the bone's rest sends the model's front.
func _chest_yaw(skeleton: Skeleton3D, bone: int) -> float:
	if bone < 0:
		return 0.0
	var posed := HandPoseModifier.global_pose(skeleton, bone).basis.orthonormalized()
	var rest := skeleton.get_bone_global_rest(bone).basis.orthonormalized()
	var ahead := (posed * rest.inverse()) * Vector3.BACK
	return rad_to_deg(atan2(ahead.x, ahead.z))
