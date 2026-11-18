## Films upper-body actions while leaning (gdstudio #1575) from the game camera, with the HUD: the
## character aims the pistol and leans left, fires and reloads, then the same leaning right; then
## with the fists out it throws a punch leaning left and right; then the rifle's reload leaning
## left and right. The head (and the camera on it) should stay where the lean holds it while the
## arms do the action. It presses the input actions the way a player would and prints each stage
## (`STAGE <name> <tick>`).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/peek_action_tour.tscn --seconds 19
## --fps 30`. `PEEK_HOLD=0` turns the lean's hold off (`PeekTuning.action_hold`): the actions take
## the head as before. `PEEK_BODY=male` films the male prototype body; `PEEK_ONLY=pistol`,
## `fists` or `rifle` films one weapon's stages.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map, and where the character stands on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
## A wall ahead to lean past (as cover would be), and a target beyond it.
const WALL_AT := Vector3(0.0, 300.0, -1.6)
const WALL_SIZE := Vector3(0.6, 2.6, 0.4)
const TARGET_AT := Vector3(0.0, 300.0, -10.0)
const PITCH := 2.0

## Each stage: `name`, `weapon` (pistol, fists or rifle), `hold` the actions held, `seconds` how
## long, and `tap` the actions pressed for one tick at a time into it (seconds).
const STAGES: Array[Dictionary] = [
	{"name": "pistol aim", "weapon": "pistol", "hold": [&"aim"], "seconds": 1.0},
	{
		"name": "pistol lean left, fire, reload",
		"weapon": "pistol",
		"hold": [&"aim", &"lean_left"],
		"seconds": 3.4,
		"tap": [[0.5, &"fire"], [0.9, &"reload"]],
	},
	{
		"name": "pistol lean right, fire, reload",
		"weapon": "pistol",
		"hold": [&"aim", &"lean_right"],
		"seconds": 3.4,
		"tap": [[0.5, &"fire"], [0.9, &"reload"]],
	},
	{"name": "fists aim", "weapon": "fists", "hold": [&"aim"], "seconds": 1.0},
	{
		"name": "fists lean left, punch",
		"weapon": "fists",
		"hold": [&"aim", &"lean_left"],
		"seconds": 2.0,
		"tap": [[0.6, &"melee"]],
	},
	{
		"name": "fists lean right, punch",
		"weapon": "fists",
		"hold": [&"aim", &"lean_right"],
		"seconds": 2.0,
		"tap": [[0.6, &"melee"]],
	},
	{"name": "rifle aim", "weapon": "rifle", "hold": [&"aim"], "seconds": 1.0},
	{
		"name": "rifle lean left, reload",
		"weapon": "rifle",
		"hold": [&"aim", &"lean_left"],
		"seconds": 3.4,
		"tap": [[0.5, &"fire"], [0.9, &"reload"]],
	},
	{
		"name": "rifle lean right, reload",
		"weapon": "rifle",
		"hold": [&"aim", &"lean_right"],
		"seconds": 3.4,
		"tap": [[0.5, &"fire"], [0.9, &"reload"]],
	},
]

var _stages: Array[Dictionary] = []
var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _side: Camera3D

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var only := OS.get_environment("PEEK_ONLY")
	for stage in STAGES:
		if only == "" or stage["weapon"] == only:
			_stages.append(stage)
	var block := load("res://world/blocks/proto_block.tscn") as PackedScene
	var floor_block := block.instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var wall := block.instantiate()
	wall.size = WALL_SIZE
	wall.position = WALL_AT + Vector3.UP * WALL_SIZE.y / 2.0
	add_child(wall)
	var target := (load("res://gameplay/target/target.tscn") as PackedScene).instantiate()
	target.position = TARGET_AT
	add_child(target)
	if OS.get_environment("PEEK_HOLD") == "0" and "action_hold" in _player.peek_tuning:
		_player.peek_tuning = _player.peek_tuning.duplicate()
		_player.peek_tuning.set(&"action_hold", false)
	if OS.get_environment("PEEK_BODY") == "male":
		var old := _player.model.rig()
		_player.model.remove_child(old)
		old.free()
		_player.model.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	_player.teleport(START, PI)
	if OS.get_environment("PEEK_VIEW") == "side":
		_side = Camera3D.new()
		_side.fov = 45.0
		add_child(_side)
		_side.make_current()


func _physics_process(delta: float) -> void:
	if _index >= _stages.size():
		return
	if _index < 0 or _clock >= float(_stages[_index]["seconds"]):
		_next_stage()
		if _index >= _stages.size():
			return
	var stage := _stages[_index]
	_rig.orbit(Vector2(clampf(wrapf(_rig.yaw, -180.0, 180.0), -3.0, 3.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
	var actions: Array[StringName] = []
	actions.append_array(stage["hold"])
	for tap: Array in stage.get("tap", []):
		var at: float = tap[0]
		if _clock >= at - 1e-4 and _clock < at + delta - 1e-4:
			actions.append(tap[1])
	_clock += delta
	_hold(actions)
	if _side != null:
		_film_side()


# The side camera: left of the body and ahead of it, a little over the chest, on it.
func _film_side() -> void:
	var ahead := _player.model.global_basis.z
	ahead = Vector3(ahead.x, 0.0, ahead.z).normalized()
	var right := ahead.cross(Vector3.UP)
	var at := _player.global_position + Vector3.UP * 1.3
	_side.global_position = at + ahead * 1.6 - right * 1.6 + Vector3.UP * 0.2
	_side.look_at(at, Vector3.UP)


func _next_stage() -> void:
	var before: String = _stages[_index]["weapon"] if _index >= 0 else ""
	_index += 1
	_clock = 0.0
	if _index >= _stages.size():
		_finish()
		return
	var weapon: String = _stages[_index]["weapon"]
	if weapon != before:
		_take(weapon)
	print("STAGE ", _stages[_index]["name"], " ", Engine.get_physics_frames())


# Takes `weapon` in the hands: the pistol the body starts with, the fists by the unarmed key, the
# rifle picked up (a weapon given goes to the hands).
func _take(weapon: String) -> void:
	match weapon:
		"pistol":
			(_player.controller as PlayerInput).request_weapon(0)
		"rifle":
			_player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 60)
		"fists":
			Input.action_press(&"toggle_unarmed")
			await get_tree().physics_frame
			await get_tree().physics_frame
			Input.action_release(&"toggle_unarmed")


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
