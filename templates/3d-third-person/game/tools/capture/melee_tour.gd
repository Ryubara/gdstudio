## Films the melee blow of each weapon category from the game camera (gdstudio #1254): an enemy
## grunt (its deciding parts taken out, so it stands and takes the blows) a pace in front of the
## player, three blows of V with the pistol (the whip, the backhand, the jab), H to the fists and
## three left clicks (the jab, the cross, the hook). It presses the input actions the way a player
## would; each blow's landing is printed (`HIT <zone> <damage> <health left>`).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/melee_tour.tscn --seconds 9
## --fps 30`
## `MELEE_SIDE=1` films from the player's right side instead of over the shoulder.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map, and where the player and the grunt stand on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
const GRUNT_AT := Vector3(0.0, 300.1, -1.3)
const GRUNT := "res://gameplay/ai/characters/enemy_grunt.tscn"
## The grunt's parts that decide what it does: taken out, it stands where it is put.
const DECIDING: Array[StringName] = [&"Navigator", &"Brain", &"Senses", &"AiTasks"]
const PITCH := 4.0

## Each stage: `name` (printed when it starts), `seconds` how long, and `taps`: actions pressed for
## 0.1 s at each of the listed seconds into the stage.
const STAGES: Array[Dictionary] = [
	{"name": "ready", "seconds": 0.8},
	{"name": "pistol blows", "seconds": 2.8, "taps": {&"melee": [0.1, 0.95, 1.8]}},
	{"name": "to the fists", "seconds": 0.8, "taps": {&"toggle_unarmed": [0.1]}},
	{"name": "fist blows", "seconds": 2.6, "taps": {&"fire": [0.1, 0.8, 1.5]}},
	{"name": "rest", "seconds": 0.8},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _side := OS.get_environment("MELEE_SIDE") == "1"
var _grunt: AiCharacter

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_grunt = (load(GRUNT) as PackedScene).instantiate() as AiCharacter
	_grunt.navigator = null
	_grunt.brain = null
	_grunt.senses = null
	_grunt.task_runner = null
	for slot in DECIDING:
		var part := _grunt.get_node_or_null(NodePath(slot))
		if part != null:
			_grunt.remove_child(part)
			part.free()
	_grunt.position = GRUNT_AT
	add_child(_grunt)
	_grunt.facing = 0.0
	# The grunt's health is kept high so every blow lands on a standing body.
	Health.of(_grunt).max_value = 1000.0
	Health.of(_grunt).reset()
	_player.teleport(START, PI)
	_player.weapon.melee_started.connect(func(blow: int) -> void: print("BLOW ", blow))
	_player.weapon.hit_scanned.connect(_on_hit)
	_player.loadout.weapon_changed.connect(
		func(definition: WeaponDef) -> void: print("WEAPON ", definition.display_name)
	)


func _on_hit(hit: Dictionary) -> void:
	var record: HitRecord = hit.get("record")
	var zone := String(record.zone) if record != null else "-"
	print("HIT %s %.1f %.1f" % [zone, float(hit.get("damage", 0.0)), Health.of(_grunt).value])


func _physics_process(delta: float) -> void:
	var yaw := 90.0 if _side else 0.0
	_rig.orbit(Vector2(-clampf(wrapf(yaw - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
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
	var stage := STAGES[_index]
	_clock += delta
	var actions: Array[StringName] = []
	var taps: Dictionary = stage.get("taps", {})
	for action: StringName in taps:
		for at: float in taps[action]:
			if _clock >= at and _clock < at + 0.1:
				actions.append(action)
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
