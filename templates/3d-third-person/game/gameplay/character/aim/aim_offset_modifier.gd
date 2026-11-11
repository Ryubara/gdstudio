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
## A second pass takes the muzzle's own swing round the spine into account.
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

## The pitch (x, positive lifts the muzzle) and yaw (y, positive to the model's left) of the last
## update's turn, in radians, before `influence`.
var turn := Vector2.ZERO
## How far the muzzle pointed from the aimed direction (the way to the point, held within the
## limits) after the last update, in degrees, before `influence`.
var miss := 0.0

var _bones := PackedInt32Array()
var _attachment: BoneAttachment3D
var _bone := -1
# The pose of the chain's parent, of each chain bone now, and from the last one to the muzzle.
var _base := Transform3D.IDENTITY
var _globals: Array[Transform3D] = []
var _below := Transform3D.IDENTITY
var _offset := Transform3D.IDENTITY
var _held := Vector2.ZERO
var _held_angles := Vector2.ZERO
var _holding := false
var _release := 0.0


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
	var wanted := _solve(point)
	if hold_turn:
		var angles := _angles(_aimed_direction(point))
		if not _holding:
			_holding = true
			_held = turn
			_held_angles = angles
		wanted = (
			_held + Vector2(angles.y - _held_angles.y, wrapf(angles.x - _held_angles.x, -PI, PI))
		)
		_release = release_time
	else:
		_holding = false
		if _release > 0.0:
			# Ease from the kept turn back to the measured one.
			var share := clampf(delta / _release, 0.0, 1.0)
			_release = maxf(_release - delta, 0.0)
			wanted = turn.lerp(wanted, share)
	_apply(wanted)
	if not hold_turn:
		for _pass in passes - 1:
			var more := _solve(point)
			_apply(more)
			wanted += more
	turn = wanted
	miss = rad_to_deg((-_muzzle().basis.z).normalized().angle_to(_aimed_direction(point)))


# The turn that puts the muzzle, as it is posed now, along the aimed direction: a pitch (x) about
# the model's side axis, the chest bending forward or back, then a yaw (y) about its up axis.
# Both are exact for the direction: the pitch brings the muzzle to the aim's elevation, the yaw to
# its heading.
func _solve(point: Vector3) -> Vector2:
	var pointing := (-_muzzle().basis.z).normalized()
	var aimed := _aimed_direction(point)
	# About +X: the forward (z) and up (y) parts turn, the side part (x) stays.
	var reach := Vector2(pointing.z, pointing.y).length()
	var pitch := 0.0
	if reach > 0.001:
		var lift := asin(clampf(aimed.y / reach, -1.0, 1.0))
		pitch = lift - atan2(pointing.y, pointing.z)
	var pitched := pointing.rotated(Vector3.LEFT, pitch)
	var yaw := wrapf(atan2(aimed.x, aimed.z) - atan2(pitched.x, pitched.z), -PI, PI)
	return Vector2(pitch, yaw)


# The direction from the muzzle to `point` in the skeleton's space, held within the limits: its
# heading off the model's +Z (the way the body faces) and its elevation.
func _aimed_direction(point: Vector3) -> Vector3:
	var toward := point - _muzzle().origin
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


# Turns the chain by `by` (pitch, yaw): the whole turn is one rotation (the pitch about the side
# axis, then the yaw about up), and each bone turns by its share of it about the same axis, so
# the shares add up to it exactly.
func _apply(by: Vector2) -> void:
	if by.is_zero_approx():
		return
	var whole := Quaternion(Vector3.UP, by.y) * Quaternion(Vector3.LEFT, by.x)
	var skeleton := get_skeleton()
	var above := _base
	for index in _bones.size():
		var share := weights[index] if index < weights.size() else 0.0
		var bone := _bones[index]
		var posed := above * skeleton.get_bone_pose(bone)
		if share > 0.0:
			var part := Basis(Quaternion.IDENTITY.slerp(whole, share))
			var local := (
				above.basis.orthonormalized().inverse() * part * posed.basis.orthonormalized()
			)
			skeleton.set_bone_pose_rotation(bone, local.orthonormalized().get_rotation_quaternion())
			posed = above * skeleton.get_bone_pose(bone)
		_globals[index] = posed
		above = posed


# The muzzle's pose in the skeleton's space: the last bone of the chain, the bones below it to
# the one the attachment rides (which the turn does not move), and the muzzle's place there.
func _muzzle() -> Transform3D:
	return _globals[_globals.size() - 1] * _below


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
		_globals.resize(_bones.size())
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
	var above := _base
	for index in _bones.size():
		above = above * skeleton.get_bone_pose(_bones[index])
		_globals[index] = above
	return true
