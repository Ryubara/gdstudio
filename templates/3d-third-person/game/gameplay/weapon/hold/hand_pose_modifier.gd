class_name HandPoseModifier
extends SkeletonModifier3D
## Turns the bones of a hand to a `HandPose` after the clip (kit #1001): the clips hold one fist
## for every weapon, so the fingers are closed on the weapon here instead. A second pose can be
## blended over the first (the trigger finger moving from the frame to the trigger). The node's
## own `influence` fades the whole pose in and out; it reads no clock.

## The pose every named bone takes.
@export var pose: HandPose:
	set(value):
		_watch(pose, value)
		pose = value
		_dirty = true
## A pose blended over `pose` on the bones it names, by `second_weight`.
@export var second: HandPose:
	set(value):
		_watch(second, value)
		second = value
		_dirty = true
## How far the bones `second` names are on it (0 `pose`, 1 `second`).
@export_range(0.0, 1.0, 0.01) var second_weight := 0.0
## The poses the bones of `second` pass through on their way from `pose`, in order, spread evenly
## over `second_weight` (kit #1036): a trigger finger that would go through the trigger guard on
## the straight way between the two goes round it. Each pose names the bones `second` names.
## Empty: the straight way.
@export var second_way: Array[HandPose] = []:
	set(value):
		for old in second_way:
			_watch(old, null)
		second_way = value
		for new in second_way:
			_watch(null, new)
		_dirty = true
## A pose blended over both on the bones it names, by `open_weight`: the hand opened, as it lets
## go of the weapon or comes back to it, or a thumb moved over to make room for the other hand.
@export var open: HandPose:
	set(value):
		_watch(open, value)
		open = value
		_dirty = true
@export_range(0.0, 1.0, 0.01) var open_weight := 0.0
## A pose the bones it names pass through half-way to `open` (kit #1084): the right thumb lifts
## clear of the weapon's frame before it swings over to the other hand's thumb, where the
## straight blend took its middle bone through the frame's edge.
@export var open_via: HandPose:
	set(value):
		_watch(open_via, value)
		open_via = value
		_dirty = true
## The bones of `open` that open first, over the first `open_first_share` of `open_weight`, with
## the others opening over the rest (and closing before them): fingers hooked over a part let go
## at the knuckles before they straighten. Empty: every bone opens together.
@export var open_first: Array[StringName] = []:
	set(value):
		open_first = value
		_dirty = true
@export_range(0.05, 0.95, 0.01) var open_first_share := 0.5
## Every bone opens together though `open_first` names some: fingers closing round a part they
## are not hooked over (a magazine's front) curl as one.
@export var open_together := false
## An upper arm lifted away from the body before the pose is put on, and by how many degrees: the
## weapon's arm held out from the thigh while the weapon is carried (`swing_out()`).
@export var swing_bone: StringName = &""
@export_range(0.0, 45.0, 0.1) var swing_degrees := 0.0

# The poses laid out once per bone (kit #1178: read from the poses' dictionaries a bone at a time,
# the two hands of a rifle were about half its hold's cost in the web build): the skeleton's
# index of each bone `pose` names, its rotation in each pose (its own where a pose leaves it out)
# and how it opens (0 with `open_weight`, 1 first, 2 after); then the turned bones and turns.
var _dirty := true
var _indexes := PackedInt32Array()
var _rotations: Array[Quaternion] = []
var _seconds: Array[Quaternion] = []
var _has_second := PackedByteArray()
# Each bone's rotation in each pose of `second_way`, `second_way.size()` a bone.
var _ways: Array[Quaternion] = []
var _opens: Array[Quaternion] = []
var _opening := PackedByteArray()
# Each bone's rotation in `open_via`, where it names the bone.
var _open_vias: Array[Quaternion] = []
var _has_open_via := PackedByteArray()
var _turned := PackedInt32Array()
var _turns: Array[Quaternion] = []


