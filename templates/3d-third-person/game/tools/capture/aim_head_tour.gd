## Films the head while the character aims, from the player's own shoulder camera (kit #1334):
## the pistol aimed level, down and up, walking and crouched, then the rifle standing, crouched and
## lying, then the fists, each with the aim raised and lowered so the start and end of an aim show
## too. `AIM_HEAD=0` turns the aim layer's head off (`AimLayer.head_disabled`), as before the fix,
## for the pull request's before and after.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/aim_head_tour.tscn --seconds 30
## --fps 10`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing to walk into, no camera zone).
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 10.0)

## Each stage: `name` (printed when it starts), `hold` the actions held, `tap` the actions pressed
## for one tick at its start, `give` a weapon handed over at its start, `pitch` the view's pitch
## and `seconds` how long. Crouch is held (the tuning's crouch is held by default, not toggled).
const STAGES: Array[Dictionary] = [
	{"name": "pistol lowered", "hold": [], "seconds": 1.0},
	{"name": "pistol aim level", "hold": [&"aim"], "seconds": 2.5},
	{"name": "pistol aim down", "hold": [&"aim"], "pitch": -25.0, "seconds": 2.0},
	{"name": "pistol aim up", "hold": [&"aim"], "pitch": 15.0, "seconds": 2.0},
	{"name": "pistol aim walking", "hold": [&"aim", &"move_right"], "seconds": 2.0},
	{"name": "pistol lowered again", "hold": [], "seconds": 1.0},
	{"name": "pistol crouched aim", "hold": [&"aim", &"crouch"], "seconds": 2.5},
	{"name": "rifle", "hold": [], "give": "rifle", "seconds": 2.0},
	{"name": "rifle aim level", "hold": [&"aim"], "seconds": 2.5},
	{"name": "rifle aim down", "hold": [&"aim"], "pitch": -25.0, "seconds": 2.0},
	{"name": "rifle crouched aim", "hold": [&"aim", &"crouch"], "seconds": 2.5},
	{"name": "rifle lying aim", "hold": [&"aim"], "tap": [&"prone"], "seconds": 3.5},
	{"name": "fists", "hold": [], "tap": [&"prone", &"toggle_unarmed"], "seconds": 2.0},
	{"name": "fists aim down", "hold": [&"aim"], "pitch": -25.0, "seconds": 2.0},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _tapped: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var layer := _player.get_node("AimLayer") as AimLayer
	layer.head_disabled = OS.get_environment("AIM_HEAD") == "0"
	print("aim head ", not layer.head_disabled)
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(30.0, 1.0, 60.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_player.teleport(START, PI)


func _physics_process(delta: float) -> void:
	for action in _tapped:
		Input.action_release(action)
	_tapped.clear()
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= STAGES.size():
			_finish()
			return
		_begin(STAGES[_index])
	_clock += delta
	var pitch := float(STAGES[_index].get("pitch", 0.0))
	_rig.orbit(Vector2(-clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(pitch - _rig.pitch, -2.0, 2.0)))
	var actions: Array[StringName] = []
	actions.append_array(STAGES[_index]["hold"])
	_hold(actions)


func _begin(stage: Dictionary) -> void:
	print("STAGE ", stage["name"])
	if stage.get("give", "") == "rifle":
		_player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 30)
	for action: StringName in stage.get("tap", []):
		Input.action_press(action)
		_tapped.append(action)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
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
