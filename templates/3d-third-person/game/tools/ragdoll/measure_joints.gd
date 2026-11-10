## Measures how far every joint of the ragdoll turns in the animation clips, so its limits hold
## every pose the character can die in (a joint that starts outside its limits is snapped back and
## can throw the whole body). For each joint of `PlayerRagdoll.BODIES` it samples every clip the
## player plays by default (`PlayerAnimation`'s clips) on both mannequins and prints, relative to
## the joint's rest frame:
##   - a cone: the swing's centre (the mean direction of the bone) as a rotation, the widest swing
##     from it and the twist range around the bone;
##   - a knee or an elbow (`&"bend"`): the bend axis that fits the clips best, and the ranges
##     about it (the bend), along the bone (the twist) and across (the side), as the 6DOF joint
##     measures them (`PlayerRagdoll.swing_twist`).
## The numbers in `PlayerRagdoll.BODIES` come from this, with `MARGIN` added (and never under a
## small floor, so a joint the clips hardly turn still gives a little).
##
## Run it headless from a game made from the template:
## `<godot> --headless --path game -s res://tools/ragdoll/measure_joints.gd`
## It lives in tools/, which the export leaves out.
extends SceneTree

const MODELS := [
	"res://assets/characters/mannequin/mannequin_female.glb",
	"res://assets/characters/mannequin/mannequin_male.glb",
]
const LIBRARIES: Dictionary[StringName, String] = {
	&"ual1": "res://assets/animation/universal/ual1.glb",
	&"ual2": "res://assets/animation/universal/ual2.glb",
}
## Samples per second of each clip.
const RATE := 15.0
## Degrees added to every measured range.
const MARGIN := 10.0


func _initialize() -> void:
	var samples := {}
	for path: String in MODELS:
		_sample_model(path, samples)
	for entry: Dictionary in PlayerRagdoll.BODIES:
		if entry.joint == &"":
			continue
		var turns: Array = samples[entry.bone]
		if entry.joint == &"bend":
			_report_hinge(entry, turns)
		else:
			_report_cone(entry, turns)
	quit()


func _sample_model(path: String, samples: Dictionary) -> void:
	var holder := Node3D.new()
	get_root().add_child(holder)
	var slot := PlayerModel.new()
	holder.add_child(slot)
	var rig := (load(path) as PackedScene).instantiate() as Node3D
	slot.add_child(rig)
	var skeleton := slot.skeleton()
	var ragdoll := PlayerRagdoll.new()
	ragdoll.model = slot
	var rest := {}
	for entry: Dictionary in PlayerRagdoll.BODIES:
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
			for entry: Dictionary in PlayerRagdoll.BODIES:
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


# The clips the player's `PlayerAnimation` plays by default: a character dies in one of these.
func _player_clips() -> Array[StringName]:
	var animation := PlayerAnimation.new()
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


func _rest(ragdoll: PlayerRagdoll, slot: PlayerModel, bone: StringName) -> Transform3D:
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
		for entry: Dictionary in PlayerRagdoll.BODIES:
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
			"%s cone: centre = Vector3(%.1f, %.1f, %.1f), swing = %.0f, twist = %.0f"
			% [
				entry.bone,
				rad_to_deg(euler.x),
				rad_to_deg(euler.y),
				rad_to_deg(euler.z),
				maxf(swing + MARGIN, 20.0),
				maxf(twist + MARGIN, 15.0)
			]
		)
	)


func _report_hinge(entry: Dictionary, turns: Array) -> void:
	# The bend axis: the mean of the turns' axes, weighted by their angles.
	var sum := Vector3.ZERO
	for turn: Basis in turns:
		var q := _short(Quaternion(turn))
		if q.get_angle() > 0.05:
			var axis := q.get_axis()
			sum += axis * q.get_angle() * (1.0 if axis.z >= 0.0 else -1.0)
	var bend_axis := (sum - Vector3.RIGHT * sum.x).normalized()
	# The joint's frame (`PlayerRagdoll.bend_frame`: X the bend, Y along the bone); each turn
	# read the way the joint reads it (`PlayerRagdoll.swing_twist`).
	var frame := PlayerRagdoll.bend_frame(bend_axis)
	var low := Vector3.INF
	var high := -Vector3.INF
	for turn: Basis in turns:
		var angles := PlayerRagdoll.swing_twist(frame.inverse() * turn * frame)
		low = low.min(angles)
		high = high.max(angles)
	print(
		(
			(
				"%s bend: axis = Vector3(%.3f, %.3f, %.3f), bend = Vector2(%.0f, %.0f), "
				+ "twist = Vector2(%.0f, %.0f), side = Vector2(%.0f, %.0f)"
			)
			% [
				entry.bone,
				bend_axis.x,
				bend_axis.y,
				bend_axis.z,
				minf(low.x - MARGIN / 2.0, 0.0),
				maxf(high.x + MARGIN, 145.0),
				low.y - MARGIN,
				high.y + MARGIN,
				low.z - MARGIN,
				high.z + MARGIN
			]
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
