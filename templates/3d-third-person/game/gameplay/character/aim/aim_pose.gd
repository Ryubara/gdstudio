class_name AimPose
extends RefCounted
## The weapon's aim pose alone, bone by bone, for the `AimOffsetModifier` to solve on (kit #1318).
## The modifier runs after the clips, where the aim pose is blended with the carry pose by how far
## the weapon is up: over the carry pose the muzzle points at the floor, so a turn solved on that
## blend lifts it by up to 70 degrees and folds the chest back on the first and last frames of
## every aim. The turn the aim needs is the one the aim pose needs, so this reads that pose from the
## hold's three aim clips (down, level, up), blended by the aim pitch as the weapon layer's blend
## space blends them (`CharacterAnimation`), and the modifier puts it in place of the drawn pose
## for its solve. The clips are poses: each is read once, at its start, and kept.

# Per blend point (down, level, up), the bones its clip poses (bone index -> [rotation or null,
# position or null]), the pitch of the outer points (degrees) and the pitch now.
var _range := 45.0
var _poses: Array[Dictionary] = []
var _pitch := 0.0
# What the poses were read for: the skeleton, the clips and the pitch range.
var _skeleton := 0
var _clips: Array[StringName] = []
var _made_range := 0.0


## Reads the hold's aim clips from `player` for `skeleton`, once per set of clips and skeleton.
## False when there is nothing to read (no clips): the modifier then solves on the drawn pose.
func prepare(
	player: AnimationPlayer, skeleton: Skeleton3D, clips: Array[StringName], pitch_range: float
) -> bool:
	if player == null or skeleton == null or clips.size() != 3 or clips.has(&""):
		_skeleton = 0
		_poses.clear()
		return false
	var made := skeleton.get_instance_id()
	if made == _skeleton and clips == _clips and pitch_range == _made_range:
		return not _poses.is_empty()
	_skeleton = made
	_clips = clips.duplicate()
	_made_range = pitch_range
	_range = maxf(pitch_range, 0.001)
	_poses.clear()
	for clip in clips:
		if not player.has_animation(clip):
			_poses.clear()
			return false
		_poses.append(_read(player.get_animation(clip), skeleton))
	return true


## Where the pose is on its pitch axis now, in degrees (the weapon layer's `aim_pitch()`).
func set_pitch(degrees: float) -> void:
	_pitch = clampf(degrees, -_range, _range)


## True when a pose was read.
func has_pose() -> bool:
	return _poses.size() == 3


## The bone's local pose in the aim pose at the pitch set, with `drawn`'s scale (and its position
## where the clips do not move the bone); `drawn` itself for a bone the clips leave alone.
func local(bone: int, drawn: Transform3D) -> Transform3D:
	if not has_pose():
		return drawn
	var high := 1 if _pitch < 0.0 else 2
	var share := (_pitch + _range) / _range if _pitch < 0.0 else _pitch / _range
	var lower: Variant = _poses[high - 1].get(bone)
	var upper: Variant = _poses[high].get(bone)
	if lower == null or upper == null:
		return drawn
	var basis := drawn.basis
	if lower[0] != null and upper[0] != null:
		var rotation: Quaternion = (lower[0] as Quaternion).slerp(upper[0] as Quaternion, share)
		basis = Basis(rotation.normalized()).scaled(drawn.basis.get_scale())
	var origin := drawn.origin
	if lower[1] != null and upper[1] != null:
		origin = (lower[1] as Vector3).lerp(upper[1] as Vector3, share)
	return Transform3D(basis, origin)


# The rotation (and position) each bone of the skeleton has at the clip's start.
static func _read(clip: Animation, skeleton: Skeleton3D) -> Dictionary:
	var found := {}
	for track in clip.get_track_count():
		var kind := clip.track_get_type(track)
		if kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_POSITION_3D:
			continue
		var bone := skeleton.find_bone(clip.track_get_path(track).get_concatenated_subnames())
		if bone < 0 or clip.track_get_key_count(track) == 0:
			continue
		var entry: Array = found.get(bone, [null, null])
		if kind == Animation.TYPE_ROTATION_3D:
			entry[0] = clip.rotation_track_interpolate(track, 0.0)
		else:
			entry[1] = clip.position_track_interpolate(track, 0.0)
		found[bone] = entry
	return found
