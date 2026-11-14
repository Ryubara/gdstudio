class_name AimOffsetModifier
extends SkeletonModifier3D
## Turns a chain of spine bones after the clips so the weapon's muzzle points at a point (kit
## #1253): it reads where the muzzle points in this very update (the move's pose, the aim clips
## and the grip's wrist turn under it), holds the direction to the point within its limits (the
## heading off the model's +Z, the way the body faces, and the elevation), and works out the turn
## that puts the muzzle along it: a pitch about the model's side axis, then a yaw about up. The
## whole turn is one rotation, and each bone of the chain turns by its share of it about the same
## axis, so the shares add up to it exactly. The arms, the hands and the weapon ride the spine, so
## they follow; the support hand that reaches for the weapon after this (`HoldArm`) finds it there.
## A second pass takes the muzzle's own swing round the spine into account. While the weapon comes
## up or goes down, the drawn pose is the aim pose blended with the carry pose, so the turn is
## solved on the aim pose alone (`aim_pose`) and on the drawn pose only by `drawn_trust` (kit
## #1318). The passes work on copies of the chain's poses and each bone is written once.
##
## While `hold_turn` is on (a shot's recoil playing), the turn found before is kept and only moved
## by as much as the aim moved since, so the recoil the clip shows is not turned away; when it
## goes off, the turn eases back to the measured one over `release_time`. The node's `influence`
## fades it in and out; it reads no clock but the update's delta.

## The bones that turn, from the hips up (each turns its share in the skeleton's space).
@export var chain: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]:
	set(value):
		chain = value
		_bones.clear()
## Each bone's share of the turn, in the order of `chain`; they should add up to 1.
@export var weights := PackedFloat32Array([0.3, 0.3, 0.4])
## The muzzle: a node that rides a `BoneAttachment3D` of the same skeleton, pointing along -Z.
@export var muzzle: Node3D:
	set(value):
		if value != muzzle:
			muzzle = value
			_attachment = null
## The point the muzzle is turned toward, in world space.
@export var target := Vector3.ZERO
## How far it may turn the upper body.
@export var limits: AimLimits
## On: keep the turn found before, moved only with the point (a recoil plays).
@export var hold_turn := false
## Seconds the turn takes to ease back to the measured one after `hold_turn` goes off.
@export_range(0.0, 1.0, 0.01, "suffix:s") var release_time := 0.12
## Passes of the solve (the second takes in the muzzle's own swing round the spine).
@export_range(1, 4, 1) var passes := 2
## The weapon's aim pose alone, solved on in place of the drawn pose (null: the drawn pose).
var aim_pose: AimPose
## How far the turn is the one solved on the drawn pose rather than on `aim_pose` (0 the aim pose
## alone, 1 the drawn pose alone): the drawn pose is the aim pose blended with the carry pose
## until the weapon is all the way up.
var drawn_trust := 1.0

## The pitch (x, positive lifts the muzzle) and yaw (y, positive to the model's left) of the last
## update's turn, in radians, before `influence`.
var turn := Vector2.ZERO
## How far the muzzle pointed from the aimed direction (the way to the point, held within the
## limits) after the last update, in degrees, before `influence`.
var miss := 0.0

var _bones := PackedInt32Array()
var _attachment: BoneAttachment3D
var _bone := -1
# The pose of the chain's parent, each chain bone's local pose now, and from the last one to the
# muzzle.
var _base := Transform3D.IDENTITY
var _locals: Array[Transform3D] = []
var _below := Transform3D.IDENTITY
var _offset := Transform3D.IDENTITY
var _held := Vector2.ZERO
var _held_angles := Vector2.ZERO
var _holding := false
var _release := 0.0


