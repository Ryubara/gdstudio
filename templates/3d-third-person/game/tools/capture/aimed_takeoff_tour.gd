## Films the jump begun in a stop clip of gdstudio #1462 from the game's own camera, driven by the
## actions a player presses: the pistol up, a jog aimed, the stick let go (a stop clip begins), a
## jump in the stop and the flight, then the same jump from a still stand. A label names each part
## and shows the body machine's state and the transition's clip; every physics frame prints them on
## a line starting `TAKEOFFTOUR`.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder), at 60 frames
## a second for a clip slowed to half speed:
## `gds capture frames --project game --seconds 6 --fps 60 --name takeoff`
## with `--scene res://tools/capture/aimed_takeoff_tour.tscn`, then
## `gds capture clip <folder> --gif --slow 2`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## An open spot of the sample map, looking north (-Z) with room ahead.
const SPOT := Vector3(4.0, 0.0, 18.0)
const PISTOL := "res://gameplay/weapon/pistol.tres"
## The parts: a title, seconds, and the actions held through it.
const PARTS: Array[Array] = [
	["Aim", 0.6, [&"aim"]],
	["Jog, aiming", 0.75, [&"aim", &"move_forward"]],
	["Stop", 0.13, [&"aim"]],
	["Jump in the stop", 0.2, [&"aim", &"jump"]],
	["In the air", 1.3, [&"aim"]],
	["Still stand, aiming", 0.8, [&"aim"]],
	["Jump from the stand", 0.2, [&"aim", &"jump"]],
	["In the air ", 1.3, [&"aim"]],
]

var _part := -1
var _clock := 0.0
var _label: Label

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _animation: CharacterAnimation = $Main/PlayerRig/Player/Animation


func _ready() -> void:
	_player.teleport(SPOT, 0.0)
	_rig.yaw = 0.0
	_rig.pitch = 5.0
	var pistol := load(PISTOL) as WeaponDef
	if _player.weapon == null or _player.weapon.definition != pistol:
		_player.loadout.give(pistol, 60)
	_build_label()
	_next()


func _physics_process(delta: float) -> void:
	_clock += delta
	if _part >= PARTS.size():
		return
	var part: Array = PARTS[_part]
	var state: String = Character.State.keys()[_player.state]
	_label.text = (
		"%s\nbody %s   clips %s %s"
		% [part[0], state, _animation.body_state(), _animation.gait.transitions.clip]
	)
	print(
		"TAKEOFFTOUR ",
		_part,
		" ",
		snappedf(_clock, 0.01),
		" ",
		state,
		" ",
		_animation.body_state(),
		" ",
		_animation.gait.transitions.clip
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
