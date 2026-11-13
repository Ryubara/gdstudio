class_name HandFloor
extends SkeletonModifier3D
## Keeps both hands over the floor (kit #1356): when a bone of either hand is lower than
## `clearance` over `floor_height`, both arms are turned up at the shoulder by the same rise, the
## hands keeping their turn, so the pistol in one hand and the other hand on it go up together.
##
## A lying body's aim comes in by blending its prone idle (the fists on the floor) into the
## prone aim (the arms stretched, the hands just over the floor), and a blend of the arms'
## rotations between two poses with the hands at the floor takes the left hand under it on the
## way: 59 mm on `form_female` and 70 mm on `form_male` at a third of the blend. Turned up at
## the shoulder the arms keep the clips' shape, and where no hand is that low (both clips' own
## poses) nothing moves.

## The name a weapon hold gives it on the skeleton.
const NODE_NAME := &"HoldHandFloor"
## How far into a lying aim the hands are fully kept over the floor: from nothing at no aim, so a
## crawl's fists are never moved.
const FLOOR_FROM_AIM := 0.1

## The upper bone of each arm; its hand is two bones below it.
@export var arms: Array[StringName] = [&"upperarm_r", &"upperarm_l"]
## The lowest any bone of either hand may be over the floor, in metres. A finger's skin is about
## 7 mm under its bone; the prone idle's fists rest with their lowest bones 4 to 6 mm up.
@export_range(0.0, 0.05, 0.001, "suffix:m") var clearance := 0.005
## The floor's height in the skeleton's space, in metres (the body's own point, written by whoever
## drives this before each update).
var floor_height := 0.0
## How far the hands were raised on the last update, in metres (0 when they were over the floor).
var lifted := 0.0

# For each arm: the upper arm, the forearm and the hand; and every bone of each hand, parents
# first.
var _chains: Array[PackedInt32Array] = []
var _hands: Array[PackedInt32Array] = []


## A floor keeper for a hold's two arms, by their upper bones (an empty one keeps the default).
static func made(right: StringName, left: StringName) -> HandFloor:
	var keeper := HandFloor.new()
	keeper.name = NODE_NAME
	if not right.is_empty():
		keeper.arms[0] = right
	if not left.is_empty():
		keeper.arms[1] = left
	return keeper


## Its weight in a hold: `keep` (the hold's elbow keep) by how far the aim has come, all of it
## from `FLOOR_FROM_AIM`.
static func share(keep: float, aim: float) -> float:
	return keep * clampf(aim / FLOOR_FROM_AIM, 0.0, 1.0)


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_chains.clear()
	_hands.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _chains.is_empty() and not _find_bones(skeleton):
		return
	var lowest := INF
	var poses: Array[Transform3D] = []
	for index in _chains.size():
		var hand := HandPoseModifier.global_pose(skeleton, _chains[index][2])
		poses.append(hand)
		lowest = minf(lowest, _lowest_of_hand(skeleton, _hands[index], hand))
	lifted = maxf(floor_height + clearance - lowest, 0.0)
	if lifted <= 0.0:
		return
	for index in _chains.size():
		_raise(skeleton, _chains[index], poses[index], lifted)


# The lowest any bone of a hand is, in the skeleton's space: `bones` is the hand and every bone
# under it, parents first, and `hand` the hand's pose.
static func _lowest_of_hand(
	skeleton: Skeleton3D, bones: PackedInt32Array, hand: Transform3D
) -> float:
	var posed := {bones[0]: hand}
	var lowest := hand.origin.y
	for bone in bones.slice(1):
		var parent := skeleton.get_bone_parent(bone)
		var from: Transform3D = (
			posed[parent] if posed.has(parent) else HandPoseModifier.global_pose(skeleton, parent)
		)
		var at := from * skeleton.get_bone_pose(bone)
		posed[bone] = at
		lowest = minf(lowest, at.origin.y)
	return lowest


# Turns the arm `chain` up at the shoulder so its hand (posed `hand`) is `rise` higher, and turns
# the hand back to the way it faced.
static func _raise(
	skeleton: Skeleton3D, chain: PackedInt32Array, hand: Transform3D, rise: float
) -> void:
	var above := HandPoseModifier.global_pose(skeleton, skeleton.get_bone_parent(chain[0]))
	var upper := above * skeleton.get_bone_pose(chain[0])
	var reach := hand.origin - upper.origin
	var axis := reach.cross(Vector3.UP)
	if axis.is_zero_approx() or reach.is_zero_approx():
		return
	var length := reach.length()
	var angle := asin(clampf((reach.y + rise) / length, -1.0, 1.0)) - asin(reach.y / length)
	var turn := Basis(axis.normalized(), angle)
	var fore := upper * skeleton.get_bone_pose(chain[1])
	var turned_upper := turn * upper.basis.orthonormalized()
	var turned_fore := turn * fore.basis.orthonormalized()
	skeleton.set_bone_pose_rotation(chain[0], _local(above.basis, turned_upper))
	skeleton.set_bone_pose_rotation(chain[2], _local(turned_fore, hand.basis))


static func _local(parent: Basis, child: Basis) -> Quaternion:
	return (parent.orthonormalized().inverse() * child.orthonormalized()).get_rotation_quaternion()


func _find_bones(skeleton: Skeleton3D) -> bool:
	for upper_name in arms:
		var upper := skeleton.find_bone(upper_name)
		var hand := HandPoseModifier.arm_end(skeleton, upper) if upper >= 0 else -1
		if upper < 0 or hand == upper:
			_chains.clear()
			_hands.clear()
			return false
		var bones := PackedInt32Array([hand])
		for bone in skeleton.get_bone_count():
			var cursor := skeleton.get_bone_parent(bone)
			while cursor >= 0 and cursor != hand:
				cursor = skeleton.get_bone_parent(cursor)
			if cursor == hand:
				bones.append(bone)
		_chains.append(PackedInt32Array([upper, skeleton.get_bone_parent(hand), hand]))
		_hands.append(bones)
	return true
