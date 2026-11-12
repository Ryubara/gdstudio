## Films the gait fitting of gdstudio #1158 from the game's own camera, driven by the actions a
## player presses: a walk that speeds up through the walk and jog blend into a jog, a stop, a
## sprint and its reversal, a stop out of the sprint, and a turn on the spot while aiming. A
## label names each part and shows the ground speed, the blend's place and the walk's pace.
## `GAIT_OFF=1` films it with the speed matching, the momentum blend and the transitions off (the
## template before #1158), for a before and after. Every physics frame it prints the part, the
## speed and the body state on a line starting `GAITTOUR`.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 14 --fps 30 --name gait`
## with `--scene res://tools/capture/gait_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## An open spot of the sample map, looking north (-Z) with room ahead.
const SPOT := Vector3(4.0, 0.0, 18.0)
## The parts: a title, seconds, and the actions held through it.
const PARTS: Array[Array] = [
	["Walk", 1.4, [&"move_forward", &"walk"]],
	["Walk into jog (the blend)", 1.4, [&"move_forward"]],
	["Stop", 1.0, []],
	["Sprint", 1.3, [&"move_forward", &"sprint"]],
	["Sprint reversal", 1.4, [&"move_back", &"sprint"]],
	["Stop out of the sprint", 1.2, []],
	["Turn on the spot, aiming", 2.4, [&"aim"]],
]

var _part := -1
var _clock := 0.0
var _label: Label

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _animation: CharacterAnimation = $Main/PlayerRig/Player/Animation


func _ready() -> void:
	if OS.get_environment("GAIT_OFF") == "1":
		var settings := _animation.gait_settings
		settings = (settings if settings != null else GaitSettings.new()).duplicate()
		settings.speed_match = false
		settings.momentum_blend = false
		settings.transitions = false
		_animation.gait_settings = settings
	_player.teleport(SPOT, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 10.0
	_build_label()
	_next()


func _physics_process(delta: float) -> void:
	_clock += delta
	if _part >= PARTS.size():
		return
	var part: Array = PARTS[_part]
	if part[0].begins_with("Turn"):
		# The view swings 120 degrees to the left and back; the aimed body turns after it.
		var swing := (
			clampf((_clock - 0.3) / 0.25, 0.0, 1.0) - clampf((_clock - 1.4) / 0.25, 0.0, 1.0)
		)
		_rig.yaw = 120.0 * swing
	var tree := _animation.tree
	var at: float = tree.get(&"parameters/Locomotion/ground/blend_position")
	var pace: float = tree.get(&"parameters/Locomotion/ground/walk/Pace/scale")
	var speed := _player.ground_speed()
	_label.text = (
		"%s%s\nspeed %.2f m/s   blend at %.2f   walk pace %.2f   %s"
		% [
			part[0],
			"  (fitting off)" if OS.get_environment("GAIT_OFF") == "1" else "",
			speed,
			at,
			pace,
			_animation.body_state()
		]
	)
	print(
		"GAITTOUR ",
		_part,
		" ",
		snappedf(_clock, 0.01),
		" ",
		snappedf(speed, 0.01),
		" ",
		_animation.body_state()
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
	for action: StringName in PARTS[_part][2]:
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
