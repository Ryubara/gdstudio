## Films running with the rifle from the game camera, with a second view from the side in the
## corner (kit #1333): the rifle given and brought out, a run, a switch to the pistol and back
## while running, the run straight after it, a short burst on the move, the run after the shots,
## a sprint, a slide and the run after it. The run before the burst and the run after it are the
## same pose: a shot leaves nothing on the body once its hold time is over. It presses the input
## actions the way a player would.
##
## Record it with Movie Maker through the kit, once for each body (`RUN_MODEL=male` swaps the
## model at the start; the female is the default):
## `gds capture frames --project game --scene res://tools/capture/rifle_run_tour.tscn --seconds
## 15 --fps 20`
## It prints a `STAGE` line as each stage starts. It lives in tools/, which the export leaves
## out, and nothing in the game refers to it.
extends Node

const RIFLE := "res://gameplay/weapon/rifle.tres"
## A long flat floor built high above the map, and where the character starts on it.
const FLOOR_SIZE := Vector3(30.0, 1.0, 400.0)
const START := Vector3(0.0, 300.1, 180.0)
const PITCH := 4.0
## Where the side view's camera is from the character, in its space (+Z its front, +X its left),
## and how high on the character it looks.
const SIDE_FROM := Vector3(-3.4, 1.0, 0.3)
const SIDE_AT := 0.95

## Each stage: `name`, `hold` the actions held, `seconds` how long and `taps`: actions pressed for
## 0.1 s at each of the listed seconds into the stage.
const STAGES: Array[Dictionary] = [
	{"name": "draw", "hold": [], "seconds": 1.0},
	{"name": "run", "hold": [&"move_forward"], "seconds": 1.5},
	{
		"name": "to the pistol",
		"hold": [&"move_forward"],
		"seconds": 1.2,
		"taps": {&"previous_weapon": [0.1]}
	},
	{
		"name": "back to the rifle",
		"hold": [&"move_forward"],
		"seconds": 1.2,
		"taps": {&"next_weapon": [0.1]}
	},
	{"name": "run after the switch", "hold": [&"move_forward"], "seconds": 2.0},
	{"name": "burst", "hold": [&"move_forward", &"fire"], "seconds": 0.5},
	{"name": "run after the shots", "hold": [&"move_forward"], "seconds": 2.5},
	{"name": "sprint", "hold": [&"move_forward", &"sprint"], "seconds": 1.6},
	{"name": "slide", "hold": [&"move_forward", &"sprint", &"crouch"], "seconds": 1.2},
	{"name": "run after the slide", "hold": [&"move_forward"], "seconds": 1.6},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _side: Camera3D

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = FLOOR_SIZE
	floor_block.position = Vector3(0.0, START.y - 0.6, 0.0)
	add_child(floor_block)
	if OS.get_environment("RUN_MODEL") == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		slot.add_child((load(CharacterBodies.MALE) as PackedScene).instantiate())
	_player.teleport(START, PI)
	_player.loadout.give(load(RIFLE) as WeaponDef, 60)
	_player.loadout.weapon_changed.connect(
		func(definition: WeaponDef) -> void: print("WEAPON ", definition.display_name)
	)
	# The side view is drawn by a viewport of its own in the corner: the game aims along the main
	# viewport's camera, so a second camera made current there would turn the character to it.
	process_priority = 1000
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.anchor_left = 0.56
	container.anchor_right = 1.0
	container.anchor_top = 0.0
	container.anchor_bottom = 0.62
	layer.add_child(container)
	var view := SubViewport.new()
	view.world_3d = get_viewport().world_3d
	container.add_child(view)
	_side = Camera3D.new()
	_side.fov = 34.0
	view.add_child(_side)


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
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
	_hold_actions(actions)


func _process(_delta: float) -> void:
	var facing := _player.model.global_basis
	var feet := _player.global_position
	_side.global_position = feet + facing * SIDE_FROM
	_side.look_at(feet + Vector3.UP * SIDE_AT + facing * Vector3(0.0, 0.0, SIDE_FROM.z))


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
