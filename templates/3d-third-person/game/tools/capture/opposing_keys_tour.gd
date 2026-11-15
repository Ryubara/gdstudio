## Films the movement-key sequences of gdstudio #1563 from the game's own camera, driven by the
## actions a player presses: W then S a few ticks apart, W then W and S held together then S, and
## W then D then everything let go, each from standing at the same spot at a jog. A label names
## the sequence and shows the keys held, the ground speed and the clip the tree plays (the
## transition's, or the body state); every physics frame prints the same on a line starting
## `KEYTOUR`. Before #1563 W and S held together cancelled out and played the stop.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 20 --fps 30 --name keys`
## with `--scene res://tools/capture/opposing_keys_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing to walk into, no camera zone), and the spot on
## it each sequence starts from.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const SPOT := Vector3(0.0, 300.1, 0.0)
## The sequences: a title, then steps of seconds and the move actions held.
const SEQUENCES: Array[Array] = [
	[
		"W, then S 0.05 s later",
		[[1.4, ["move_forward"]], [0.05, []], [2.0, ["move_back"]], [2.5, []]]
	],
	[
		"W, W+S, S",
		[
			[1.4, ["move_forward"]],
			[1.0, ["move_forward", "move_back"]],
			[1.2, ["move_back"]],
			[2.5, []]
		]
	],
	["W, D, let go", [[1.4, ["move_forward"]], [0.05, []], [1.4, ["move_right"]], [2.5, []]]],
]

var _sequence := -1
var _step := -1
var _clock := 0.0
var _label: Label

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _animation: CharacterAnimation = $Main/PlayerRig/Player/Animation


func _ready() -> void:
	_rig.pitch = 18.0
	_rig.distance = 4.5  # Further back than play, so the feet stay in the frame.
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_build_label()
	_next_sequence()


func _physics_process(delta: float) -> void:
	if _sequence >= SEQUENCES.size():
		return
	_clock += delta
	var steps: Array = SEQUENCES[_sequence][1]
	if _clock >= float(steps[_step][0]):
		_next_step()
		if _sequence >= SEQUENCES.size():
			return
	var held: Array = SEQUENCES[_sequence][1][_step][1]
	var keys := ""
	for action: String in held:
		keys += {"move_forward": "W", "move_back": "S", "move_right": "D"}[action]
	var clip := String(_animation.gait.transitions.clip).trim_prefix("gds/")
	var shown := clip if clip != "" else String(_animation.body_state())
	_label.text = (
		"%s\nkeys %s   speed %.2f m/s   %s"
		% [SEQUENCES[_sequence][0], keys if keys != "" else "none", _player.ground_speed(), shown]
	)
	print("KEYTOUR ", _sequence, " ", keys, " ", snappedf(_player.ground_speed(), 0.01), " ", shown)


func _next_sequence() -> void:
	_sequence += 1
	_step = -1
	if _sequence >= SEQUENCES.size():
		_finish()
		return
	_player.teleport(SPOT, PI)
	_rig.yaw = 0.0
	_next_step()


func _next_step() -> void:
	var steps: Array = SEQUENCES[_sequence][1]
	if _step >= 0:
		for action: String in steps[_step][1]:
			Input.action_release(action)
	_step += 1
	_clock = 0.0
	if _step >= steps.size():
		_next_sequence()
		return
	for action: String in steps[_step][1]:
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
