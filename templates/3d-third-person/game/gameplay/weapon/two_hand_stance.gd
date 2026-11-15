extends SkeletonModifier3D
## The first of a `TwoHandHold`'s modifiers, made by it at run time. It turns the chest about the
## model's up axis (in a slide, its own: `_chest_up`) until the chest stands at the hold's
## `chest_turn` from the model's front (by `chest_weight()`: not while the left hand is away for an
## action): the turn the clip of this frame already has is taken off, so a walk or a run that
## swings the shoulders leaves the left shoulder forward and the left hand in reach of the hand
## guard. Each spine bone goes toward its own share of the turn from the front (a third, two thirds,
## all of it) with the clip's own spread about that share kept up to `SPINE_SPREAD`, not by a share
## of the gap: a clip that swings the chest far on the top bone alone left the lower spine twisted
## past the chest, 44 degrees under a chest on its 30 (kit #1379).
## The turn goes by the hold's weight (a switch eases it in and out), and the head is turned back
## by as much, so it keeps the facing the clip gives it: a run counters its swing of the shoulders
## in the neck, and a head left on a chest whose swing was taken off swung 109 degrees from side to
## side at every stride (kit #1333). Then it asks the hold to place the shoulder's pocket and the
## gun from the chest bone's pose of this frame; the hold gives each arm's `HoldArm`, which runs
## after this, its hand's place on the gun just placed, so the hands are on the gun in the pose of
## this very update.

## The head's bone: it is turned back by the chest's turn, so the head stays on the locomotion
## clip. The head and not the neck under it: the neck carries skin at the collar, and turning it
## put that skin 12 to 24 mm into the stock in the crouch (`test_rifle_hold.gd`).
const HEAD := &"Head"
## Over how long the trunk's lean is averaged before the upright carry takes off what it has over
## the hold's `carry_lean_limit`, in seconds: about a stride, so the run's own rise and fall of the
## trunk through a stride stays and only its standing lean is taken off.
const LEAN_SMOOTHING := 0.5
## How far a spine bone under the chest may stand off its share of the hold's turn, in degrees,
## where the clip twists the spine unevenly (`_share_turn`, kit #1379): the clip's own spread about
## an even twist is kept, eased toward this bound (`tanh`), so the template's clips (spreads of 1
## to 5 degrees) read as before, and with `chest_turn` -30 `spine_02` stands at most 28 degrees from
## the front under any clip (44 with the gap split evenly under a chest swung 47 degrees).
const SPINE_SPREAD := 8.0

## The hold that made it.
var hold: TwoHandHold
## How far the body leans for a peek, either way, 0 to 1, for a hold with no `character` (posed by
## hand); with one, its `CharacterPeek.drawn()` (gdstudio #1436).
var lean_share := 0.0

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
# Each spine bone's rest turn inverted, read once, and how far the clip of this update turns each
# from the model's front, in degrees (`_share_turn`).
var _rest_inverses: Array[Basis] = []
var _clip_yaws := PackedFloat32Array()
# The trunk's lean averaged over `LEAN_SMOOTHING`, in radians, and whether it has a value yet.
var _lean := 0.0
var _leaning := false


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_head = -2
	_laid_out = false


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or hold == null:
		return
	if not _laid_out:
		_lay_out(skeleton)
	if _bones.is_empty():
		hold.place(skeleton)
		return
	var top := _bones[-1]
	# The clip's spine, and how far it has the chest turned from the model's front now
	# (`_chest_yaw`).
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
	# About the chest's own up axis in a slide, not the model's: a slide lays the chest back, and
	# a turn about the model's up axis rolled it onto its side instead (kit #1413).
	var yaw := 0.0
	var axis := Vector3.UP
	var lying := 0.0
	if top >= 0:
		var turned := chest.basis.orthonormalized() * _rest_inverse
		lying = CharacterSlide.lying(hold.character)
		yaw = _chest_yaw(turned, lying)
		axis = _chest_up(turned, lying)
	# `left_chest_turn` on the left shoulder (a left peek lean, gdstudio #1435).
	var turn_now := lerpf(hold.chest_turn, hold.left_chest_turn, hold.side)
	var weight := hold.chest_weight()
	var degrees := (turn_now - yaw) * weight
	if _chain:
		degrees = _share_turn(skeleton, axis, turn_now, weight, lying)
	else:
		_turn_spine(skeleton, Basis(axis, deg_to_rad(degrees / _bones.size())))
	_turn_head(skeleton, top, degrees, axis)
	_straighten_chest(skeleton, top)
	_turn_back(skeleton, top)
	_carry_upright(skeleton, top, delta)
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
	_rest_inverses.resize(_bones.size())
	_clip_yaws.resize(_bones.size())
	for each in _bones.size():
		var bone := _bones[each]
		if bone >= 0:
			_rest_inverses[each] = (
				skeleton.get_bone_global_rest(bone).basis.orthonormalized().inverse()
			)
	if not _bones.is_empty() and _bones[-1] >= 0:
		var rest := skeleton.get_bone_global_rest(_bones[-1]).basis.orthonormalized()
		_rest_inverse = rest.inverse()


