## Films how fast the body answers its movement keys (gdstudio #1565), driven by the actions a
## player presses: a sprint reversal (W then S), W+A to W+D through W alone for 0.05 s at a sprint,
## the keys spammed through a sprint reversal, and crouch and aim pressed in a jog's stop; the
## reversal and the spam again from the side, and lying down from a jog. A label names the sequence
## and shows the keys held, the ground speed, the ticks since the last change of keys and the clip
## the tree plays; every drawn frame prints a line starting `RESPONSETOUR` with the sequence, so a
## recording can be cut into one clip a sequence. Before #1565 a reversal held the body on its
## clip's path for 1.8 to 2.2 s and every key pressed meanwhile was ignored.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 40 --fps 30 --name response`
## with `--scene res://tools/capture/responsive_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing to walk into, no camera zone), and the spot on
## it each sequence starts from.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const SPOT := Vector3(0.0, 300.1, 0.0)
const NAMES := {
	"move_forward": "W",
	"move_left": "A",
	"move_back": "S",
	"move_right": "D",
	"sprint": "Shift",
	"crouch": "C",
	"aim": "Aim",
	"prone": "Z",
}
const SPAM := [
	["move_right"],
	["move_left"],
	["move_forward"],
	["move_back"],
	["move_forward", "move_right"],
	["move_left"],
	["move_back", "move_right"],
	["move_forward"],
	["move_right"],
	["move_back"],
]
## The sequences: a title, the side view or the game's camera, then steps of seconds and the
## actions held.
var sequences: Array[Array] = [
	[
		"Sprint: W, then S",
		false,
		[
			[1.6, ["move_forward", "sprint"]],
			[1.4, ["move_back", "sprint"]],
			[1.2, []],
		]
	],
	[
		"Sprint: W+A, W for 0.05 s, W+D",
		false,
		[
			[1.6, ["move_forward", "move_left", "sprint"]],
			[0.05, ["move_forward", "sprint"]],
			[1.4, ["move_forward", "move_right", "sprint"]],
			[1.2, []],
		]
	],
	["Sprint: W, S, then the keys spammed", false, _spam_steps()],
	[
		"Jog: W, let go, crouch in the stop",
		false,
		[[1.4, ["move_forward"]], [0.25, []], [1.3, ["crouch"]], [1.2, []]]
	],
	[
		"Jog: W, let go, aim in the stop",
		false,
		[[1.4, ["move_forward"]], [0.25, []], [1.3, ["aim"]], [1.2, []]]
	],
	[
		"Sprint: W, then S (side view)",
		true,
		[
			[1.6, ["move_forward", "sprint"]],
			[1.4, ["move_back", "sprint"]],
			[1.2, []],
		]
	],
	["Sprint: W, S, then the keys spammed (side view)", true, _spam_steps()],
	[
		"Jog: W, then lying down from the run (side view)",
		true,
		[[1.4, ["move_forward"]], [0.1, ["move_forward", "prone"]], [1.6, ["move_forward"]]]
	],
]

var _sequence := -1
var _step := -1
var _clock := 0.0
var _since_change := 0
var _label: Label
var _side: Camera3D

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _animation: CharacterAnimation = $Main/PlayerRig/Player/Animation


func _ready() -> void:
	_rig.pitch = 18.0
	_rig.distance = 4.5  # Further back than play, so the feet stay in the frame.
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(80.0, 1.0, 80.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_side = Camera3D.new()
	_side.fov = 50.0
	add_child(_side)
	_build_label()
	_next_sequence()


func _process(_delta: float) -> void:
	if _sequence >= sequences.size():
		return
	if _side.current:
		# Beside the lane the body runs along (+X and back from the start), level with the hips.
		var at := _player.global_position
		_side.global_position = Vector3(at.x, at.y + 1.1, at.z - 7.0)
		_side.look_at(at + Vector3(0.0, 0.9, 0.0), Vector3.UP)
	print("RESPONSETOUR ", _sequence, " ", Engine.get_frames_drawn())


func _physics_process(delta: float) -> void:
	if _sequence >= sequences.size():
		return
	_clock += delta
	_since_change += 1
	var steps: Array = sequences[_sequence][2]
	if _clock >= float(steps[_step][0]):
		_next_step()
		if _sequence >= sequences.size():
			return
	var held: Array = sequences[_sequence][2][_step][1]
	var keys := PackedStringArray()
	for action: String in held:
		keys.append(NAMES[action])
	var clip := String(_animation.gait.transitions.clip).trim_prefix("gds/")
	var shown := clip if clip != "" else String(_animation.body_state())
	_label.text = (
		"%s\nkeys %s   speed %.2f m/s   %d ticks since the keys changed\n%s"
		% [
			sequences[_sequence][0],
			"+".join(keys) if not keys.is_empty() else "none",
			_player.ground_speed(),
			_since_change,
			shown
		]
	)


func _spam_steps() -> Array:
	var steps: Array = [[1.6, ["move_forward", "sprint"]], [0.15, ["move_back", "sprint"]]]
	for keys: Array in SPAM:
		steps.append([0.12, keys + ["sprint"]])
	steps.append([1.2, []])
	return steps


func _next_sequence() -> void:
	_sequence += 1
	_step = -1
	if _sequence >= sequences.size():
		_finish()
		return
	_player.teleport(SPOT, PI)
	_rig.yaw = 0.0
	if sequences[_sequence][1]:
		_side.make_current()
	else:
		_side.clear_current()
	_next_step()


func _next_step() -> void:
	var steps: Array = sequences[_sequence][2]
	if _step >= 0:
		for action: String in steps[_step][1]:
			Input.action_release(action)
	_step += 1
	_clock = 0.0
	_since_change = 0
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
