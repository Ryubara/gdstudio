class_name UseTurn
extends SkeletonModifier3D
## Keeps an upper-body action's chest where its clip puts it (`UseLayer`). A clip made for the whole
## body turns its root and hips and turns the spine back against them: `ual2/Consume` turns the
## hips 28 degrees and the chest 34. Played on the upper body alone, the root and hips stay the
## legs' and only the spine's turn back is left, so the chest swung 28 degrees off and the hand
## that should reach the face reached out to the side. This turns the first spine bone by the
## difference between the clip's turn of every bone above it (the root, the pelvis) and the turn
## the legs hold, eased in and out with the action, so the chest, the head and the arm are where
## the clip has them while the legs keep walking.
##
## It is made by `UseLayer` as the first modifier of the character's skeleton and does nothing
## between actions. Cosmetic: each screen works it out from the clip's own time, never sent.

## The bone turned by the difference (the first of the upper body).
@export var spine_bone: StringName = &"spine_01"

var _clip: Animation
# Each bone above `spine_bone`, from the root down, with its rotation track in the clip (-1: none).
var _chain: Array[int] = []
var _tracks: Array[int] = []
var _scale := 1.0
var _duration := 0.0
var _blend := 0.1
var _elapsed := 0.0
var _out_left := -1.0


## Starts following `clip`, its tracks found under `rig_path` (the skeleton's path from the
## animation player's root, `Armature/Skeleton3D`), stretched to `duration` seconds and blended in
## and out over `blend`.
func begin(clip: Animation, rig_path: NodePath, duration: float, blend: float) -> void:
	_clip = clip
	_chain.clear()
	_tracks.clear()
	var skeleton := get_skeleton()
	if clip != null and skeleton != null:
		var bone := skeleton.get_bone_parent(skeleton.find_bone(spine_bone))
		while bone >= 0:
			var path := NodePath("%s:%s" % [rig_path, skeleton.get_bone_name(bone)])
			_chain.push_front(bone)
			_tracks.push_front(clip.find_track(path, Animation.TYPE_ROTATION_3D))
			bone = skeleton.get_bone_parent(bone)
	_duration = duration if duration > 0.0 else (clip.length if clip != null else 0.0)
	_scale = clip.length / _duration if clip != null and _duration > 0.0 else 1.0
	_blend = maxf(blend, 0.001)
	_elapsed = 0.0
	_out_left = -1.0


## The action ended early: the turn eases out over the blend time.
func end() -> void:
	if _clip != null and _out_left < 0.0:
		_out_left = minf(_blend, _duration - _elapsed)


## True while a clip is being followed.
func is_following() -> bool:
	return _clip != null and not _chain.is_empty()


## How much of the turn is applied now (0 between actions, 1 with the clip fully in).
func weight() -> float:
	if not is_following():
		return 0.0
	var amount := minf(_elapsed / _blend, (_duration - _elapsed) / _blend)
	if _out_left >= 0.0:
		amount = minf(amount, _out_left / _blend)
	return clampf(amount, 0.0, 1.0)


func _process_modification_with_delta(delta: float) -> void:
	if not is_following():
		return
	_elapsed += delta
	if _out_left >= 0.0:
		_out_left -= delta
	if _elapsed >= _duration or (_out_left >= 0.0 and _out_left <= 0.0):
		_clip = null
		return
	var skeleton := get_skeleton()
	var spine := skeleton.find_bone(spine_bone) if skeleton != null else -1
	if spine < 0:
		return
	var at := clampf(_elapsed * _scale, 0.0, _clip.length)
	var wanted := Quaternion.IDENTITY
	var held := Quaternion.IDENTITY
	for index in _chain.size():
		var bone := _chain[index]
		var pose := skeleton.get_bone_pose_rotation(bone)
		held = held * pose
		var track := _tracks[index]
		wanted = wanted * (_clip.rotation_track_interpolate(track, at) if track >= 0 else pose)
	var turn := Quaternion.IDENTITY.slerp((held.inverse() * wanted).normalized(), weight())
	skeleton.set_bone_pose_rotation(spine, turn * skeleton.get_bone_pose_rotation(spine))