## True while a shot's recoil keeps the turn (`hold_turn`) or the turn eases back after it.
func is_settling() -> bool:
	return hold_turn or _release > 0.0


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_bones.clear()
	_attachment = null


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or muzzle == null or limits == null or not muzzle.is_inside_tree():
		return
	if not _find_parts(skeleton):
		return
	var point := skeleton.global_transform.affine_inverse() * target
	var trust := drawn_trust if aim_pose != null and aim_pose.has_pose() else 1.0
	var wanted := Vector2.ZERO
	# The drawn pose turned by the passes on it, used as it is when the turn is theirs alone.
	var solved: Array[Transform3D] = []
	if trust < 1.0:
		wanted = _solve_passes(_aim_locals(), _aim_below(skeleton), point, solved)
	if trust > 0.0:
		var drawn_turn := _solve_passes(_locals, _below, point, solved)
		wanted = wanted.lerp(drawn_turn, trust)
	# The passes on the drawn pose alone, with no recoil kept or eased: their pose is the result.
	var as_solved := trust >= 1.0 and not hold_turn and _release <= 0.0
	if hold_turn:
		var angles := _angles(_aimed_direction(point, _muzzle_of(_locals, _below)))
		if not _holding:
			_holding = true
			_held = turn
			_held_angles = angles
		wanted = (
			_held + Vector2(angles.y - _held_angles.y, wrapf(angles.x - _held_angles.x, -PI, PI))
		)
		_release = release_time
	# How much of the last pass's correction this update takes: all of it, but while the turn eases
	# back after a recoil only as much as it has eased (gdstudio #1369: taken whole, the last pass
	# put back on one frame all that the ease spread out, and the chest snapped 10 to 20 degrees
	# as a recoil kept in the air ran out, the jump's pose having moved under the kept turn).
	var eased := 1.0
	if not hold_turn:
		_holding = false
		if _release > 0.0:
			# Ease from the kept turn back to the measured one.
			var share := clampf(delta / _release, 0.0, 1.0)
			_release = maxf(_release - delta, 0.0)
			wanted = turn.lerp(wanted, share)
			eased = 1.0 - _release / maxf(release_time, 0.001)
	var turned := solved
	if not as_solved:
		turned = _turned(_locals, wanted)
		if not hold_turn and trust > 0.0:
			# One more pass on the drawn pose, by as much as it is trusted.
			var more := _solve(turned, _below, point) * trust * eased
			turned = _turned(turned, more)
			wanted += more
	_write(skeleton, turned)
	turn = wanted
	var drawn := _muzzle_of(turned, _below)
	miss = rad_to_deg((-drawn.basis.z).normalized().angle_to(_aimed_direction(point, drawn)))


# The turn summed over `passes` solves on the chain posed by `locals`, each solve made on the chain
# the passes before turned (the second takes in the muzzle's own swing round the spine). `posed`
# is filled with the chain turned by every pass.
func _solve_passes(
	locals: Array[Transform3D], below: Transform3D, point: Vector3, posed: Array[Transform3D]
) -> Vector2:
	var total := Vector2.ZERO
	var turned := locals
	for _pass in passes:
		var more := _solve(turned, below, point)
		total += more
		turned = _turned(turned, more)
	posed.assign(turned)
	return total


# The turn that puts the muzzle, with the chain posed by `locals`, along the aimed direction: a
# pitch (x) about the model's side axis, the chest bending forward or back, then a yaw (y) about its
# up axis. Both are exact for the direction: the pitch brings the muzzle to the aim's elevation,
# the yaw to its heading.
func _solve(locals: Array[Transform3D], below: Transform3D, point: Vector3) -> Vector2:
	var at := _muzzle_of(locals, below)
	var pointing := (-at.basis.z).normalized()
	var aimed := _aimed_direction(point, at)
	# About +X: the forward (z) and up (y) parts turn, the side part (x) stays.
	var reach := Vector2(pointing.z, pointing.y).length()
	var pitch := 0.0
	if reach > 0.001:
		var lift := asin(clampf(aimed.y / reach, -1.0, 1.0))
		pitch = lift - atan2(pointing.y, pointing.z)
	var pitched := pointing.rotated(Vector3.LEFT, pitch)
	var yaw := wrapf(atan2(aimed.x, aimed.z) - atan2(pitched.x, pitched.z), -PI, PI)
	return Vector2(pitch, yaw)


# The direction from the muzzle at `at` to `point` in the skeleton's space, held within the limits:
# its heading off the model's +Z (the way the body faces) and its elevation.
func _aimed_direction(point: Vector3, at: Transform3D) -> Vector3:
	var toward := point - at.origin
	if toward.is_zero_approx():
		return Vector3.BACK
	var angles := _angles(toward.normalized())
	var heading := limits.clamp_yaw(angles.x)
	var elevation := limits.clamp_pitch(angles.y)
	return Vector3(sin(heading) * cos(elevation), sin(elevation), cos(heading) * cos(elevation))


# The heading about +Y (x: 0 along +Z, positive toward +X, the model's left) and the elevation
# (y) of a direction.
func _angles(direction: Vector3) -> Vector2:
	return Vector2(atan2(direction.x, direction.z), asin(clampf(direction.y, -1.0, 1.0)))


