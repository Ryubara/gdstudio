class_name OneHandStance
extends SkeletonModifier3D
## The body of a one-handed shot (kit #1085), put on the aim clips after the tree: the chest turned
## side-on (the shooting shoulder forward, the head turned back to the target), the shooting arm
## reached out nearly straight along the barrel's line, the free arm held a little out for
## balance, and the shot's kick taken by the wrist (the muzzle climbs) and the elbow (the hand
## comes back and up). The tree leaves the free arm on the locomotion clip while it aims
## (`CharacterAnimation`'s one-handed filter), so it hangs and swings as the body moves.
##
## The barrel keeps the direction the aim clip gives it, so the shot and the look range are the
## two-handed hold's; only where the hand is changes. `WeaponHold` makes this node, puts it before
## the grip on the skeleton and sets `influence` (how far the character aims, off for a reload)
## and `kick`. It reads no clock; it is cosmetic and never sent over a network.

## The bones that turn the chest side-on, from the hips up, each by an equal share.
@export var turn_bones: Array[StringName] = [&"spine_01", &"spine_02", &"spine_03"]
## How far the chest turns side-on, in degrees about the body's up axis (positive brings the
## shooting shoulder forward; the right shoulder for a right hand).
@export_range(-80.0, 80.0, 0.5, "suffix:deg") var side_on := 35.0
## The bones that turn the head back to the target, each by an equal share of `side_on`.
@export var head_bones: Array[StringName] = [&"neck_01", &"head"]
## How much of the chest's turn the head turns back (1 faces the target as before).
@export_range(0.0, 1.0, 0.01) var head_back := 1.0

## The shooting arm: the upper arm, the forearm and the hand that holds the weapon.
@export var arm: Array[StringName] = [&"upperarm_r", &"lowerarm_r", &"hand_r"]
## How far from the shoulder the wrist is, as a share of the arm's length (1 locks the elbow).
@export_range(0.7, 1.0, 0.005) var reach := 0.96
## Where the elbow points, in the skeleton's space (down and out to the shooting side).
@export var elbow := Vector3(-0.5, -1.0, 0.0)
## The barrel's direction and the weapon's up in the hand bone's space as the aim clip leaves it
## (before the grip's wrist turn); `WeaponHold` works them out from the weapon's seat.
@export var barrel := Vector3.FORWARD
@export var weapon_up := Vector3.UP
## The wrist moved from the barrel's line through the shoulder, in the skeleton's space (up lifts
## the sights toward the eye).
@export var hand_offset := Vector3.ZERO

## The free arm's upper arm and how many degrees it is held out from the body for balance.
@export var free_arm: StringName = &"upperarm_l"
@export_range(0.0, 45.0, 0.5, "suffix:deg") var free_arm_out := 10.0

## How far into a shot's kick the arm is (1 the moment of the shot, 0 settled).
@export_range(0.0, 1.0, 0.01) var kick := 0.0
## How many degrees the muzzle climbs at the wrist at the height of the kick.
@export_range(0.0, 45.0, 0.5, "suffix:deg") var kick_climb := 10.0
## How far the wrist comes back toward the shoulder (the elbow bends) and up at the kick's height,
## in metres.
@export_range(0.0, 0.2, 0.005, "suffix:m") var kick_back := 0.05
@export_range(0.0, 0.2, 0.005, "suffix:m") var kick_up := 0.03

var _turned := PackedInt32Array()
var _heads := PackedInt32Array()
var _arm := PackedInt32Array()


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_arm.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or arm.size() != 3:
		return
	if _arm.is_empty():
		_turned = _find(skeleton, turn_bones)
		_heads = _find(skeleton, head_bones)
		_arm = _find(skeleton, arm)
	if _arm.has(-1):
		return
	# The barrel's line as the aim clip points it, before the chest turns under it.
	var hand_before := HandPoseModifier.global_pose(skeleton, _arm[2])
	var line := (hand_before.basis * barrel).normalized()
	var gun_up := (hand_before.basis * weapon_up).normalized()
	_turn(skeleton, _turned, deg_to_rad(side_on))
	_turn(skeleton, _heads, -deg_to_rad(side_on) * head_back)
	var climbed := Basis(line.cross(gun_up).normalized(), deg_to_rad(kick_climb) * kick)
	var goal := Transform3D(climbed * hand_before.basis.orthonormalized(), Vector3.ZERO)
	var above := HandPoseModifier.global_pose(skeleton, skeleton.get_bone_parent(_arm[0]))
	var shoulder := (above * skeleton.get_bone_pose(_arm[0])).origin
	goal.origin = (
		shoulder
		+ line * (arm_length(skeleton) * reach - kick_back * kick)
		+ hand_offset
		+ Vector3.UP * kick_up * kick
	)
	reach_arm(skeleton, _arm, goal, elbow, above)
	if free_arm != &"" and free_arm_out > 0.0:
		HandPoseModifier.swing_out(skeleton, free_arm, free_arm_out)


