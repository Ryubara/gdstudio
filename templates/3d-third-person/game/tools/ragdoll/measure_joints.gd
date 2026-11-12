## Measures how far every joint of the ragdoll turns in the animation clips, to see how far they go
## past the table's limits. The limits themselves are a person's (`CharacterRagdoll.BODIES`,
## sources in docs/engines/godot/ragdoll.md#limits); a clip may hold a joint outside them, and the
## pose is pushed inside them when the character goes limp. For each joint of the table it samples
## every clip the player plays by default (`CharacterAnimation`'s clips) on both mannequins and
## prints, relative to the joint's rest frame:
##   - a cone: the swing's centre (the mean direction of the bone) as a rotation, the widest swing
##     from it and the twist range around the bone, next to the table's swing and twist;
##   - a hinge (a knee or an elbow): the bend range, and the largest lean sideways and roll about
##     the bone (a hinge has neither), next to the table's range.
## The cones' `centre` values in the table come from this (the mean direction of the clips). A
## number past the table's is a pose the clamp will move; a large one is a clip worth looking at.
##
## Run it headless from a game made from the template:
## `<godot> --headless --path game -s res://tools/ragdoll/measure_joints.gd`
## It lives in tools/, which the export leaves out.
extends SceneTree

const MODELS := [
	CharacterBodies.FEMALE,
	CharacterBodies.MALE,
]
const LIBRARIES: Dictionary[StringName, String] = {
	&"ual1": "res://assets/animation/universal/ual1.glb",
	&"ual2": "res://assets/animation/universal/ual2.glb",
}
## Samples per second of each clip.
const RATE := 15.0


func _initialize() -> void:
	var samples := {}
	for path: String in MODELS:
		_sample_model(path, samples)
	for entry: Dictionary in CharacterRagdoll.BODIES:
		if entry.joint == &"":
			continue
		var turns: Array = samples[entry.bone]
		if entry.joint == &"hinge":
			_report_hinge(entry, turns)
		else:
			_report_cone(entry, turns)
	quit()


func _sample_model(path: String, samples: Dictionary) -> void:
	var holder := Node3D.new()
	get_root().add_child(holder)
	var slot := CharacterModel.new()
	holder.add_child(slot)
	var rig := (load(path) as PackedScene).instantiate() as Node3D
	slot.add_child(rig)
	var skeleton := slot.skeleton()
	var ragdoll := CharacterRagdoll.new()
	ragdoll.model = slot
	var rest := {}
	for entry: Dictionary in CharacterRagdoll.BODIES:
		rest[entry.bone] = _rest(ragdoll, slot, entry.bone)
		if not samples.has(entry.bone):
			samples[entry.bone] = []
	for clip in _player_clips():
		var parts := String(clip).split("/")
		if parts.size() != 2 or not LIBRARIES.has(StringName(parts[0])):
			continue
		var library := load(LIBRARIES[StringName(parts[0])]) as AnimationLibrary
		var animation := library.get_animation(parts[1])
		var steps := maxi(int(animation.length * RATE), 1)
		for step in steps + 1:
			_pose(skeleton, animation, animation.length * step / steps)
			for entry: Dictionary in CharacterRagdoll.BODIES:
				if entry.joint == &"":
					continue
				var parent := _parent_body(skeleton, entry.bone)
				var child_now := _body_now(skeleton, entry.bone, rest[entry.bone])
				var parent_now := _body_now(skeleton, parent, rest[parent])
				var rest_turn: Basis = rest[parent].basis.inverse() * rest[entry.bone].basis
				samples[entry.bone].append(rest_turn.inverse() * (parent_now.inverse() * child_now))
	ragdoll.free()
	get_root().remove_child(holder)
	holder.free()


# The clips the player's `CharacterAnimation` plays by default: a character dies in one of these.
func _player_clips() -> Array[StringName]:
	var animation := CharacterAnimation.new()
	var found: Array[StringName] = []
	for property in animation.get_property_list():
		if String(property["name"]).ends_with("_clip"):
			found.append(animation.get(property["name"]))
	animation.free()
	return found


# Puts the clip's pose at `time` on the skeleton, straight from its tracks.
func _pose(skeleton: Skeleton3D, animation: Animation, time: float) -> void:
	skeleton.reset_bone_poses()
	for track in animation.get_track_count():
		var bone := skeleton.find_bone(
			String(animation.track_get_path(track).get_concatenated_subnames())
		)
		if bone < 0:
			continue
		match animation.track_get_type(track):
			Animation.TYPE_ROTATION_3D:
				skeleton.set_bone_pose_rotation(
					bone, animation.rotation_track_interpolate(track, time)
				)
			Animation.TYPE_POSITION_3D:
				skeleton.set_bone_pose_position(
					bone, animation.position_track_interpolate(track, time)
				)


