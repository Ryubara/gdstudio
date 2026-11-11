class_name AimOffsetModifier
extends SkeletonModifier3D
## Turns a chain of spine bones after the clips so the weapon's muzzle points at a point (kit
## #1253): it reads where the muzzle points in this very update (the move's pose, the aim clips
## and the grip's wrist turn under it), works out the turn that puts it on the point, a yaw about
## the model's up axis and then a pitch, holds both within its limits and shares the turn out over
## the chain's bones by their weights. The arms, the hands and the weapon ride the spine, so they
## follow; the support hand that reaches for the weapon after this (`HoldArm`) finds it there.
##
## Every bone's share is a part of one rotation about one axis, so the parts add up to exactly
## the whole turn: the muzzle's direction is right after one pass. A second pass takes the muzzle's
## own move (it swings round the spine) into account, for a point that is near.
##
## While `hold_turn` is on (a shot's recoil playing), the turn found before is kept and only moved
## by as much as the point moved since, so the recoil the clip shows is not turned away; when it
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
## How far the muzzle pointed from the point after the last update, in degrees (before
## `influence`; 0 when it reached it, more when a limit held it).
var miss := 0.0

var _bones := PackedInt32Array()
var _attachment: BoneAttachment3D
var _bone := -1
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
	var wanted := _solve(skeleton, point)
	if hold_turn:
		var angles := _angles(_aimed_direction(skeleton, point))
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
	_apply(skeleton, wanted)
	if not hold_turn:
		for _pass in passes - 1:
			var more := _solve(skeleton, point)
			_apply(skeleton, more)
			wanted += more
	turn = wanted
	var now := _muzzle(skeleton)
	miss = rad_to_deg((-now.basis.z).normalized().angle_to(_aimed_direction(skeleton, point)))


# The turn that puts the muzzle, as it is posed now, along the aimed direction: a pitch (x) about
# the model's side axis, the chest bending forward or back, then a yaw (y) about its up axis.
# Both are exact for the direction: the pitch brings the muzzle to the aim's elevation, the yaw to
# its heading.
func _solve(skeleton: Skeleton3D, point: Vector3) -> Vector2:
	var pointing := (-_muzzle(skeleton).basis.z).normalized()
	var aimed := _aimed_direction(skeleton, point)
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
func _aimed_direction(skeleton: Skeleton3D, point: Vector3) -> Vector3:
	var toward := point - _muzzle(skeleton).origin
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


# Turns the chain by `by` (pitch, yaw): the pitch shared out over the bones (parts of one
# rotation about one axis, so they add up to it exactly), then the yaw the same way.
func _apply(skeleton: Skeleton3D, by: Vector2) -> void:
	if not is_zero_approx(by.x):
		_turn_chain(skeleton, Vector3.LEFT, by.x)
	if not is_zero_approx(by.y):
		_turn_chain(skeleton, Vector3.UP, by.y)


func _turn_chain(skeleton: Skeleton3D, axis: Vector3, angle: float) -> void:
	for index in _bones.size():
		var share := weights[index] if index < weights.size() else 0.0
		if share <= 0.0:
			continue
		var bone := _bones[index]
		var posed := HandPoseModifier.global_pose(skeleton, bone).basis.orthonormalized()
		var parent := skeleton.get_bone_parent(bone)
		var above := Basis.IDENTITY
		if parent >= 0:
			above = HandPoseModifier.global_pose(skeleton, parent).basis.orthonormalized()
		var turned := Basis(axis, angle * share) * posed
		skeleton.set_bone_pose_rotation(
			bone, (above.inverse() * turned).orthonormalized().get_rotation_quaternion()
		)


# The muzzle's pose in the skeleton's space, from the bone its attachment rides.
func _muzzle(skeleton: Skeleton3D) -> Transform3D:
	return HandPoseModifier.global_pose(skeleton, _bone) * _offset


# Finds the chain's bones, the attachment the muzzle rides and the muzzle's place on its bone.
func _find_parts(skeleton: Skeleton3D) -> bool:
	if _bones.is_empty():
		for bone_name in chain:
			var found := skeleton.find_bone(bone_name)
			if found >= 0:
				_bones.append(found)
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
	if _bone < 0:
		return false
	# The muzzle is fixed on its attachment: its place there, read from the two nodes.
	_offset = _attachment.global_transform.affine_inverse() * muzzle.global_transform
	return true
