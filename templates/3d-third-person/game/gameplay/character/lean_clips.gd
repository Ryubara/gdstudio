class_name LeanClips
extends RefCounted
## The clips `GaitLean` blends (gdstudio #1403): the first frame of each lean pose, and of the base
## pose once for each axis, with only the tracks the axis's poses move off the base. A track both
## poses of an axis hold where the base does adds nothing to that axis's lean (its difference is
## nought) and was blended twice a way on every character each frame; it is left out of the axis's
## three clips. A track some clip lacks is kept as it is, and every track that is not a transform.
## Made once for a set of source clips and shared by every character whose player holds them, in
## the player's own `LIBRARY`.

const LIBRARY := &"gait_lean"
## A position or a scale this close, or a turn this small (quaternion components), is the base's.
const SAME := 1e-6
const FRAME := 1.0 / 30.0
const TRANSFORMS: Array[Animation.TrackType] = [
	Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D
]

## The library made for each set of source clips, by their instance ids.
static var _made: Dictionary[String, AnimationLibrary] = {}


## The names in `player` of each way's trimmed pose (`clips`: way to clip name) and of each axis's
## trimmed base (`axes`: way to its axis), the library added to `player` when it lacks it.
static func trimmed(
	player: AnimationPlayer,
	base: StringName,
	clips: Dictionary[StringName, StringName],
	axes: Dictionary[StringName, StringName]
) -> Dictionary[StringName, StringName]:
	var source := player.get_animation(base)
	var poses: Dictionary[StringName, Animation] = {}
	var key := str(source.get_instance_id())
	for way: StringName in clips:
		poses[way] = player.get_animation(clips[way])
		key += ",%s:%s=%d" % [way, axes[way], poses[way].get_instance_id()]
	if not _made.has(key):
		_made[key] = _library(source, poses, axes)
	var library := _made[key]
	if player.has_animation_library(LIBRARY) and player.get_animation_library(LIBRARY) != library:
		player.remove_animation_library(LIBRARY)
	if not player.has_animation_library(LIBRARY):
		player.add_animation_library(LIBRARY, library)
	var names: Dictionary[StringName, StringName] = {}
	for clip: StringName in library.get_animation_list():
		names[clip] = StringName("%s/%s" % [LIBRARY, clip])
	return names


## How many tracks each trimmed clip of `player` keeps (clip: count), for the tests and the bench.
static func kept_tracks(player: AnimationPlayer) -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	if player.has_animation_library(LIBRARY):
		var library := player.get_animation_library(LIBRARY)
		for clip: StringName in library.get_animation_list():
			counts[clip] = library.get_animation(clip).get_track_count()
	return counts


static func _library(
	base: Animation,
	poses: Dictionary[StringName, Animation],
	axes: Dictionary[StringName, StringName]
) -> AnimationLibrary:
	var moved := {}  # axis: {track key: true}
	for way: StringName in poses:
		var axis := axes[way]
		if not moved.has(axis):
			moved[axis] = {}
		var pose := poses[way]
		for track in pose.get_track_count():
			var path := pose.track_get_path(track)
			var type := pose.track_get_type(track)
			var other := base.find_track(path, type)
			if other < 0 or not _same(pose, track, base, other):
				moved[axis][_key(path, type)] = true
		for track in base.get_track_count():
			var type := base.track_get_type(track)
			if pose.find_track(base.track_get_path(track), type) < 0:
				moved[axis][_key(base.track_get_path(track), type)] = true
	var library := AnimationLibrary.new()
	for axis: StringName in moved:
		library.add_animation(axis, _first_frame(base, moved[axis]))
	for way: StringName in poses:
		library.add_animation(way, _first_frame(poses[way], moved[axes[way]]))
	return library


# `source`'s first frame, of the tracks in `moved` and every track that is not a transform.
static func _first_frame(source: Animation, moved: Dictionary) -> Animation:
	var out := Animation.new()
	out.length = FRAME
	out.loop_mode = Animation.LOOP_NONE
	for track in source.get_track_count():
		var type := source.track_get_type(track)
		if type not in TRANSFORMS:
			source.copy_track(track, out)
			continue
		var path := source.track_get_path(track)
		if not moved.has(_key(path, type)):
			continue
		var added := out.add_track(type)
		out.track_set_path(added, path)
		out.track_set_enabled(added, source.track_is_enabled(track))
		match type:
			Animation.TYPE_POSITION_3D:
				out.position_track_insert_key(
					added, 0.0, source.position_track_interpolate(track, 0.0)
				)
			Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(
					added, 0.0, source.rotation_track_interpolate(track, 0.0)
				)
			Animation.TYPE_SCALE_3D:
				out.scale_track_insert_key(added, 0.0, source.scale_track_interpolate(track, 0.0))
	return out


static func _same(a: Animation, track_a: int, b: Animation, track_b: int) -> bool:
	match a.track_get_type(track_a):
		Animation.TYPE_POSITION_3D:
			var pa := a.position_track_interpolate(track_a, 0.0)
			return pa.distance_to(b.position_track_interpolate(track_b, 0.0)) <= SAME
		Animation.TYPE_ROTATION_3D:
			# Component by component (q and -q are one turn): an angle read through acos is
			# blind below about 3e-4 radians in single precision.
			var qa := a.rotation_track_interpolate(track_a, 0.0)
			var qb := b.rotation_track_interpolate(track_b, 0.0)
			return minf((qa - qb).length(), (qa + qb).length()) <= SAME
		Animation.TYPE_SCALE_3D:
			var sa := a.scale_track_interpolate(track_a, 0.0)
			return sa.distance_to(b.scale_track_interpolate(track_b, 0.0)) <= SAME
	return false


static func _key(path: NodePath, type: int) -> String:
	return "%s|%d" % [path, type]
