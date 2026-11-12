class_name AimHeadModifier
extends SkeletonModifier3D
## Holds the head level and looking along the aim while the character aims (kit #1334). The aim
## clips carry a head and neck of their own: the pistol's lean the head 12 degrees to the right
## and, blended up or down with the aim's pitch, bend the neck one way and the head the other (a
## zigzag of 23 and 29 degrees aiming 40 down); the crouched rifle looks at the floor, and the
## fists and the rifle standing look straight ahead whatever the pitch. Over the aim layer's spine
## turn the head rode all of it.
##
## After the clips and the spine's turn it puts `neck` and `head` on one line: it works out the
## turn that takes the head from where the chest leaves it (the neck and head at their rest on the
## chest) to looking at `target` with no roll against the world's up, holds it within `max_turn`
## of the chest, and gives the neck `neck_share` of it and the head the rest, both about the same
## axis, so neither bends against the other. Each bone is written once per update, so `influence`
## fades the whole turn in and out. It reads no clock and keeps nothing between frames: the pose
## follows the target and the chest of this very update.
##
## A shouldered weapon wants more than a level head: the eye behind its sights, which is a cheek
## on the stock (kit #1082). With `eye` set (a marker on the weapon, where the aiming eye belongs,
## its -Z along the sight line), the level look is turned on, by one more turn of at most
## `sight_tilt`, until the head's eye (`eye_bone` and `eye_offset`) is as near that place as it
## gets for what a nod, a turned face and a canted head cost: a few steps of least squares from
## the level look,
## every update, so it keeps nothing either. The turn is still one turn shared between the neck
## and the head. It must run after whatever places the weapon in this update (`AimLayer` puts it
## after a `TwoHandHold`'s stance).

# The steps of least squares toward the sights, and the turn a slope is measured over (radians).
const _SIGHT_PASSES := 3
const _SIGHT_STEP := 0.001

## The neck bone (the head's parent) and the head.
@export var neck: StringName = &"neck_01":
	set(value):
		neck = value
		_neck = -2
@export var head: StringName = &"Head":
	set(value):
		head = value
		_neck = -2
## The point the head looks at, in world space.
@export var target := Vector3.ZERO
## The neck's share of the turn (the head takes the rest).
@export_range(0.0, 1.0, 0.01) var neck_share := 0.4
## The most the head may turn off the line the chest gives it, in degrees.
@export_range(0.0, 120.0, 0.5, "suffix:deg") var max_turn := 90.0

@export_group("Sight")
## The bone the eye is counted from (the rig's camera socket, at the middle of the face), and the
## eye from it in the skeleton's rest space: half the distance between the pupils to the
## character's right, an eye's depth behind the brow.
@export var eye_bone: StringName = &"socket_camera":
	set(value):
		eye_bone = value
		_neck = -2
@export var eye_offset := Vector3(-0.032, 0.0, -0.018):
	set(value):
		eye_offset = value
		_neck = -2
## The most the head turns from the level look toward the sights, in degrees.
@export_range(0.0, 90.0, 0.5, "suffix:deg") var sight_tilt := 45.0
## What a radian of the turn weighs against a metre of the eye off the sight line: a nod toward
## the sights (about the side axis), a turn of the face off the line (about the up axis) and a cant
## of the head onto the stock (about the line). The face stays nearest the line where turning it
## costs most; the cheek goes to the stock where the cant costs least.
@export_range(0.0, 2.0, 0.005) var sight_nod := 0.15
@export_range(0.0, 2.0, 0.005) var sight_face := 0.3
@export_range(0.0, 2.0, 0.005) var sight_cant := 0.125
## What a metre of the eye along the sight line (nearer or further from the sights) weighs against
## a metre off it.
@export_range(0.0, 1.0, 0.01) var sight_along := 0.1

## Where the aiming eye belongs on the weapon, its -Z along the sight line; null: a level head.
var eye: Node3D

var _neck := -2
var _head := -1
var _chest := -1
# The head's rest turn in the skeleton's space (looking along +Z, level).
var _head_rest := Quaternion.IDENTITY
# The eye in the head bone's own space.
var _eye_local := Vector3.ZERO


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_neck = -2


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not _find_bones(skeleton):
		return
	var chest := HandPoseModifier.global_pose(skeleton, _chest)
	var neck_rest := skeleton.get_bone_rest(_neck)
	var head_rest := skeleton.get_bone_rest(_head)
	var neck_pose := skeleton.get_bone_pose(_neck)
	var head_pose := skeleton.get_bone_pose(_head)
	# Where the chest leaves the head with the neck and head on its line (their rest turns, the
	# clip's own places).
	var neck_line := chest * Transform3D(neck_rest.basis, neck_pose.origin)
	var head_line := neck_line * Transform3D(head_rest.basis, head_pose.origin)
	var lined := head_line.basis.get_rotation_quaternion()
	var wanted := _looking(skeleton.global_transform.affine_inverse() * target - head_line.origin)
	# The turn from the line to the look, in the skeleton's space, held within `max_turn`.
	var turn := (wanted * lined.inverse()).normalized()
	if eye != null and is_instance_valid(eye) and eye.is_inside_tree():
		var place := skeleton.global_transform.affine_inverse() * eye.global_transform
		turn = _to_sights(turn, neck_line, lined, head_pose.origin, place)
	turn = _held(turn)
	var neck_turn := Quaternion.IDENTITY.slerp(turn, neck_share)
	var chest_turn := chest.basis.get_rotation_quaternion()
	var neck_global := neck_turn * neck_line.basis.get_rotation_quaternion()
	var head_global := turn * lined
	skeleton.set_bone_pose_rotation(_neck, (chest_turn.inverse() * neck_global).normalized())
	skeleton.set_bone_pose_rotation(_head, (neck_global.inverse() * head_global).normalized())