# Turns each spine bone of the chain about `axis` toward its share of `turn_now` from the model's
# front (bone `i` of `n` toward `turn_now * (i + 1) / n`) plus the clip's own spread about an even
# twist (its turn of the bone less that share of its chest's), eased to at most `SPINE_SPREAD`; by
# `weight` from where the clip has it. With a small spread this is the gap split evenly, as
# before; the chest ends where that left it, and no bone under it stands farther from the front
# than the clip's own turn of it or its share of the hold's and `SPINE_SPREAD` (kit #1379). Each
# bone's turn now is read after its parent was turned, so it takes the parent's along. Returns
# how far the chest was turned in all, in degrees, for the head's turn back.
func _share_turn(
	skeleton: Skeleton3D, axis: Vector3, turn_now: float, weight: float, lying: float
) -> float:
	var count := _bones.size()
	for index in count:
		var clip := _posed[index].basis.orthonormalized() * _rest_inverses[index]
		_clip_yaws[index] = _chest_yaw(clip, lying)
	var total := 0.0
	var above := _base
	for index in count:
		var pose := above * _locals[index]
		var now := _chest_yaw(pose.basis.orthonormalized() * _rest_inverses[index], lying)
		var share := float(index + 1) / count
		var spread := wrapf(_clip_yaws[index] - _clip_yaws[-1] * share, -180.0, 180.0)
		spread = SPINE_SPREAD * tanh(spread / SPINE_SPREAD)
		var wanted := lerpf(_clip_yaws[index], turn_now * share + spread, weight)
		var degrees := wrapf(wanted - now, -180.0, 180.0)
		total += degrees
		var turned := Transform3D(Basis(axis, deg_to_rad(degrees)) * pose.basis, pose.origin)
		_locals[index] = above.affine_inverse() * turned
		skeleton.set_bone_pose(_bones[index], _locals[index])
		_posed[index] = turned
		above = turned
	return total


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


# Turns the head back by the chest's turn of `degrees` about `axis`, so it keeps the clip's
# facing; its parent's pose comes from the chest's (`top`) when it is under it.
func _turn_head(skeleton: Skeleton3D, top: int, degrees: float, axis: Vector3) -> void:
	if _head == -2:
		_head = skeleton.find_bone(HEAD)
	if _head < 0:
		return
	var neck := _neck_pose(skeleton, top)
	var head := neck * skeleton.get_bone_pose(_head)
	var back := Basis(axis, -deg_to_rad(degrees))
	skeleton.set_bone_pose(
		_head, neck.affine_inverse() * Transform3D(back * head.basis, head.origin)
	)


# Turns a peek lean's chest back to the hold's turn after `_straighten_chest()` (gdstudio #1436):
# the lean rolls a chest the crouch bends forward about the model's front, and raising that chest
# the short way swung its shoulders round, up to 84 degrees past `chest_turn` crouched, so the
# right hand reached across the chest and the arm went into it. The turn is read from the
# shoulders' line (the chest's side axis), which the roll leaves pointing where the shoulders are,
# and it goes by the lean's share: an upright body is left as it was.
func _turn_back(skeleton: Skeleton3D, top: int) -> void:
	var character := hold.character
	var lean := absf(character.peek_motion.drawn()) if character != null else lean_share
	if lean <= 0.0 or top < 0 or not _chain:
		return
	var across := (_posed[-1].basis.orthonormalized() * _rest_inverse) * Vector3.RIGHT
	var yaw := rad_to_deg(atan2(-across.z, across.x))
	var turn_now := lerpf(hold.chest_turn, hold.left_chest_turn, hold.side)
	var degrees := (turn_now - yaw) * hold.chest_weight() * lean
	_turn_spine(skeleton, Basis(Vector3.UP, deg_to_rad(degrees / _bones.size())))
	_turn_head(skeleton, top, degrees, Vector3.UP)


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