func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_dirty = true


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or pose == null:
		return
	if _dirty:
		_lay_out(skeleton)
	if swing_bone != &"" and not is_zero_approx(swing_degrees):
		swing_out(skeleton, swing_bone, swing_degrees)
	for index in _turned.size():
		var bone := _turned[index]
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * _turns[index])
	var blend := second != null and second_weight > 0.0
	var opened := open != null and open_weight > 0.0
	if not blend and not opened:
		for index in _indexes.size():
			skeleton.set_bone_pose_rotation(_indexes[index], _rotations[index])
		return
	var shares := [
		open_weight,
		minf(open_weight / open_first_share, 1.0),
		maxf((open_weight - open_first_share) / (1.0 - open_first_share), 0.0),
	]
	if open_first.is_empty() or open_together:
		shares = [open_weight, open_weight, open_weight]
	for index in _indexes.size():
		var turned := _rotations[index]
		if blend and _has_second[index] == 1:
			turned = _on_the_way(index, turned)
		if opened and _opening[index] < 3:
			var share: float = shares[_opening[index]]
			if _has_open_via[index] == 0:
				turned = turned.slerp(_opens[index], share)
			elif share < 0.5:
				turned = turned.slerp(_open_vias[index], share * 2.0)
			else:
				turned = _open_vias[index].slerp(_opens[index], share * 2.0 - 1.0)
		skeleton.set_bone_pose_rotation(_indexes[index], turned)


# Where the bone at `index` is on its way from `turned` (its rotation in `pose`) through
# `second_way` to `second`, `second_weight` of the way along.
func _on_the_way(index: int, turned: Quaternion) -> Quaternion:
	var stops := second_way.size()
	if stops == 0:
		return turned.slerp(_seconds[index], second_weight)
	var legs := stops + 1
	var leg := mini(floori(second_weight * legs), legs - 1)
	var from := turned if leg == 0 else _ways[index * stops + leg - 1]
	var to := _seconds[index] if leg == legs - 1 else _ways[index * stops + leg]
	return from.slerp(to, second_weight * legs - leg)


func _lay_out(skeleton: Skeleton3D) -> void:
	_dirty = false
	_indexes.clear()
	_rotations.clear()
	_seconds.clear()
	_has_second.clear()
	_ways.clear()
	_opens.clear()
	_opening.clear()
	_open_vias.clear()
	_has_open_via.clear()
	_turned.clear()
	_turns.clear()
	var first := {}
	for bone_name in open_first:
		first[bone_name] = true
	for bone_name in pose.rotations:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var own := pose.rotations[bone_name]
		_indexes.append(bone)
		_rotations.append(own)
		var in_second := second != null and second.rotations.has(bone_name)
		_has_second.append(1 if in_second else 0)
		_seconds.append(second.rotations[bone_name] if in_second else own)
		# A way that leaves a bone out keeps it where the pose before it has it.
		var before := own
		for stop in second_way:
			if in_second and stop != null and stop.rotations.has(bone_name):
				before = stop.rotations[bone_name]
			_ways.append(before)
		var in_open := open != null and open.rotations.has(bone_name)
		_opens.append(open.rotations[bone_name] if in_open else own)
		var via_open := in_open and open_via != null and open_via.rotations.has(bone_name)
		_has_open_via.append(1 if via_open else 0)
		_open_vias.append(open_via.rotations[bone_name] if via_open else own)
		var opening := 3
		if in_open:
			opening = 0 if open_first.is_empty() else (1 if first.has(bone_name) else 2)
		_opening.append(opening)
	for bone_name in pose.turns:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			_turned.append(bone)
			_turns.append(pose.turns[bone_name])


# Lays the poses out again when one of them changes.
func _watch(old: HandPose, new: HandPose) -> void:
	if old != null and old.changed.is_connected(_on_pose_changed):
		old.changed.disconnect(_on_pose_changed)
	if new != null and not new.changed.is_connected(_on_pose_changed):
		new.changed.connect(_on_pose_changed)


func _on_pose_changed() -> void:
	_dirty = true


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
