## Films the gait stops of gdstudio #1415 from the game's own camera, driven by the actions a
## player presses: a jog across the view and the stick let go, then a sprint and the stick let go.
## The camera looks north and the body runs east, across the view, so the ground a stop covers and
## the feet on the floor are seen side on, with the game's camera pulled back to 4 m. A label names
## each part and shows the ground speed, the ground covered since the stick was let go and the stop
## clip that plays. Every physics frame it
## prints the part, the speed, the ground covered and the transition's clip on a line starting
## `STOPTOUR`.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 9 --fps 30 --name stops`
## with `--scene res://tools/capture/gait_stop_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## An open spot of the sample map, with room to the east.
const SPOT := Vector3(-2.0, 0.0, 18.0)
## The parts: a title, seconds, and the actions held through it.
const PARTS: Array[Array] = [
	["Jog", 1.3, [&"move_right"]],
	["Jog stop", 1.8, []],
	["Sprint", 1.5, [&"move_right", &"sprint"]],
	["Sprint stop", 2.6, []],
]

var _part := -1
var _clock := 0.0
var _let_go := Vector3.INF
var _label: Label

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _animation: CharacterAnimation = $Main/PlayerRig/Player/Animation


func _ready() -> void:
	_player.teleport(SPOT, -PI / 2.0)
	_rig.yaw = 0.0
	_rig.pitch = 18.0
	_rig.distance = 4.0  # Further back than play, so the feet stay in the frame.
	_build_label()
	_next()


func _physics_process(delta: float) -> void:
	_clock += delta
	if _part >= PARTS.size():
		return
	var part: Array = PARTS[_part]
	var speed := _player.ground_speed()
	var covered := 0.0
	if _let_go != Vector3.INF:
		var moved := _player.global_position - _let_go
		covered = Vector2(moved.x, moved.z).length()
	var clip := _animation.gait.transitions.clip
	_label.text = (
		"%s\nspeed %.2f m/s   since let go %.2f m   %s"
		% [part[0], speed, covered, clip if clip != &"" else _animation.body_state()]
	)
	print(
		"STOPTOUR ",
		_part,
		" ",
		snappedf(_clock, 0.01),
		" ",
		snappedf(speed, 0.01),
		" ",
		snappedf(covered, 0.001),
		" ",
		clip
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
	_let_go = _player.global_position if part[2].is_empty() else Vector3.INF
	if part[0] == "Sprint":
		_player.teleport(SPOT, -PI / 2.0)
	for action: StringName in part[2]:
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
