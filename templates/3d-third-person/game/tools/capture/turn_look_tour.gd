## Films the drawn reversals and the quarter turn of gdstudio #1574 in real time, driven by the
## actions a player presses: a jog away from the camera and back toward it (W to S), the same at a
## sprint, and a jog with W+A then W+D. `turn_look_tour_side.tscn` presses the same moves turned a
## quarter (D to A, D+W to D+S), so the plant and the hips coming round are seen side on.
## A label names each part and shows the ticks since the keys changed and how far the drawn body
## is from the way asked. Every physics frame it prints the part, the clock, the transition's kind,
## the drawn yaw and the facing on a line starting `TURNTOUR`.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 11 --fps 30 --name turns`
## with `--scene res://tools/capture/turn_look_tour.tscn` (or `turn_look_tour_side.tscn`).
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing in the view), and where the body starts on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const SPOT := Vector3(0.0, 300.1, 10.0)
## The parts: a title, seconds, the actions held through it, and whether the body starts again at
## the spot.
const PARTS: Array[Array] = [
	["Jog W", 1.2, [&"move_forward"], true],
	["Jog W to S", 1.6, [&"move_back"], false],
	["Sprint W", 1.4, [&"move_forward", &"sprint"], true],
	["Sprint W to S", 1.8, [&"move_back", &"sprint"], false],
	["Jog W+A", 1.2, [&"move_forward", &"move_left"], true],
	["Jog W+A to W+D", 1.6, [&"move_forward", &"move_right"], false],
	["", 0.6, [], false],
]
## The keys the side view presses for each one the game view does: the same moves turned a
## quarter to the right, so the body runs across the game's camera and is seen side on.
const SIDE_KEYS := {
	&"move_forward": &"move_right",
	&"move_back": &"move_left",
	&"move_left": &"move_forward",
	&"move_right": &"move_back",
}

## Turns every move a quarter to the right (`turn_look_tour_side.tscn`): the body runs across the
## game's camera, seen side on.
@export var side_view := false

var _part := -1
var _clock := 0.0
var _ticks := 0
var _label: Label

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _animation: CharacterAnimation = $Main/PlayerRig/Player/Animation


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 80.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_player.teleport(SPOT, PI)
	_rig.yaw = 0.0
	_rig.pitch = 12.0
	if side_view:
		_rig.distance = 5.0  # Further back than play, so the whole body runs across the frame.
	_build_label()
	_next()


func _physics_process(delta: float) -> void:
	_clock += delta
	_ticks += 1
	if _part >= PARTS.size():
		return
	var part: Array = PARTS[_part]
	var transitions := _animation.gait.transitions
	var drawn := _player.facing + transitions.look.offset
	var wish := _player._wish_direction()
	var left := 0.0
	if not wish.is_zero_approx():
		left = rad_to_deg(absf(angle_difference(drawn, atan2(wish.x, wish.z))))
	var kind: String = GaitTransitions.Kind.keys()[transitions.kind]
	_label.text = (
		"%s\n%d ticks   %.0f deg to go   %.1f m/s   %s"
		% [part[0], _ticks, left, _player.ground_speed(), kind.to_lower()]
	)
	print(
		"TURNTOUR ",
		_part,
		" ",
		_ticks,
		" ",
		kind,
		" ",
		snappedf(rad_to_deg(drawn), 0.1),
		" ",
		snappedf(rad_to_deg(_player.facing), 0.1),
		" ",
		snappedf(left, 0.1)
	)
	if _clock >= part[1]:
		_next()


func _next() -> void:
	if _part >= 0:
		for action: StringName in PARTS[_part][2]:
			Input.action_release(_key(action))
	_part += 1
	_clock = 0.0
	_ticks = 0
	if _part >= PARTS.size():
		_finish()
		return
	var part: Array = PARTS[_part]
	if part[3]:
		_player.teleport(SPOT, PI)
	for action: StringName in part[2]:
		Input.action_press(_key(action))


# The action pressed for `action`: turned a quarter in the side view.
func _key(action: StringName) -> StringName:
	return SIDE_KEYS.get(action, action) if side_view else action


func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	_label = Label.new()
	_label.position = Vector2(24.0, 24.0)
	_label.add_theme_font_size_override(&"font_size", 28)
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
