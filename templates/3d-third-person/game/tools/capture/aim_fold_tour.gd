## Films the upper body through an aim going up and coming down, standing and crouched, and a shot
## from the carry, from the game camera (kit #1318: the aim layer folded the chest back on the
## first and last frames of every aim). It presses the input actions the way a player would (it
## only puts the body back at the start of each stage). Record it at 60 frames a second and play
## the frames at 15 to see each frame of the aim at a quarter of the speed:
## `gds capture frames --project game --scene res://tools/capture/aim_fold_tour.tscn --seconds 8
## --fps 60`
## `AIM_LAYER_OFF=1` turns the aim layer off (the clips alone). It lives in tools/, which the
## export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing to walk into, no camera zone), where each
## stage starts, and the camera's pitch.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(-12.0, 300.1, 0.0)
const PITCH := 10.0
## The camera backs off the shoulder view's 1.7 m a little, so the whole upper body is in frame.
const DISTANCE := 2.4

## The tour. Each stage is a dictionary: `name` (printed when it starts), `hold` the actions held,
## `seconds` how long, `reset` to put the body back at the start (facing -Z, the camera's heading,
## so aiming turns nothing), `tap` actions pressed for `tap_seconds` at `tap_at` seconds into the
## stage.
const STAGES: Array[Dictionary] = [
	{"name": "stand", "hold": [], "seconds": 0.6, "reset": true},
	{"name": "aim", "hold": [&"aim"], "seconds": 0.9},
	{"name": "let go", "hold": [], "seconds": 0.9},
	{
		"name": "hip fire",
		"hold": [],
		"seconds": 1.6,
		"tap": [&"fire"],
		"tap_at": 0.1,
		"tap_seconds": 0.12,
	},
	{"name": "crouch", "hold": [&"crouch"], "seconds": 0.8, "reset": true},
	{"name": "crouched aim", "hold": [&"crouch", &"aim"], "seconds": 0.9},
	{"name": "crouched let go", "hold": [&"crouch"], "seconds": 1.0},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	if OS.get_environment("AIM_LAYER_OFF") == "1":
		(_player.get_node("AimLayer") as AimLayer).disabled = true
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(60.0, 1.0, 30.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_rig.distance = DISTANCE
	_player.teleport(START, PI)


func _physics_process(delta: float) -> void:
	_rig.orbit(Vector2(-clampf(wrapf(0.0 - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_next()
		if _index >= STAGES.size():
			_finish()
			return
	var stage := STAGES[_index]
	_clock += delta
	var actions: Array[StringName] = []
	actions.append_array(stage["hold"])
	if stage.has("tap"):
		var from := float(stage["tap_at"])
		if _clock >= from and _clock < from + float(stage["tap_seconds"]):
			actions.append_array(stage["tap"])
	_hold(actions)


func _next() -> void:
	_index += 1
	_clock = 0.0
	if _index >= STAGES.size():
		return
	var stage := STAGES[_index]
	print("STAGE ", stage["name"])
	if stage.get("reset", false):
		_player.teleport(START, PI)


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