func _rest(ragdoll: CharacterRagdoll, slot: CharacterModel, bone: StringName) -> Transform3D:
	ragdoll.set(&"model", slot)
	return ragdoll.rest_body(bone)


# The body's basis in the skeleton's space in the pose now: the bone's turn from rest applied to
# the body's rest basis.
func _body_now(skeleton: Skeleton3D, bone: StringName, body_rest: Transform3D) -> Basis:
	var index := skeleton.find_bone(bone)
	var turn := (
		_global_pose(skeleton, index).basis * skeleton.get_bone_global_rest(index).basis.inverse()
	)
	return turn * body_rest.basis


# The bone's pose in the skeleton's space, from the local poses up the chain (the skeleton works
# its global poses out later, not at once after a pose is set).
func _global_pose(skeleton: Skeleton3D, index: int) -> Transform3D:
	var pose := skeleton.get_bone_pose(index)
	var parent := skeleton.get_bone_parent(index)
	return _global_pose(skeleton, parent) * pose if parent >= 0 else pose


func _parent_body(skeleton: Skeleton3D, bone: StringName) -> StringName:
	var index := skeleton.get_bone_parent(skeleton.find_bone(bone))
	while index >= 0:
		var name_now := skeleton.get_bone_name(index)
		for entry: Dictionary in CharacterRagdoll.BODIES:
			if entry.bone == name_now:
				return name_now
		index = skeleton.get_bone_parent(index)
	return &""


func _report_cone(entry: Dictionary, turns: Array) -> void:
	var mean := Vector3.ZERO
	for turn: Basis in turns:
		mean += turn.x
	var centre := mean.normalized()
	var swing_to := Quaternion(Vector3.RIGHT, centre)
	var twists: Array[float] = []
	var swing := 0.0
	for turn: Basis in turns:
		swing = maxf(swing, rad_to_deg(turn.x.angle_to(centre)))
		twists.append(_twist(Basis(swing_to).inverse() * turn))
	var middle: float = (twists.max() + twists.min()) / 2.0
	var twist: float = (twists.max() - twists.min()) / 2.0
	var euler := (Basis(swing_to) * Basis(Vector3.RIGHT, deg_to_rad(middle))).get_euler()
	print(
		(
			(
				"%s cone: centre = Vector3(%.1f, %.1f, %.1f), clips swing %.0f, twist %.0f "
				+ "(table swing %.0f, twist %.0f)"
			)
			% [
				entry.bone,
				rad_to_deg(euler.x),
				rad_to_deg(euler.y),
				rad_to_deg(euler.z),
				swing,
				twist,
				entry.swing,
				entry.twist
			]
		)
	)


func _report_hinge(entry: Dictionary, turns: Array) -> void:
	# Each turn from the straight limb, read in the hinge's frame: the bend about Z, the lean
	# about Y and the roll about X (small angles, as the test reads them).
	var frame := CharacterRagdoll.hinge_frame(entry.axis)
	var low := INF
	var high := -INF
	var lean := 0.0
	var roll := 0.0
	for turn: Basis in turns:
		var q := _short(Quaternion(frame.inverse() * turn * frame))
		var bend := rad_to_deg(2.0 * atan2(q.z, q.w))
		low = minf(low, bend)
		high = maxf(high, bend)
		lean = maxf(lean, absf(rad_to_deg(2.0 * asin(clampf(q.y, -1.0, 1.0)))))
		roll = maxf(roll, absf(rad_to_deg(2.0 * asin(clampf(q.x, -1.0, 1.0)))))
	print(
		(
			"%s hinge: clips bend %.0f to %.0f (table %.0f to %.0f), lean up to %.0f, roll up to %.0f"
			% [entry.bone, low, high, entry.range.x, entry.range.y, lean, roll]
		)
	)


# The turn about X left after the swing that takes X to where `turn` takes it.
func _twist(turn: Basis) -> float:
	var q := Quaternion(turn)
	if q.w < 0.0:
		q = -q
	return rad_to_deg(2.0 * atan2(q.x, q.w))


# The same turn the short way round (w not negative), so its angle is at most 180 degrees.
func _short(q: Quaternion) -> Quaternion:
	return -q if q.w < 0.0 else q
