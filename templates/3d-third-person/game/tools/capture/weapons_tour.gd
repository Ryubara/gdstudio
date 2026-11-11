## Films the weapon system from the game camera, with the HUD: the pistol fired to an empty
## magazine (the ammo counts down), a pull on the empty magazine (a click), R and the reload (the
## clip, the rounds going in at its end), H to the fists and two punches, then H back to the
## pistol with its rounds. It presses the input actions the way a player would, for the pull
## request's captures. The pistol's automatic reload is off for the tour (a copy of its
## definition), so the empty magazine and the reload button are both seen.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/weapons_tour.tscn --seconds 14
## --fps 20`
## `WEAPONS_SIDE=1` films from the character's right side instead of over the shoulder.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map, and where the character stands on it.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(0.0, 300.1, 0.0)
const PITCH := 6.0

## Each stage: `name` (printed when it starts), `hold` the actions held, `seconds` how long, and
## `taps`: actions pressed for 0.1 s at each of the listed seconds into the stage.
const STAGES: Array[Dictionary] = [
	{"name": "ready", "hold": [], "seconds": 0.8},
	{
		"name": "fire to empty",
		"hold": [&"aim"],
		"seconds": 4.4,
		"taps": {&"fire": [0.4, 0.7, 1.0, 1.3, 1.6, 1.9, 2.2, 2.5, 2.8, 3.1, 3.4, 3.7]},
	},
	{"name": "empty click", "hold": [&"aim"], "seconds": 0.8, "taps": {&"fire": [0.2]}},
	{"name": "reload", "hold": [], "seconds": 2.2, "taps": {&"reload": [0.1]}},
	{"name": "to the fists", "hold": [], "seconds": 0.9, "taps": {&"toggle_unarmed": [0.1]}},
	{"name": "punch", "hold": [], "seconds": 1.6, "taps": {&"fire": [0.2, 0.8]}},
	{"name": "back to the pistol", "hold": [], "seconds": 1.2, "taps": {&"toggle_unarmed": [0.1]}},
	{"name": "aim again", "hold": [&"aim"], "seconds": 1.0},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _side := OS.get_environment("WEAPONS_SIDE") == "1"

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(40.0, 1.0, 40.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	var pistol := _player.loadout.slots[0].duplicate() as WeaponDef
	pistol.auto_reload = false
	_player.loadout.slots[0] = pistol
	_player.weapon.definition = pistol
	_player.teleport(START, PI)
	_player.weapon.ammo_changed.connect(func(ammo: int) -> void: print("AMMO ", ammo))
	_player.weapon.dry_fired.connect(func() -> void: print("CLICK"))
	_player.weapon.reloaded.connect(func() -> void: print("RELOADED ", _player.weapon.reserve))
	_player.loadout.weapon_changed.connect(
		func(definition: WeaponDef) -> void: print("WEAPON ", definition.display_name)
	)


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
	actions.append_array(stage["hold"])
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