# A turn held within `max_turn`.
func _held(turn: Quaternion) -> Quaternion:
	var angle := turn.get_angle()
	var most := deg_to_rad(max_turn)
	if angle > most and angle > 0.0001:
		return Quaternion.IDENTITY.slerp(turn, most / angle)
	return turn


# The level look `level` turned on toward the sights: the turn `r` (an axis times its angle) that
# leaves the eye nearest `place` (the eye's place on the weapon, in the skeleton's space) for the
# least nod, turned face and cant, by `_SIGHT_PASSES` steps of least squares from no turn.
# `neck_line` and `lined` are the neck and the head on the chest's line, `far` the head bone from
# the neck in the neck's line.
func _to_sights(
	level: Quaternion, neck_line: Transform3D, lined: Quaternion, far: Vector3, place: Transform3D
) -> Quaternion:
	var line := -place.basis.z.normalized()
	var most := deg_to_rad(sight_tilt)
	var r := Vector3.ZERO
	for _pass in _SIGHT_PASSES:
		var now := _sight_miss(r, level, neck_line, lined, far, place.origin, line)
		var slopes: Array[Array] = []
		for axis in 3:
			var stepped := r
			stepped[axis] += _SIGHT_STEP
			var there := _sight_miss(stepped, level, neck_line, lined, far, place.origin, line)
			var slope: Array[Vector3] = []
			for part in now.size():
				slope.append((there[part] - now[part]) / _SIGHT_STEP)
			slopes.append(slope)
		var normal := Basis.IDENTITY
		var down := Vector3.ZERO
		for a in 3:
			var row := Vector3.ZERO
			for b in 3:
				for part in now.size():
					row[b] += (slopes[a][part] as Vector3).dot(slopes[b][part])
			row[a] += 1e-9
			normal = _with_row(normal, a, row)
			for part in now.size():
				down[a] += (slopes[a][part] as Vector3).dot(now[part])
		if absf(normal.determinant()) < 1e-18:
			break
		r -= normal.inverse() * down
		if r.length() > most:
			r = r.normalized() * most
	return (_turn_of(r) * level).normalized()


# What a turn `r` on the level look leaves wrong, as weighted parts: the eye off the sight line,
# the eye along it, the turn itself.
func _sight_miss(
	r: Vector3,
	level: Quaternion,
	neck_line: Transform3D,
	lined: Quaternion,
	far: Vector3,
	place: Vector3,
	line: Vector3
) -> Array[Vector3]:
	var turn := _held((_turn_of(r) * level).normalized())
	var neck_turn := Quaternion.IDENTITY.slerp(turn, neck_share)
	var neck_global := neck_turn * neck_line.basis.get_rotation_quaternion()
	var head_global := turn * lined
	var eye_at := neck_line.origin + neck_global * far + head_global * _eye_local
	var off := eye_at - place
	var along := off.dot(line)
	# The turn about the sight line (a cant), about the up axis beside it (the face off the line)
	# and about the side axis (a nod).
	var upward := (Vector3.UP - line * Vector3.UP.dot(line)).normalized()
	var side := upward.cross(line)
	var turned := Vector3(
		r.dot(side) * sight_nod, r.dot(upward) * sight_face, r.dot(line) * sight_cant
	)
	return [off - line * along, Vector3(along * sight_along, 0.0, 0.0), turned]


func _turn_of(r: Vector3) -> Quaternion:
	var angle := r.length()
	return Quaternion(r / angle, angle) if angle > 1e-9 else Quaternion.IDENTITY


func _with_row(rows: Basis, row: int, value: Vector3) -> Basis:
	rows.x[row] = value.x
	rows.y[row] = value.y
	rows.z[row] = value.z
	return rows


## Where the head's eye is now, in the skeleton's space (the pose the skeleton holds), or the
## head bone's place on a rig with no head.
func eye_place(skeleton: Skeleton3D) -> Vector3:
	if not _find_bones(skeleton):
		return Vector3.ZERO
	return HandPoseModifier.global_pose(skeleton, _head) * _eye_local


# The head's turn in the skeleton's space that looks along `toward` level: its rest turn (which
# looks along +Z with no roll) turned so +Z goes along `toward` and +X stays level.
func _looking(toward: Vector3) -> Quaternion:
	var ahead := toward.normalized() if not toward.is_zero_approx() else Vector3.BACK
	var side := Vector3.UP.cross(ahead)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT.cross(ahead)
	side = side.normalized()
	var up := ahead.cross(side).normalized()
	return (Basis(side, up, ahead).get_rotation_quaternion() * _head_rest).normalized()


func _find_bones(skeleton: Skeleton3D) -> bool:
	if _neck == -2:
		_neck = skeleton.find_bone(neck)
		_head = skeleton.find_bone(head)
		_chest = skeleton.get_bone_parent(_neck) if _neck >= 0 else -1
		if _head < 0 or _chest < 0 or skeleton.get_bone_parent(_head) != _neck:
			_neck = -1
		else:
			var rest := skeleton.get_bone_global_rest(_head)
			_head_rest = rest.basis.get_rotation_quaternion()
			var socket := skeleton.find_bone(eye_bone)
			var at := rest.origin
			if socket >= 0:
				at = skeleton.get_bone_global_rest(socket).origin
			_eye_local = rest.affine_inverse() * (at + eye_offset)
	return _neck >= 0
