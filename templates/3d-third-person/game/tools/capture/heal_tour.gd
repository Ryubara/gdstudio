## Films a hurt character using bandages from the hotbar (kit #1342), from the game camera with the
## HUD: with the pistol aimed (the aim goes down for the use), three quick presses of key 3 that use
## one bandage, the rifle at the low ready, and a use cut short by a sprint. It presses the input
## actions the way a player would; the sound is the bandage's own.
##
## Record it with Movie Maker through the kit (the frames and the sound land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/heal_tour.tscn --seconds 15
## --fps 30`, then `gds capture clip <folder>` for an MP4 with the sound.
## It prints a `STAGE` line as each stage starts and a `USE` line for every start, heal, end and cut
## of a use, with the health and the bandages left. It lives in tools/, which the export leaves
## out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map, and where the character stands on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
const PITCH := 6.0
const RIFLE := "res://gameplay/weapon/rifle.tres"
## The camera's yaw for the stages filmed from the character's left, where the left hand shows.
const SIDE_YAW := -60.0
## The health the character starts the tour with.
const START_HEALTH := 15.0

## Each stage: `name`, `hold` the actions held, `seconds` how long, `taps`: actions pressed for
## 0.1 s at each of the listed seconds into the stage, `give`: the rifle is handed over, and
## `yaw`: where the camera orbits to.
const STAGES: Array[Dictionary] = [
	{"name": "pistol, aim", "hold": [&"aim"], "seconds": 1.0},
	{
		"name": "pistol, aim, bandage",
		"hold": [&"aim"],
		"seconds": 2.2,
		"taps": {&"hotbar_1": [0.1]},
	},
	{
		"name": "pistol, three presses, one bandage",
		"hold": [],
		"seconds": 2.2,
		"taps": {&"hotbar_1": [0.1, 0.4, 0.7]},
		"yaw": SIDE_YAW,
	},
	{"name": "rifle out", "hold": [], "seconds": 1.2, "give": true, "yaw": SIDE_YAW},
	{
		"name": "rifle, bandage",
		"hold": [],
		"seconds": 2.2,
		"taps": {&"hotbar_1": [0.1]},
		"yaw": SIDE_YAW,
	},
	{"name": "rifle, bandage", "hold": [], "seconds": 0.7, "taps": {&"hotbar_1": [0.1]}},
	{"name": "sprint cuts it short", "hold": [&"move_forward", &"sprint"], "seconds": 1.2},
	{"name": "rest", "hold": [], "seconds": 1.0},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _yaw := 0.0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(60.0, 1.0, 60.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_player.teleport(START, PI)
	Health.of(_player).value = START_HEALTH
	var use := ItemUse.of(_player)
	use.started.connect(func(_p: int, _i: ItemDef, _s: float) -> void: _say("start"))
	use.applied.connect(func(_p: int, _i: ItemDef) -> void: _say("healed"))
	use.finished.connect(func(_p: int, _i: ItemDef) -> void: _say("end"))
	use.cancelled.connect(func(_p: int, _i: ItemDef, why: StringName) -> void: _say("cut " + why))


func _say(what: String) -> void:
	print(
		(
			"USE %s health %d bandages %d"
			% [what, Health.of(_player).value, _player.inventory.count_of_id(&"bandage")]
		)
	)


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(_yaw - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_index += 1
		_clock = 0.0
		if _index >= STAGES.size():
			_finish()
			return
		print("STAGE ", STAGES[_index]["name"])
		_yaw = STAGES[_index].get("yaw", 0.0)
		if STAGES[_index].get("give", false):
			_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	var stage := STAGES[_index]
	_clock += delta
	var actions: Array[StringName] = []
	actions.append_array(stage["hold"])
	var taps: Dictionary = stage.get("taps", {})
	for action: StringName in taps:
		for at: float in taps[action]:
			if _clock >= at and _clock < at + 0.1:
				actions.append(action)
	_hold_actions(actions)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	_hold_actions([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


# Holds exactly these actions down and lets go of the rest.
func _hold_actions(actions: Array[StringName]) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action in actions:
		Input.action_press(action)
		_held.append(action)
