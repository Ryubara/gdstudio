class_name HelperTracks
extends RefCounted
## The clips' tracks of the rig's helper bones (gdstudio #1438): the prototype rig's `ik_` targets
## (`ik_foot_l`, `ik_hand_r`, ...), which our own clips key (8 of their 61 tracks) and the library
## clips do not. No vertex of the bodies is weighted to them, no bone hangs under them and nothing
## in the game reads them, yet the animation tree blended those tracks on every character each
## frame. `mute()` switches them off in every library of a player (`Animation.track_set_enabled`,
## which a compressed clip allows where removing a track is refused): the mixer then makes no
## cache for them and blends nothing, the targets stay at their rest and every other bone is
## drawn as before, to the bit. A clip made from a muted one (`LeanClips` copies the flag) is
## muted too.
##
## The libraries are resources every character's player shares, so this holds for the whole game:
## `GaitSettings.helper_tracks` decides it, and the characters' settings should agree (the
## template's share `gait_settings.tres`). In the game only: the editor keeps the imported clips
## as they are.

## Bone names that start with one of these are helper bones.
const PREFIXES: Array[String] = ["ik_"]

## The libraries already muted, by instance id: a library is looked through once per game.
static var _muted: Dictionary[int, bool] = {}


## Switches off the helper bones' tracks in every library of `player` that is not muted yet, and
## returns how many tracks it switched off.
static func mute(player: AnimationPlayer) -> int:
	return _set_all(player, false)


## Switches the helper bones' tracks of `player`'s libraries back on (a game or a test that wants
## the targets keyed), and returns how many it switched on.
static func unmute(player: AnimationPlayer) -> int:
	return _set_all(player, true)


## True when `bone` (a bone name or a track's `Skeleton3D:bone` path) is a helper bone.
static func is_helper(bone: String) -> bool:
	var name := bone.get_slice(":", bone.get_slice_count(":") - 1)
	for prefix in PREFIXES:
		if name.begins_with(prefix):
			return true
	return false


static func _set_all(player: AnimationPlayer, on: bool) -> int:
	if player == null or Engine.is_editor_hint():
		return 0
	var changed := 0
	for library_name in player.get_animation_library_list():
		var library := player.get_animation_library(library_name)
		var id := library.get_instance_id()
		if _muted.has(id) != on:
			continue
		for clip in library.get_animation_list():
			changed += _set_clip(library.get_animation(clip), on)
		if on:
			_muted.erase(id)
		else:
			_muted[id] = true
	return changed


static func _set_clip(clip: Animation, on: bool) -> int:
	var changed := 0
	for track in clip.get_track_count():
		if clip.track_is_enabled(track) == on:
			continue
		if not is_helper(str(clip.track_get_path(track))):
			continue
		clip.track_set_enabled(track, on)
		changed += 1
	return changed
