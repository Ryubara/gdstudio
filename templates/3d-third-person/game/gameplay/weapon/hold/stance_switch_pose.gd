class_name StanceSwitchPose
extends RefCounted
## The trunk a rifle's stance holds through a switch while the body leans (gdstudio #1585).
##
## On a lean the stance moves the head a long way from where the bend alone puts it (the raise of
## a leaning chest and the chest's turn about the model's up axis: 12 to 14 cm from the pelvis on
## a right lean), and through a switch two holds let go of it at once: `PeekModifier` let go of the
## clips' turns it kept and the stance of the arms' weight, each along its own curve, so the head
## went 3 to 11 cm off the straight way between the two weapons' stances. Now, while the next weapon
## comes up, `PeekModifier` keeps nothing and the stance blends the trunk, as the clips and every
## modifier before it leave it, toward the pose drawn just before the switch by the hold's share:
## one blend between two poses, so the head goes nearly straight. The pose kept is the stance's own
## output while its weapon is in the hands, and the trunk it was given while another weapon is,
## since then it shows that weapon's held pose. A pose on each machine from what the body already
## has: never sent.

# The first spine bone's turn in the skeleton's space (its parent, the pelvis, is the bend's and
# the legs'), the turns of the spine bones above it, the neck's and the head's on their parents.
var _turns: Array[Quaternion] = []
var _kept := false


## Forgets the pose kept (the switch is over).
func clear() -> void:
	_kept = false


## True once a pose is kept.
func has_pose() -> bool:
	return _kept


## Keeps the pose of this update: the spine's `posed` (in the skeleton's space) and `locals`, and
## the neck's and the head's local turns (`neck` and `head`, -1 when the rig has none).
func keep(
	skeleton: Skeleton3D,
	locals: Array[Transform3D],
	posed: Array[Transform3D],
	neck: int,
	head: int
) -> void:
	var count := locals.size()
	_turns.resize(count + 2)
	_turns[0] = posed[0].basis.get_rotation_quaternion()
	for index in range(1, count):
		_turns[index] = locals[index].basis.get_rotation_quaternion()
	_turns[count] = skeleton.get_bone_pose_rotation(neck) if neck >= 0 else Quaternion.IDENTITY
	_turns[count + 1] = skeleton.get_bone_pose_rotation(head) if head >= 0 else Quaternion.IDENTITY
	_kept = true


## Turns the spine `bones`, the neck and the head `share` of the way from their pose now toward the
## kept one and writes `locals` and `posed` again from `base`, the first bone's parent's pose (the
## places stay); then turns the whole spine about its first bone so the head is `share` of the
## straight way from where it was to where the kept pose has it: turned bone by bone, it went round
## an arc, up to 9 mm off that way. Under a modifier's `influence` below 1 each bone's turn is taken
## on past that pose by as much, so the influence brings it back to it.
func blend(
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	base: Transform3D,
	locals: Array[Transform3D],
	posed: Array[Transform3D],
	neck: int,
	head: int,
	share: float,
	influence := 1.0
) -> void:
	if not _kept or _turns.size() != bones.size() + 2:
		return
	var count := bones.size()
	var given: Array[Transform3D] = locals.duplicate()
	var neck_local := skeleton.get_bone_pose(neck) if neck >= 0 else Transform3D.IDENTITY
	var head_place := skeleton.get_bone_pose_position(head) if head >= 0 else Vector3.ZERO
	var live := _head_at(base, given, neck_local, head_place, 0.0)
	var kept := _head_at(base, given, neck_local, head_place, 1.0)
	var above := base
	for index in count:
		var pose := above * locals[index]
		if index == 0:
			var turn := _toward(pose.basis.get_rotation_quaternion(), _turns[0], share)
			pose = Transform3D(Basis(turn).scaled(pose.basis.get_scale()), pose.origin)
			locals[index] = above.affine_inverse() * pose
		else:
			var local := locals[index]
			var turn := _toward(local.basis.get_rotation_quaternion(), _turns[index], share)
			locals[index] = Transform3D(Basis(turn).scaled(local.basis.get_scale()), local.origin)
			pose = above * locals[index]
		posed[index] = pose
		above = pose
	var neck_from := neck_local.basis.get_rotation_quaternion()
	var neck_turn := _toward(neck_from, _turns[count], share)
	var head_now := (posed[-1] * Transform3D(Basis(neck_turn), neck_local.origin)) * head_place
	var origin := posed[0].origin
	var arc := head_now - origin
	var straight := live.lerp(kept, share) - origin
	if not arc.is_zero_approx() and not straight.is_zero_approx():
		var onto := Basis(Quaternion(arc.normalized(), straight.normalized()))
		posed[0] = Transform3D(onto * posed[0].basis, origin)
		locals[0] = base.affine_inverse() * posed[0]
		for index in range(1, count):
			posed[index] = posed[index - 1] * locals[index]
	var past := 1.0 / maxf(influence, 0.001)
	for index in count:
		var local := locals[index]
		if past > 1.0:
			var from := given[index].basis.get_rotation_quaternion()
			var turn := _toward(from, local.basis.get_rotation_quaternion(), past)
			local = Transform3D(Basis(turn).scaled(local.basis.get_scale()), local.origin)
		skeleton.set_bone_pose(bones[index], local)
	if neck >= 0:
		skeleton.set_bone_pose_rotation(neck, _toward(neck_from, neck_turn, past))
	if head >= 0:
		var head_from := skeleton.get_bone_pose_rotation(head)
		var head_turn := _toward(head_from, _turns[count + 1], share)
		skeleton.set_bone_pose_rotation(head, _toward(head_from, head_turn, past))


# Where the head bone is with the spine (`locals` from `base`) and the neck turned `share` of the
# way toward the kept pose, the places as they are.
func _head_at(
	base: Transform3D,
	locals: Array[Transform3D],
	neck_local: Transform3D,
	head_place: Vector3,
	share: float
) -> Vector3:
	var above := base
	for index in locals.size():
		var pose := above * locals[index]
		if index == 0:
			var turn := _toward(pose.basis.get_rotation_quaternion(), _turns[0], share)
			pose = Transform3D(Basis(turn).scaled(pose.basis.get_scale()), pose.origin)
		else:
			var local := locals[index]
			var turn := _toward(local.basis.get_rotation_quaternion(), _turns[index], share)
			pose = above * Transform3D(Basis(turn).scaled(local.basis.get_scale()), local.origin)
		above = pose
	var neck_turn := _toward(neck_local.basis.get_rotation_quaternion(), _turns[-2], share)
	return (above * Transform3D(Basis(neck_turn), neck_local.origin)) * head_place


# `share` of the way from `from` to `to`, the short way; past 1 it goes on along it.
static func _toward(from: Quaternion, to: Quaternion, share: float) -> Quaternion:
	var way := (from.inverse() * to).normalized()
	if way.w < 0.0:
		way = -way
	var axis := Vector3(way.x, way.y, way.z)
	if axis.length_squared() < 1e-12:
		return from
	return (from * Quaternion(axis.normalized(), way.get_angle() * share)).normalized()