# The chain's local poses turned by `by` (pitch, yaw): the whole turn is one rotation (the pitch
# about the side axis, then the yaw about up), and each bone turns by its share of it about the
# same axis, so the shares add up to it exactly. Nothing is written to the skeleton.
func _turned(locals: Array[Transform3D], by: Vector2) -> Array[Transform3D]:
	if by.is_zero_approx():
		return locals
	var whole := Quaternion(Vector3.UP, by.y) * Quaternion(Vector3.LEFT, by.x)
	var result: Array[Transform3D] = []
	result.resize(locals.size())
	var above := _base
	for index in locals.size():
		var share := weights[index] if index < weights.size() else 0.0
		var local := locals[index]
		if share > 0.0:
			var part := Basis(Quaternion.IDENTITY.slerp(whole, share))
			var posed := above * local
			var turned := (
				above.basis.orthonormalized().inverse() * part * posed.basis.orthonormalized()
			)
			var spin := turned.orthonormalized().get_rotation_quaternion()
			local = Transform3D(Basis(spin).scaled(local.basis.get_scale()), local.origin)
		result[index] = local
		above = above * local
	return result


# Writes the chain's turned rotations to the skeleton, each bone once: Godot 4.7 blends a
# modifier's result by its `influence` from the pose a bone had before its last write in the
# update, so a bone written twice (once per pass) took the first pass whole (kit #1318).
func _write(skeleton: Skeleton3D, locals: Array[Transform3D]) -> void:
	for index in _bones.size():
		var share := weights[index] if index < weights.size() else 0.0
		if share > 0.0:
			skeleton.set_bone_pose_rotation(
				_bones[index], locals[index].basis.orthonormalized().get_rotation_quaternion()
			)


# The muzzle's pose in the skeleton's space with the chain posed by `locals`: the chain from its
# parent, the bones below it to the one the attachment rides (`below`, which the turn does not
# move), and the muzzle's place there.
func _muzzle_of(locals: Array[Transform3D], below: Transform3D) -> Transform3D:
	var above := _base
	for local in locals:
		above = above * local
	return above * below


# The chain's local poses in the weapon's aim pose alone (`aim_pose`).
func _aim_locals() -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for index in _bones.size():
		result.append(aim_pose.local(_bones[index], _locals[index]))
	if not result.is_empty():
		result[0] = aim_pose.braced(_bones[0], result[0], _base.basis)
	return result


# From the last bone of the chain to the muzzle in the aim pose alone: the arm as the aim clips
# pose it, and the hand the attachment rides as the grip turns it (`AimPose.gripped()`).
func _aim_below(skeleton: Skeleton3D) -> Transform3D:
	var result := _offset
	var cursor := _bone
	while cursor != _bones[-1] and cursor >= 0:
		var pose := skeleton.get_bone_pose(cursor)
		if cursor == _bone:
			result = aim_pose.gripped(cursor, skeleton.get_bone_name(cursor), pose) * result
		else:
			result = aim_pose.local(cursor, pose) * result
		cursor = skeleton.get_bone_parent(cursor)
	return result


# Finds the chain's bones, the attachment the muzzle rides and the muzzle's place on its bone, and
# reads the poses the solve starts from: the chain's bones and what is below the chain down to the
# muzzle. Each bone of the chain must be the child of the one before it, and the attachment's bone
# below the last.
func _find_parts(skeleton: Skeleton3D) -> bool:
	if _bones.is_empty():
		for bone_name in chain:
			var found := skeleton.find_bone(bone_name)
			if (
				found < 0
				or (not _bones.is_empty() and skeleton.get_bone_parent(found) != _bones[-1])
			):
				_bones.clear()
				return false
			_bones.append(found)
		_locals.resize(_bones.size())
		if _bones.is_empty():
			return false
	if _attachment == null or not is_instance_valid(_attachment):
		_attachment = null
		var cursor := muzzle.get_parent()
		while cursor != null and not cursor is BoneAttachment3D:
			cursor = cursor.get_parent()
		if cursor == null:
			return false
		_attachment = cursor as BoneAttachment3D
		_bone = skeleton.find_bone(_attachment.bone_name)
		# The muzzle is fixed on its attachment: its place there, read once from the nodes between
		# (a global transform read in the middle of the skeleton's update would make the engine
		# work every node's transform out again).
		_offset = Transform3D.IDENTITY
		var node: Node = muzzle
		while node != _attachment:
			_offset = (node as Node3D).transform * _offset
			node = node.get_parent()
	if _bone < 0:
		return false
	_below = _offset
	var cursor := _bone
	while cursor != _bones[-1]:
		if cursor < 0:
			return false
		_below = skeleton.get_bone_pose(cursor) * _below
		cursor = skeleton.get_bone_parent(cursor)
	var parent := skeleton.get_bone_parent(_bones[0])
	_base = HandPoseModifier.global_pose(skeleton, parent) if parent >= 0 else Transform3D.IDENTITY
	for index in _bones.size():
		_locals[index] = skeleton.get_bone_pose(_bones[index])
	return true
