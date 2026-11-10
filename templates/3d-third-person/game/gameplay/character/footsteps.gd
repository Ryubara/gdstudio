@tool
class_name Footsteps
extends Node3D
## Plays a footstep each time a foot of the animated character lands. It reads the feet from the
## skeleton the walk, run, sprint and crouch-walk clips pose, so a step sounds exactly where the
## clip puts the foot down, at any blend of the clips, and never when the character stands
## still or is in the air.
##
## A foot lands when its bone, moving forward through the swing, turns back (the body moves
## over it). The sounds are three nodes of `footsteps.tscn`: `Step` for a walk, run or sprint,
## `CrouchStep` while the character crouches (quieter) and `LandStep` for a landing (louder). Each
## is an `AudioStreamPlayer3D` whose volume, bus and attenuation are the node's own. `steps` holds
## the files, cycled in a seeded order so two steps in a row never repeat.

## A foot landed. `foot` is the bone's name and `crouched` says which sound player it used.
signal stepped(foot: StringName, crouched: bool)

@export_group("Nodes")
## The character whose feet are followed.
@export var player: Player
## The slot that holds the character's model: the feet are read from the skeleton it finds, so a
## replaced model needs nothing set here. Its +Z is forward, so a foot moving toward +Z is
## swinging ahead.
@export var model: CharacterModel

@export_group("Sounds")
## The footstep files; one is picked for each step.
@export var steps: Array[AudioStream] = []
## How much the pitch of a step varies, as a share (0.05 is 5 percent either way).
@export_range(0.0, 0.5, 0.01) var pitch_variation := 0.05

@export_group("Timing")
## The bones that touch the ground.
@export var foot_bones: Array[StringName] = [&"foot_l", &"foot_r"]
## A foot swings when it moves forward faster than this, so the jitter of a resting foot does not
## count.
@export_range(0.0, 1.0, 0.01, "suffix:m/s") var swing_speed := 0.15
## A foot lands only after it swung forward at least this far, so a jitter of the pose (the
## blend between two clips) is not a step.
@export_range(0.0, 1.0, 0.01, "suffix:m") var min_stride := 0.2
## No step sounds sooner than this after the one before.
@export_range(0.0, 1.0, 0.01, "suffix:s") var min_interval := 0.12
## Below this ground speed no step sounds.
@export_range(0.0, 2.0, 0.05, "suffix:m/s") var min_speed := 0.5

var _skeleton: Skeleton3D
var _bones: Array[int] = []
var _last: Array[float] = []
var _swinging: Array[bool] = []
var _low: Array[float] = []
var _since := 10.0
var _rng := RandomNumberGenerator.new()
var _last_pick := -1


func _ready() -> void:
	_rng.seed = 1
	if Engine.is_editor_hint():
		set_process(false)
		return
	if player != null:
		player.landed.connect(_on_landed)


func _process(delta: float) -> void:
	if model == null or player == null or delta <= 0.0:
		return
	var skeleton := model.skeleton()
	if skeleton == null:
		return
	if skeleton != _skeleton or _bones.size() != foot_bones.size():
		_find_bones(skeleton)
	_since += delta
	var inverse := model.global_transform.affine_inverse()
	for index in _bones.size():
		if _bones[index] < 0:
			continue
		var pose := skeleton.global_transform * skeleton.get_bone_global_pose(_bones[index])
		var forward: float = (inverse * pose.origin).z
		var speed := (forward - _last[index]) / delta
		_last[index] = forward
		if speed > swing_speed:
			_swinging[index] = true
		elif speed < -swing_speed:
			if _swinging[index] and forward - _low[index] >= min_stride:
				_land(foot_bones[index])
			_swinging[index] = false
		if not _swinging[index]:
			_low[index] = forward


## Plays a step now, as if the foot `foot` landed (for a game's own animation event).
func play_step(foot: StringName = &"") -> void:
	var crouched := player != null and player.crouching
	var sound := get_node_or_null("%CrouchStep" if crouched else "%Step") as AudioStreamPlayer3D
	if sound == null or steps.is_empty():
		return
	_since = 0.0
	sound.stream = steps[_pick()]
	sound.pitch_scale = 1.0 + _rng.randf_range(-pitch_variation, pitch_variation)
	sound.play()
	stepped.emit(foot, crouched)


func _land(foot: StringName) -> void:
	if not player.is_on_floor() or player.ground_speed() < min_speed:
		return
	if _since < min_interval:
		return
	play_step(foot)


func _on_landed(_impact: float) -> void:
	var sound := get_node_or_null("%LandStep") as AudioStreamPlayer3D
	if sound == null or steps.is_empty():
		return
	_since = 0.0
	sound.stream = steps[_pick()]
	sound.pitch_scale = 0.9
	sound.play()


func _find_bones(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_bones.clear()
	_last.clear()
	_swinging.clear()
	_low.clear()
	for foot in foot_bones:
		_bones.append(skeleton.find_bone(foot))
		_last.append(0.0)
		_swinging.append(false)
		_low.append(0.0)


# A step other than the one before it, in a seeded order.
func _pick() -> int:
	var count := steps.size()
	var next := _rng.randi() % count
	if count > 1 and next == _last_pick:
		next = (next + 1) % count
	_last_pick = next
	return next


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if player == null or model == null:
		warnings.append("Set `player` and `model`: the feet are read from them.")
	for part_name in ["Step", "CrouchStep", "LandStep"]:
		if get_node_or_null("%" + part_name) == null:
			warnings.append("The scene needs an AudioStreamPlayer3D named `%s`." % part_name)
	return warnings
