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

var _neck := -2
var _head := -1
var _chest := -1
# The head's rest turn in the skeleton's space (looking along +Z, level).
var _head_rest := Quaternion.IDENTITY


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
	var angle := turn.get_angle()
	var most := deg_to_rad(max_turn)
	if angle > most and angle > 0.0001:
		turn = Quaternion.IDENTITY.slerp(turn, most / angle)
	var neck_turn := Quaternion.IDENTITY.slerp(turn, neck_share)
	var chest_turn := chest.basis.get_rotation_quaternion()
	var neck_global := neck_turn * neck_line.basis.get_rotation_quaternion()
	var head_global := turn * lined
	skeleton.set_bone_pose_rotation(_neck, (chest_turn.inverse() * neck_global).normalized())
	skeleton.set_bone_pose_rotation(_head, (neck_global.inverse() * head_global).normalized())


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
			_head_rest = skeleton.get_bone_global_rest(_head).basis.get_rotation_quaternion()
	return _neck >= 0
