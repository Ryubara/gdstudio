class_name HoldArm
extends SkeletonModifier3D
## Brings a hand to a point of the weapon the other hand carries, in the pose of this very update
## (kit #1001): a two-bone reach of the arm, then the hand turned to the point's rotation. The
## weapon rides a bone, so the point is that bone's pose times a fixed offset, read here after
## the clip and the grip's wrist turn.
##
## The engine's `TwoBoneIK3D` aimed at a node is a frame late for this: it uses the place its
## target had before the skeleton's update, and whatever follows the skeleton (a marker under a
## `BoneAttachment3D`, a node a modifier moves) moves during it, so the hand trailed the pistol by
## what the gun moved in a frame (the whole way after a jump of the pose, 52 cm in a probe).

## The bones that reach: the upper arm, the forearm and the hand.
@export var arm: Array[StringName] = [&"upperarm_l", &"lowerarm_l", &"hand_l"]
## The bone the weapon rides.
@export var bone: StringName = &"hand_r"
## Where the hand bone sits, in the weapon's bone's space (the weapon's seat times the marker).
@export var offset := Transform3D.IDENTITY
## Where the elbow points, in the skeleton's space.
@export var elbow := Vector3(0.6, 0.6, 0.2)

## How far the hand stopped from the point on the last update, in metres (0 when it reached).
var shortfall := 0.0

var _bones := PackedInt32Array()


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_bones.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or arm.size() != 3:
		return
	if _bones.is_empty():
		for bone_name in arm:
			_bones.append(skeleton.find_bone(bone_name))
		_bones.append(skeleton.find_bone(bone))
	if _bones.has(-1):
		return
	# Every pose is worked out from the local ones, and only three rotations are written back.
	var goal := HandPoseModifier.global_pose(skeleton, _bones[3]) * offset
	var above := HandPoseModifier.global_pose(skeleton, skeleton.get_bone_parent(_bones[0]))
	var fore_local := skeleton.get_bone_pose(_bones[1])
	var hand_local := skeleton.get_bone_pose(_bones[2])
	var upper := above * skeleton.get_bone_pose(_bones[0])
	var fore := upper * fore_local
	var hand := fore * hand_local
	var upper_length := upper.origin.distance_to(fore.origin)
	var fore_length := fore.origin.distance_to(hand.origin)
	var to_goal := goal.origin - upper.origin
	var reach := clampf(
		to_goal.length(),
		absf(upper_length - fore_length) + 0.001,
		upper_length + fore_length - 0.001
	)
	shortfall = absf(to_goal.length() - reach)
	var along := to_goal.normalized()
	# The elbow lies on a circle about the line to the goal; the pole picks the point on it.
	var forward := (
		(upper_length * upper_length - fore_length * fore_length + reach * reach) / (2.0 * reach)
	)
	var out := sqrt(maxf(upper_length * upper_length - forward * forward, 0.0))
	var pole := elbow - upper.origin
	pole = (pole - along * pole.dot(along)).normalized()
	var elbow_at := upper.origin + along * forward + pole * out
	var wrist_at := upper.origin + along * reach
	upper.basis = _aimed(upper.basis, fore.origin - upper.origin, elbow_at - upper.origin)
	fore = upper * fore_local
	hand = fore * hand_local
	fore.basis = _aimed(fore.basis, hand.origin - fore.origin, wrist_at - fore.origin)
	hand = fore * hand_local
	hand.basis = goal.basis.orthonormalized()
	skeleton.set_bone_pose_rotation(_bones[0], _local(above.basis, upper.basis))
	skeleton.set_bone_pose_rotation(_bones[1], _local(upper.basis, fore.basis))
	skeleton.set_bone_pose_rotation(_bones[2], _local(fore.basis, hand.basis))


# A bone's rotation in its parent's space, from the two bases in the skeleton's space.
func _local(parent: Basis, child: Basis) -> Quaternion:
	return (parent.orthonormalized().inverse() * child.orthonormalized()).get_rotation_quaternion()


# The basis turned the short way so that `from` points along `to`.
func _aimed(turned: Basis, from: Vector3, to: Vector3) -> Basis:
	if from.is_zero_approx() or to.is_zero_approx():
		return turned
	return Basis(Quaternion(from.normalized(), to.normalized())) * turned
