## Films the moves into and out of our own clips (gdstudio #1416) from the game's own camera,
## driven by the actions a player presses: a start and a stop of the walk, the jog and the sprint,
## and the crouch down and up. On main each of them snapped in one frame; they blend now. A label
## names each part and shows the body state and the transition clip; every physics frame prints a
## line starting `OWNBLEND` with the part, the speed, the state, the clip and the largest move of a
## body bone since the last drawn frame, in centimetres in the model's frame.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 13 --fps 60 --name own-blend`
## with `--scene res://tools/capture/own_blend_tour.tscn`; play it back slowed to see each frame.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## An open spot of the sample map, looking north (-Z) with room ahead.
const SPOT := Vector3(4.0, 0.0, 18.0)
## The parts: a title, seconds, the actions held through it, the actions tapped as it begins, and
## whether the body goes back to the spot first.
const PARTS: Array[Array] = [
	["Standing", 0.6, [], [], true],
	["Walk start", 1.1, [&"move_forward", &"walk"], [], false],
	["Walk stop", 1.1, [], [], false],
	["Jog start", 1.1, [&"move_forward"], [], true],
	["Jog stop", 1.1, [], [], false],
	["Sprint start", 1.2, [&"move_forward", &"sprint"], [], true],
	["Sprint stop", 1.4, [], [], false],
	["Crouch down", 1.2, [&"crouch"], [], false],
	["Crouch up", 1.2, [], [], false],
]
## Seconds a tapped action is held.
const TAP := 0.1

var _part := -1
var _clock := 0.0
var _label: Label
var _skeleton: Skeleton3D
var _places: Dictionary[int, Vector3] = {}
var _move := 0.0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _animation: CharacterAnimation = $Main/PlayerRig/Player/Animation


func _ready() -> void:
	_rig.yaw = 0.0
	_rig.pitch = 10.0
	_build_label()
	_skeleton = _player.model.skeleton()
	_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	_next()


# The largest move of a body bone (no finger, IK target or root) since the last update.
func _on_skeleton_updated() -> void:
	_move = 0.0
	for bone in _skeleton.get_bone_count():
		var bone_name := String(_skeleton.get_bone_name(bone)).to_lower()
		if ["thumb", "index", "middle", "ring", "pinky", "ik_", "root", "socket"].any(
			func(part: String) -> bool: return bone_name.contains(part)
		):
			continue
		var place := _skeleton.get_bone_global_pose(bone).origin
		if _places.has(bone):
			_move = maxf(_move, place.distance_to(_places[bone]) * 100.0)
		_places[bone] = place


func _physics_process(delta: float) -> void:
	_clock += delta
	if _part >= PARTS.size():
		return
	var part: Array = PARTS[_part]
	if _clock >= TAP:
		for action: StringName in part[3]:
			Input.action_release(action)
	var speed := _player.ground_speed()
	var clip := _animation.gait.transitions.clip
	_label.text = ("%s\nspeed %.2f m/s   %s %s" % [part[0], speed, _animation.body_state(), clip])
	print(
		(
			"OWNBLEND %d %.2f %.2f %s %s %.1f"
			% [_part, _clock, speed, _animation.body_state(), clip, _move]
		)
	)
	if _clock >= part[1]:
		_next()


func _next() -> void:
	if _part >= 0:
		for action: StringName in PARTS[_part][2]:
			Input.action_release(action)
	_part += 1
	_clock = 0.0
	if _part >= PARTS.size():
		_finish()
		return
	var part: Array = PARTS[_part]
	if part[4]:
		_player.teleport(SPOT, 0.0)
		_rig.yaw = 0.0
	for action: StringName in part[2] + part[3]:
		Input.action_press(action)


func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	_label = Label.new()
	_label.position = Vector2(24.0, 24.0)
	_label.add_theme_font_size_override(&"font_size", 24)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 6)
	layer.add_child(_label)
	add_child(layer)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame_count in 8:
		await get_tree().process_frame
	get_tree().quit()
