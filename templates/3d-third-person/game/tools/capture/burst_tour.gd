## Films the burst fire mode (gdstudio #1352) from the game camera, with the HUD: the rifle on
## burst (a copy of its definition, three shots at 15 a second), a one-tick tap of fire from the
## hip (the arm comes up and the whole burst leaves, then the arm goes down), a tap with the aim
## held, a press held for a second (one burst, no more), and two taps close together (the second
## burst follows the first once it may). The ammunition counter drops by three a press. Then the
## same rifle with `full_burst_per_press` off (the burst lasts only while the button is held): a
## one-tick tap aimed fires one shot, a press of five ticks two, a press held for a second the
## whole burst. A caption names each stage. It presses the input actions the way a player would
## and prints each shot's tick (`SHOT <tick> <ammo>`).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/burst_tour.tscn --seconds 15
## --fps 30`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map, and where the character stands on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
## Where the target stands, ahead of the character.
const TARGET_AT := Vector3(0.0, 300.0, -9.0)
const PITCH := 4.0
## One physics tick: the shortest press a player can make.
const TAP := 1.0 / 60.0

## Each stage: `name` (printed when it starts), `hold` the actions held, `seconds` how long, and
## `taps`: actions pressed for `tap` seconds (one tick by default) at each of the listed seconds;
## `full` the rifle's `full_burst_per_press` for the stage (on by default).
const STAGES: Array[Dictionary] = [
	{"name": "ready", "hold": [], "seconds": 1.0},
	{"name": "tap from the hip", "hold": [], "seconds": 1.6, "taps": {&"fire": [0.2]}},
	{"name": "tap aimed", "hold": [&"aim"], "seconds": 1.6, "taps": {&"fire": [0.6]}},
	{
		"name": "held one second",
		"hold": [&"aim"],
		"seconds": 1.8,
		"taps": {&"fire": [0.3]},
		"tap": 1.0,
	},
	{"name": "two taps", "hold": [&"aim"], "seconds": 1.8, "taps": {&"fire": [0.3, 0.45]}},
	{"name": "full burst off", "hold": [&"aim"], "seconds": 0.6, "full": false},
	{
		"name": "full burst off: tap aimed",
		"hold": [&"aim"],
		"seconds": 1.4,
		"taps": {&"fire": [0.3]},
		"full": false,
	},
	{
		"name": "full burst off: 5 ticks",
		"hold": [&"aim"],
		"seconds": 1.4,
		"taps": {&"fire": [0.3]},
		"tap": 5.0 * TAP,
		"full": false,
	},
	{
		"name": "full burst off: held one second",
		"hold": [&"aim"],
		"seconds": 1.8,
		"taps": {&"fire": [0.3]},
		"tap": 1.0,
		"full": false,
	},
	{"name": "down", "hold": [], "seconds": 0.8},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
# Made in _ready, not here: a scene instantiated and freed off the tree would orphan it.
var _caption: Label

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var target := (load("res://gameplay/target/target.tscn") as PackedScene).instantiate()
	target.position = TARGET_AT
	add_child(target)
	var rifle := (load("res://gameplay/weapon/rifle.tres") as WeaponDef).duplicate() as WeaponDef
	rifle.fire_mode = WeaponDef.FireMode.BURST
	rifle.auto_reload = false
	_player.loadout.give(rifle, 60)
	_player.teleport(START, PI)
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24.0, 24.0)
	_caption.add_theme_font_size_override("font_size", 28)
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_caption)
	_player.weapon.fired.connect(
		func(_shot: Projectile) -> void:
			print("SHOT ", Engine.get_physics_frames(), " ", _player.weapon.ammo)
	)


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(-_rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= STAGES.size():
			_finish()
			return
		print("STAGE ", STAGES[_index]["name"], " ", Engine.get_physics_frames())
		_caption.text = STAGES[_index]["name"]
		_player.weapon.definition.full_burst_per_press = STAGES[_index].get("full", true)
	var stage := STAGES[_index]
	var actions: Array[StringName] = []
	actions.append_array(stage["hold"])
	var taps: Dictionary = stage.get("taps", {})
	var length: float = stage.get("tap", TAP)
	for action: StringName in taps:
		for at: float in taps[action]:
			if _clock >= at - 1e-4 and _clock < at + length - 1e-4:
				actions.append(action)
	_clock += delta
	_hold(actions)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	_hold([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array[StringName]) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action in actions:
		Input.action_press(action)
		_held.append(action)
