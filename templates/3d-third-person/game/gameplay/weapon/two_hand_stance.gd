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
# The spine (kit #1347): its bones and the skeleton's parents, read once; whether each spine bone's
# parent is the one before it (`_chain`); and in this update the pose of the first one's parent,
# each one's local pose and its pose in the skeleton's space. With a chain the turns and the
# chest's pose are worked out from these, not from every pose up to the root again for each
# step; the steps are written out in few functions, since a call costs more than most lines in
# the web build's GDScript.
var _laid_out := false
var _bones := PackedInt32Array()
var _parents := PackedInt32Array()
var _chain := false
var _base := Transform3D.IDENTITY
var _locals: Array[Transform3D] = []
var _posed: Array[Transform3D] = []
# The rest turn of the chest (the last spine bone) inverted, read once.
var _rest_inverse := Basis.IDENTITY


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_head = -2
	_laid_out = false


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or hold == null:
		return
	if not _laid_out:
		_lay_out(skeleton)
	if _bones.is_empty():
		hold.place(skeleton)
		return
	var top := _bones[-1]
	# The clip's spine, and how far it has the chest turned from the model's front now, in
	# degrees about the up axis (the way `chest_turn` counts): where the turn from the bone's rest
	# sends the model's front.
	var chest := Transform3D.IDENTITY
	if _chain:
		var above := _parents[_bones[0]]
		_base = HandPoseModifier.global_pose(skeleton, above) if above >= 0 else Transform3D()
		chest = _base
		for index in _bones.size():
			_locals[index] = skeleton.get_bone_pose(_bones[index])
			chest = chest * _locals[index]
			_posed[index] = chest
	elif top >= 0:
		chest = HandPoseModifier.global_pose(skeleton, top)
	var yaw := 0.0
	if top >= 0:
		var ahead := (chest.basis.orthonormalized() * _rest_inverse) * Vector3.BACK
		yaw = rad_to_deg(atan2(ahead.x, ahead.z))
	var degrees := (hold.chest_turn_now() - yaw) * hold.chest_weight()
	_turn_spine(skeleton, Basis(Vector3.UP, deg_to_rad(degrees / _bones.size())))
	_turn_head(skeleton, top, degrees)
	_straighten_chest(skeleton, top)
	hold.place(skeleton, _posed[-1] if _chain else Transform3D(), _chain)


func _lay_out(skeleton: Skeleton3D) -> void:
	_laid_out = true
	_bones = hold.spine_indices()
	_parents = hold.bone_parents()
	_chain = not _bones.is_empty() and _parents.size() == skeleton.get_bone_count()
	var index := 0
	while _chain and index < _bones.size():
		var bone := _bones[index]
		_chain = bone >= 0 and (index == 0 or _parents[bone] == _bones[index - 1])
		index += 1
	_locals.resize(_bones.size())
	_posed.resize(_bones.size())
	if not _bones.is_empty() and _bones[-1] >= 0:
		var rest := skeleton.get_bone_global_rest(_bones[-1]).basis.orthonormalized()
		_rest_inverse = rest.inverse()


# Turns each spine bone by `turn` in the skeleton's space, about its own place. The poses come
# from the local ones up the parents: asking the skeleton for a global pose after a bone was set
# makes it work out every bone under that one again, three times a frame for the spine.
func _turn_spine(skeleton: Skeleton3D, turn: Basis) -> void:
	if _chain:
		var above := _base
		for index in _bones.size():
			var pose := above * _locals[index]
			var turned := Transform3D(turn * pose.basis, pose.origin)
			_locals[index] = above.affine_inverse() * turned
			skeleton.set_bone_pose(_bones[index], _locals[index])
			_posed[index] = turned
			above = turned
		return
	var parent_bone := -2
	var parent := Transform3D.IDENTITY
	for bone in _bones:
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


# Turns the head back by the chest's turn of `degrees`, so it keeps the clip's facing; its
# parent's pose comes from the chest's (`top`) when it is under it.
func _turn_head(skeleton: Skeleton3D, top: int, degrees: float) -> void:
	if _head == -2:
		_head = skeleton.find_bone(HEAD)
	if _head < 0:
		return
	var bone := _parents[_head] if _head < _parents.size() else skeleton.get_bone_parent(_head)
	var neck := Transform3D.IDENTITY
	var cursor := bone
	if _chain:
		while cursor >= 0 and cursor != top:
			neck = skeleton.get_bone_pose(cursor) * neck
			cursor = _parents[cursor]
	if _chain and cursor == top:
		neck = _posed[-1] * neck
	else:
		neck = HandPoseModifier.global_pose(skeleton, bone)
	var head := neck * skeleton.get_bone_pose(_head)
	var back := Basis(Vector3.UP, -deg_to_rad(degrees))
	skeleton.set_bone_pose(
		_head, neck.affine_inverse() * Transform3D(back * head.basis, head.origin)
	)


# Raises a chest that leans more than the hold's `aim_lean_limit` toward that limit as the gun comes
# up (a crouch's hunch would put the stock in the collarbone and the head over the receiver),
# split evenly over the spine bones like the turn.
func _straighten_chest(skeleton: Skeleton3D, top: int) -> void:
	var share := hold.raised_amount() * hold.weight()
	if share <= 0.0 or top < 0:
		return
	var chest := _posed[-1] if _chain else HandPoseModifier.global_pose(skeleton, top)
	var up := (chest.basis.orthonormalized() * _rest_inverse) * Vector3.UP
	var lean := up.angle_to(Vector3.UP)
	var limit := deg_to_rad(hold.aim_lean_limit)
	if lean <= limit:
		return
	var axis := up.cross(Vector3.UP)
	if axis.length_squared() < 1e-10:
		return
	_turn_spine(skeleton, Basis(axis.normalized(), (lean - limit) * share / _bones.size()))
