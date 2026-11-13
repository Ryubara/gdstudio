class_name AimPose
extends RefCounted
## The weapon's aim pose alone, bone by bone, for the `AimOffsetModifier` to solve on (kit #1318).
## The modifier runs after the clips, where the aim pose is blended with the carry pose by how far
## the weapon is up: over the carry pose the muzzle points at the floor, so a turn solved on that
## blend lifts it by up to 70 degrees and folds the chest back on the first and last frames of
## every aim. The turn the aim needs is the one the aim pose needs, so this reads that pose from the
## hold's three aim clips (down, level, up), blended by the aim pitch as the weapon layer's blend
## space blends them (`CharacterAnimation`), and the modifier puts it in place of the drawn pose
## for its solve. The clips are poses: each is read once, at its start, and kept. A bone a clip
## has no track for is at its rest there, as the tree blends it (a deterministic tree blends a
## missing track toward the rest pose). Lying, the prone aim clips stand in for the standing ones
## by `lying_share` (`lying`, a second pose read the same way). Standing, the `AimBrace` stands the
## upper body on the aim clip's own stance, so the first bone of the upper body is braced here too
## (`braced()`), by the brace's share.

## The prone aim pose, blended in by `lying_share` (null: none).
var lying: AimPose
## How far `lying` stands in for this pose (0 none, 1 all of it).
var lying_share := 0.0
## The bone the `AimBrace` holds (-1: no brace), the turn it stands it on and how much of the brace
## the aim pose has (the brace's weight at full aim).
var brace_bone := -1
var brace_stance := Quaternion.IDENTITY
var brace_share := 0.0
## The grip (`WeaponHold.grip_modifier()`'s pose): it turns the hand the weapon rides on top of
## the clip's (`HandPose.turns`). Lying, the grip comes on with the aim, so the drawn hand is the
## prone clip's fist until the weapon is up; the aim pose's hand is the aim clip's, gripped.
var grip: HandPose

# Per blend point (down, level, up), the bones its clip poses (bone index -> [rotation or null,
# position or null]), the pitch of the outer points (x down, y up, degrees) and the pitch now.
var _range := Vector2(45.0, 45.0)
var _poses: Array[Dictionary] = []
var _pitch := 0.0
# Every bone's rest rotation and position, for a bone or a channel a clip has no track for.
var _rests: Array[Array] = []
# What the poses were read for: the skeleton, the clips and the pitch range.
var _skeleton := 0
var _clips: Array[StringName] = []
var _made_range := Vector2.ZERO


## Reads the hold's aim clips from `player` for `skeleton`, once per set of clips and skeleton;
## `pitch_range` is the pitch of the down clip (x) and of the up clip (y), in degrees, both
## positive. False when there is nothing to read (no clips): the modifier then solves on the drawn
## pose.
func prepare(
	player: AnimationPlayer, skeleton: Skeleton3D, clips: Array[StringName], pitch_range: Vector2
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
	_range = pitch_range.max(Vector2(0.001, 0.001))
	_poses.clear()
	_rests.clear()
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(bone)
		_rests.append([rest.basis.get_rotation_quaternion(), rest.origin])
	for clip in clips:
		if not player.has_animation(clip):
			_poses.clear()
			return false
		_poses.append(_read(player.get_animation(clip), skeleton))
	return true


## Where the pose is on its pitch axis now, in degrees (the weapon layer's `aim_pitch()`).
func set_pitch(degrees: float) -> void:
	_pitch = clampf(degrees, -_range.x, _range.y)


## True when a pose was read (this one, or the prone one all the way in).
func has_pose() -> bool:
	if lying_share >= 1.0 and lying != null:
		return lying.has_pose()
	return _poses.size() == 3


## The bone's local pose in the aim pose at the pitch set, with `drawn`'s scale; `drawn` itself
## when no pose was read.
func local(bone: int, drawn: Transform3D) -> Transform3D:
	var share := lying_share if lying != null and lying.has_pose() else 0.0
	if share >= 1.0:
		return lying.local(bone, drawn)
	if _poses.size() != 3 or bone < 0 or bone >= _rests.size():
		return drawn
	var high := 1 if _pitch < 0.0 else 2
	var along := (_pitch + _range.x) / _range.x if _pitch < 0.0 else _pitch / _range.y
	var rest: Array = _rests[bone]
	var lower: Array = _poses[high - 1].get(bone, rest)
	var upper: Array = _poses[high].get(bone, rest)
	# As the tree blends: each clip's turn off the rest, scaled by its weight, on the rest.
	var at_rest: Quaternion = rest[0]
	var back := at_rest.inverse()
	var low: Quaternion = back * (lower[0] if lower[0] != null else at_rest)
	var high_turn: Quaternion = back * (upper[0] if upper[0] != null else at_rest)
	var rotation := (
		at_rest
		* Quaternion.IDENTITY.slerp(low, 1.0 - along)
		* Quaternion.IDENTITY.slerp(high_turn, along)
	)
	var origin: Vector3 = (lower[1] if lower[1] != null else rest[1]).lerp(
		upper[1] if upper[1] != null else rest[1], along
	)
	var posed := Transform3D(Basis(rotation.normalized()).scaled(drawn.basis.get_scale()), origin)
	if share <= 0.0:
		return posed
	return posed.interpolate_with(lying.local(bone, drawn), share)


## The local pose of the hand the weapon rides, `bone` (named `bone_name`), in the aim pose: the aim
## clips' hand turned by the grip.
func gripped(bone: int, bone_name: StringName, drawn: Transform3D) -> Transform3D:
	var posed := local(bone, drawn)
	if grip == null or not grip.turns.has(bone_name):
		return posed
	var turn: Quaternion = grip.turns[bone_name]
	var spin := (posed.basis.get_rotation_quaternion() * turn).normalized()
	return Transform3D(Basis(spin).scaled(posed.basis.get_scale()), posed.origin)


## `posed` (the bone's local pose from `local()`) held on the brace's stance as the `AimBrace`
## holds it, by `brace_share`, when `bone` is the braced one; `parent` is its parent's pose in the
## skeleton's space.
func braced(bone: int, posed: Transform3D, parent: Basis) -> Transform3D:
	if bone != brace_bone or brace_share <= 0.0:
		return posed
	var held := parent.orthonormalized().inverse().get_rotation_quaternion() * brace_stance
	var spin := posed.basis.get_rotation_quaternion()
	var turned := spin.slerp(held * spin, clampf(brace_share, 0.0, 1.0)).normalized()
	return Transform3D(Basis(turned).scaled(posed.basis.get_scale()), posed.origin)


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