# The pose of the head's parent (the neck) in the skeleton's space, from the chest's (`top`) when
# it is under it.
func _neck_pose(skeleton: Skeleton3D, top: int) -> Transform3D:
	var bone := _parents[_head] if _head < _parents.size() else skeleton.get_bone_parent(_head)
	var neck := Transform3D.IDENTITY
	var cursor := bone
	if _chain:
		while cursor >= 0 and cursor != top:
			neck = skeleton.get_bone_pose(cursor) * neck
			cursor = _parents[cursor]
	if _chain and cursor == top:
		return _posed[-1] * neck
	return HandPoseModifier.global_pose(skeleton, bone) if bone >= 0 else Transform3D()


# Raises a trunk that leans forward more than the hold's `carry_lean_limit` at the low ready
# (`TwoHandHold.carry_amount()`; kit #1348) by what its lean, averaged over `LEAN_SMOOTHING`, has
# over it: the run's own trunk under the rifle's idle leaned 13 degrees and the sprint's 14. The
# lean is the line from the spine's parent (the pelvis) to the head's parent (the neck), forward
# in the model's space, the way the run test reads it. It is a turn about the model's side axis
# spread evenly over the spine bones, so it adds no twist (kit #1379); the head keeps the facing
# the clip gave it, as for the chest's turn. It runs only while the carry is on, and its poses
# come from the spine's of this update (kit #1347).
func _carry_upright(skeleton: Skeleton3D, top: int, delta: float) -> void:
	var share := hold.carry_amount()
	if share <= 0.0 or _head < 0 or _bones[0] < 0:
		_leaning = false
		return
	var root := _parents[_bones[0]]
	if root < 0:
		return
	var pelvis := _base.origin if _chain else HandPoseModifier.global_pose(skeleton, root).origin
	var neck := _neck_pose(skeleton, top)
	var trunk := neck.origin - pelvis
	var lean := atan2(trunk.z, trunk.y)
	if not _leaning:
		_lean = lean
		_leaning = true
	_lean = lerpf(_lean, lean, 1.0 - exp(-delta / LEAN_SMOOTHING))
	var wanted := (_lean - deg_to_rad(hold.carry_lean_limit)) * share
	if wanted <= 0.0:
		return
	var head_local := skeleton.get_bone_pose(_head)
	var head_before := (neck * head_local).basis
	# The spine turns about its own bones, above the pelvis, so the trunk's line turns by less
	# than the spine (about half); the first pass measures by how much and the second takes the
	# rest at that rate.
	_turn_spine(skeleton, Basis(Vector3.RIGHT, -wanted / _bones.size()))
	neck = _neck_pose(skeleton, top)
	trunk = neck.origin - pelvis
	var moved := lean - atan2(trunk.z, trunk.y)
	if moved > wanted * 0.1:
		var spine := (wanted - moved) * wanted / moved
		_turn_spine(skeleton, Basis(Vector3.RIGHT, -spine / _bones.size()))
		neck = _neck_pose(skeleton, top)
	var head := neck * head_local
	skeleton.set_bone_pose(_head, neck.affine_inverse() * Transform3D(head_before, head.origin))


## The spine's poses in the skeleton's space, in the order of the hold's `spine_bones`: this array,
## filled in every update the stance hands the hold the spine's top (kit #1347), so the hold's push
## to the skin reads them and does not work them out again.
func spine_poses() -> Array[Transform3D]:
	return _posed


# How far the clip has the chest turned from the model's front now, in degrees (the way
# `chest_turn` counts), from `turned`, the chest's turn from its rest in the model's space: where
# it sends the model's front, about the model's up axis, and by `lying` (a slide's share,
# `CharacterSlide.lying`) about the chest's own up axis. Laid back by a slide, the front points
# up, its turn about the model's up axis came from the slightest roll, a different one every
# slide, and a turn about that axis rolled the trunk onto its side (kit #1413). Not by the chest's
# lean: the reload and the clips lean it as far as a slide does.
static func _chest_yaw(turned: Basis, lying: float) -> float:
	var ahead := turned * Vector3.BACK
	var upright := rad_to_deg(atan2(ahead.x, ahead.z))
	var up := (turned * Vector3.UP).normalized()
	if lying <= 0.0 or up.dot(Vector3.UP) < -0.99:
		return upright
	var leaned := Basis(Quaternion(Vector3.UP, up)) * Vector3.BACK
	return lerpf(upright, rad_to_deg(leaned.signed_angle_to(ahead, up)), lying)


# The axis the chest turns about now, in the model's space (`_chest_yaw`).
static func _chest_up(turned: Basis, lying: float) -> Vector3:
	if lying <= 0.0:
		return Vector3.UP
	var up := (turned * Vector3.UP).normalized()
	if up.dot(Vector3.UP) < -0.99:
		return Vector3.UP
	return Vector3.UP.slerp(up, lying).normalized()