## The shooting arm's length (shoulder to elbow to wrist), in metres: the forearm's and the hand's
## places in their parents (the rig's bones are not scaled).
func arm_length(skeleton: Skeleton3D) -> float:
	return (
		skeleton.get_bone_pose_position(_arm[1]).length()
		+ skeleton.get_bone_pose_position(_arm[2]).length()
	)


## Reaches the three bones `bones` (upper arm, forearm, hand) so the hand bone is at `goal` (in
## the skeleton's space) with its rotation, the elbow toward `pole`; a goal out of reach is met as
## near as the arm goes. `above` is the upper arm's parent's pose in the skeleton's space.
static func reach_arm(
	skeleton: Skeleton3D,
	bones: PackedInt32Array,
	goal: Transform3D,
	pole: Vector3,
	above: Transform3D
) -> void:
	var fore_local := skeleton.get_bone_pose(bones[1])
	var hand_local := skeleton.get_bone_pose(bones[2])
	var upper := above * skeleton.get_bone_pose(bones[0])
	var fore := upper * fore_local
	var hand := fore * hand_local
	var upper_length := upper.origin.distance_to(fore.origin)
	var fore_length := fore.origin.distance_to(hand.origin)
	var to_goal := goal.origin - upper.origin
	var distance := clampf(
		to_goal.length(),
		absf(upper_length - fore_length) + 0.001,
		upper_length + fore_length - 0.001
	)
	var along := to_goal.normalized()
	var forward := (
		(upper_length * upper_length - fore_length * fore_length + distance * distance)
		/ (2.0 * distance)
	)
	var out := sqrt(maxf(upper_length * upper_length - forward * forward, 0.0))
	var side := pole - along * pole.dot(along)
	side = side.normalized() if not side.is_zero_approx() else Vector3.DOWN
	var elbow_at := upper.origin + along * forward + side * out
	var wrist_at := upper.origin + along * distance
	upper.basis = _aimed(upper.basis, fore.origin - upper.origin, elbow_at - upper.origin)
	fore = upper * fore_local
	hand = fore * hand_local
	fore.basis = _aimed(fore.basis, hand.origin - fore.origin, wrist_at - fore.origin)
	skeleton.set_bone_pose_rotation(bones[0], _local(above.basis, upper.basis))
	skeleton.set_bone_pose_rotation(bones[1], _local(upper.basis, fore.basis))
	skeleton.set_bone_pose_rotation(bones[2], _local(fore.basis, goal.basis))


# Turns each bone of `bones` by an equal share of `angle` about the skeleton's up axis, in order
# from the root up (each turn carries the bones above it). A bone that is the last one's child
# takes its parent's pose from the last turn instead of walking up the skeleton again.
static func _turn(skeleton: Skeleton3D, bones: PackedInt32Array, angle: float) -> void:
	if bones.is_empty() or is_zero_approx(angle):
		return
	var share := Basis(Vector3.UP, angle / bones.size())
	var last := -1
	var last_pose := Transform3D.IDENTITY
	for bone in bones:
		if bone < 0:
			continue
		var parent := skeleton.get_bone_parent(bone)
		var above := last_pose
		if parent != last or last < 0:
			above = (
				HandPoseModifier.global_pose(skeleton, parent)
				if parent >= 0
				else Transform3D.IDENTITY
			)
		var local := skeleton.get_bone_pose(bone)
		var turned := _local(above.basis, share * above.basis * local.basis)
		skeleton.set_bone_pose_rotation(bone, turned)
		last = bone
		last_pose = above * Transform3D(Basis(turned), local.origin)


static func _find(skeleton: Skeleton3D, names: Array[StringName]) -> PackedInt32Array:
	var found := PackedInt32Array()
	for bone_name in names:
		found.append(skeleton.find_bone(bone_name))
	return found


# A bone's rotation in its parent's space, from the two bases in the skeleton's space.
static func _local(parent: Basis, child: Basis) -> Quaternion:
	return (parent.orthonormalized().inverse() * child.orthonormalized()).get_rotation_quaternion()


# The basis turned the short way so that `from` points along `to`.
static func _aimed(turned: Basis, from: Vector3, to: Vector3) -> Basis:
	if from.is_zero_approx() or to.is_zero_approx():
		return turned
	return Basis(Quaternion(from.normalized(), to.normalized())) * turned
