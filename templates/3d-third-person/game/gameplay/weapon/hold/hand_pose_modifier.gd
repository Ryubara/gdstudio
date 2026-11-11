class_name HandPoseModifier
extends SkeletonModifier3D
## Turns the bones of a hand to a `HandPose` after the clip (kit #1001): the clips hold one fist
## for every weapon, so the fingers are closed on the weapon here instead. A second pose can be
## blended over the first (the trigger finger moving from the frame to the trigger). The node's
## own `influence` fades the whole pose in and out; it reads no clock.

## The pose every named bone takes.
@export var pose: HandPose:
	set(value):
		pose = value
		_bones.clear()
## A pose blended over `pose` on the bones it names, by `second_weight`.
@export var second: HandPose
## How far the bones `second` names are on it (0 `pose`, 1 `second`).
@export_range(0.0, 1.0, 0.01) var second_weight := 0.0
## The poses the bones of `second` pass through on their way from `pose`, in order, spread evenly
## over `second_weight` (kit #1036): a trigger finger that would go through the trigger guard on
## the straight way between the two goes round it. Each pose names the bones `second` names.
## Empty: the straight way.
@export var second_way: Array[HandPose] = []
## A pose blended over both on the bones it names, by `open_weight`: the hand opened, as it lets
## go of the weapon or comes back to it.
@export var open: HandPose
@export_range(0.0, 1.0, 0.01) var open_weight := 0.0
## The bones of `open` that open first, over the first `open_first_share` of `open_weight`, with
## the others opening over the rest (and closing before them): fingers hooked over a part let go
## at the knuckles before they straighten. Empty: every bone opens together.
@export var open_first: Array[StringName] = []:
	set(value):
		open_first = value
		_bones.clear()
@export_range(0.05, 0.95, 0.01) var open_first_share := 0.5
## An upper arm lifted away from the body before the pose is put on, and by how many degrees: the
## weapon's arm held out from the thigh while the weapon is carried (`swing_out()`).
@export var swing_bone: StringName = &""
@export_range(0.0, 45.0, 0.1) var swing_degrees := 0.0

# The skeleton's bone index for each name of `pose`, its rotations and then its turns.
var _bones: Dictionary[StringName, int] = {}
var _turned: Dictionary[StringName, int] = {}
# The bones that open first, as a set.
var _first: Dictionary[StringName, bool] = {}


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_bones.clear()


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or pose == null:
		return
	if _bones.is_empty():
		_turned.clear()
		_first.clear()
		for bone_name in open_first:
			_first[bone_name] = true
		for bone_name in pose.rotations:
			_bones[bone_name] = skeleton.find_bone(bone_name)
		for bone_name in pose.turns:
			_turned[bone_name] = skeleton.find_bone(bone_name)
	if swing_bone != &"" and not is_zero_approx(swing_degrees):
		swing_out(skeleton, swing_bone, swing_degrees)
	for bone_name in _turned:
		var bone := _turned[bone_name]
		if bone >= 0:
			skeleton.set_bone_pose_rotation(
				bone, skeleton.get_bone_pose_rotation(bone) * pose.turns[bone_name]
			)
	for bone_name in _bones:
		var bone := _bones[bone_name]
		if bone < 0:
			continue
		var turned := pose.rotations[bone_name]
		if second != null and second_weight > 0.0 and second.rotations.has(bone_name):
			turned = _on_the_way(bone_name, turned)
		if open != null and open_weight > 0.0 and open.rotations.has(bone_name):
			turned = turned.slerp(open.rotations[bone_name], _opened(bone_name))
		skeleton.set_bone_pose_rotation(bone, turned)


# Where `bone_name` is on its way from `turned` (its rotation in `pose`) through `second_way` to
# `second`, `second_weight` of the way along.
func _on_the_way(bone_name: StringName, turned: Quaternion) -> Quaternion:
	if second_way.is_empty():
		return turned.slerp(second.rotations[bone_name], second_weight)
	var legs := second_way.size() + 1
	var leg := mini(floori(second_weight * legs), legs - 1)
	var from := turned if leg == 0 else second_way[leg - 1].rotations[bone_name]
	var to := (
		second.rotations[bone_name] if leg == legs - 1 else second_way[leg].rotations[bone_name]
	)
	return from.slerp(to, second_weight * legs - leg)


# How far `bone_name` is on the open pose: `open_weight`, or its part of it when some bones open
# first.
func _opened(bone_name: StringName) -> float:
	if _first.is_empty():
		return open_weight
	if _first.has(bone_name):
		return minf(open_weight / open_first_share, 1.0)
	return maxf((open_weight - open_first_share) / (1.0 - open_first_share), 0.0)


## Lifts `bone` (an upper arm) `degrees` away from the body, where the skeleton poses it now: it
## turns about its own joint so that the hand at the arm's end moves toward the side of the
## skeleton the arm is on, however the elbow is bent.
static func swing_out(skeleton: Skeleton3D, bone: StringName, degrees: float) -> void:
	var index := skeleton.find_bone(bone)
	var end := arm_end(skeleton, index)
	if end == index:
		return
	var parent := skeleton.get_bone_parent(index)
	var above := global_pose(skeleton, parent) if parent >= 0 else Transform3D.IDENTITY
	var posed := above * skeleton.get_bone_pose(index)
	var hand := posed * skeleton.get_bone_pose(skeleton.get_bone_parent(end))
	hand = hand * skeleton.get_bone_pose(end)
	var turned := swung_out(posed, hand.origin, on_left(skeleton, index), degrees)
	skeleton.set_bone_pose_rotation(
		index, (above.basis.orthonormalized().inverse() * turned).get_rotation_quaternion()
	)


## A bone's pose in the skeleton's space, worked out from the local poses up its parents: the
## pose so far, read without asking the skeleton to update its global poses in the middle of a
## modifier, and right with no scene running too (a test that poses a skeleton by hand).
static func global_pose(skeleton: Skeleton3D, bone: int) -> Transform3D:
	var posed := skeleton.get_bone_pose(bone)
	var parent := skeleton.get_bone_parent(bone)
	while parent >= 0:
		posed = skeleton.get_bone_pose(parent) * posed
		parent = skeleton.get_bone_parent(parent)
	return posed


## The bone two below `index` (an upper arm's hand), or `index` when there is none.
static func arm_end(skeleton: Skeleton3D, index: int) -> int:
	var end := index
	for _level in 2:
		if end < 0 or skeleton.get_bone_children(end).is_empty():
			return index
		end = skeleton.get_bone_children(end)[0]
	return end


## Whether a bone is on the skeleton's -X side at rest (the mannequin's right arm).
static func on_left(skeleton: Skeleton3D, index: int) -> bool:
	return skeleton.get_bone_global_rest(index).origin.x < 0.0


## The basis of an upper arm posed at `posed` (in the skeleton's space) once it is turned `degrees`
## about its joint so that `hand` moves toward its side (-X when `to_left`). A hand already
## straight out to that side stays where it is.
static func swung_out(posed: Transform3D, hand: Vector3, to_left: bool, degrees: float) -> Basis:
	var axis := (hand - posed.origin).cross(Vector3.LEFT if to_left else Vector3.RIGHT)
	if axis.length_squared() < 1e-8:
		return posed.basis
	return Basis(axis.normalized(), deg_to_rad(degrees)) * posed.basis
