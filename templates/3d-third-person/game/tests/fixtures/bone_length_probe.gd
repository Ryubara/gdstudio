class_name BoneLengthProbe
extends SkeletonModifier3D
## The last modifier on a skeleton in a test: each time the modifiers run, it measures every bone's
## length (its distance from its parent in the pose the skin gets) against the rest's, and keeps
## the worst, so a test sees a limb drawn as a rod, which the skeleton forgets after the frame.

## Each run of the modifiers: the worst stretch in metres (the length minus the rest's, either
## way), the bone that had it and the frame it was in (`Engine.get_process_frames()`).
var stretches := PackedFloat32Array()
var bones: Array[StringName] = []
var frames := PackedInt64Array()
## Off: nothing is recorded.
var recording := true
var _rest_lengths := PackedFloat32Array()


## Puts a probe last on `skeleton`.
static func attach(skeleton: Skeleton3D) -> BoneLengthProbe:
	var probe := BoneLengthProbe.new()
	probe.name = "BoneLengthProbe"
	skeleton.add_child(probe)
	return probe


func clear() -> void:
	stretches.clear()
	bones.clear()
	frames.clear()


## The worst stretch recorded, metres.
func worst() -> float:
	var most := 0.0
	for value in stretches:
		most = maxf(most, value)
	return most


## The first record over `limit` metres, as "frame N: bone (x m)", or empty.
func first_over(limit: float) -> String:
	for index in stretches.size():
		if stretches[index] > limit:
			return "frame %d: %s (%.3f m)" % [frames[index], bones[index], stretches[index]]
	return ""


# The helper bones the skin does not follow (the rig's `ik_` bones) and the pelvis, which the
# clips move from the root on purpose.
static func _skipped(skeleton: Skeleton3D, bone: int, parent: int) -> bool:
	var name_here := skeleton.get_bone_name(bone)
	return name_here.begins_with("ik_") or skeleton.get_bone_name(parent) == "root"


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not recording:
		return
	# Stay last: a simulator or a drawing placed later goes before the probe.
	if get_index() != skeleton.get_child_count() - 1:
		skeleton.move_child.call_deferred(self, -1)
	var count := skeleton.get_bone_count()
	if _rest_lengths.size() != count:
		_rest_lengths.resize(count)
		for bone in count:
			_rest_lengths[bone] = skeleton.get_bone_rest(bone).origin.length()
	var most := 0.0
	var which := -1
	for bone in count:
		var parent := skeleton.get_bone_parent(bone)
		if parent < 0 or _skipped(skeleton, bone, parent):
			continue
		var length := skeleton.get_bone_global_pose(bone).origin.distance_to(
			skeleton.get_bone_global_pose(parent).origin
		)
		var off := absf(length - _rest_lengths[bone])
		if off > most:
			most = off
			which = bone
	stretches.append(most)
	bones.append(StringName(skeleton.get_bone_name(which)) if which >= 0 else &"")
	frames.append(Engine.get_process_frames())
