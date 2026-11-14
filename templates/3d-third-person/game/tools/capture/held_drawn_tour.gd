extends Node
## Films the rifle in the hands through the moves where a frame of lag shows most, from the game
## camera brought close beside the character (gdstudio #1473): a sprint into a slide that ends in
## the crouch, standing up, and a sprint into a jump and its landing. It presses the input actions
## the way a player would and prints the frame of each slide end and landing (`MARK`), so the
## pull request can show those frames. Run at 60 frames a second, as the game draws:
## `gds capture frames --project game --scene res://tools/capture/held_drawn_tour.tscn --seconds 8
## --fps 60`
## `HELD_PISTOL=1` keeps the pistol instead. It lives in tools/, which the export leaves out.

const RIFLE := "res://gameplay/weapon/rifle.tres"
## A flat floor high above the map, and where each stage starts.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(-16.0, 300.1, 0.0)
const PITCH := 6.0
const DISTANCE := 2.6

## `name`, `hold` (the actions held), `seconds`, `reset` (back to the start), and `tap` pressed
## for `tap_seconds` at `tap_at` seconds into the stage.
const STAGES: Array[Dictionary] = [
	{"name": "draw", "hold": [], "seconds": 1.2, "reset": true},
	{"name": "sprint", "hold": [&"move_right", &"sprint"], "seconds": 1.0},
	{"name": "slide", "hold": [&"move_right", &"sprint", &"crouch"], "seconds": 1.8},
	{"name": "stand", "hold": [], "seconds": 0.6},
	{"name": "sprint", "hold": [&"move_right", &"sprint"], "seconds": 0.9, "reset": true},
	{
		"name": "jump",
		"hold": [&"move_right", &"sprint"],
		"seconds": 1.6,
		"tap": [&"jump"],
		"tap_at": 0.1,
		"tap_seconds": 0.1,
	},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []
var _frame := 0
var _was_sliding := false
var _was_on_floor := true

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var blocks := load("res://world/blocks/proto_block.tscn") as PackedScene
	var floor_block := blocks.instantiate()
	floor_block.size = Vector3(40.0, 1.0, 24.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_rig.distance = DISTANCE
	_player.teleport(START, PI / 2.0)
	if OS.get_environment("HELD_PISTOL") != "1":
		_player.loadout.give(load(RIFLE) as WeaponDef, 60)


func _process(_delta: float) -> void:
	_frame += 1
	if _player.sliding != _was_sliding:
		if _was_sliding:
			print("MARK slide end at frame ", _frame)
		_was_sliding = _player.sliding
	if _player.is_on_floor() != _was_on_floor:
		if _player.is_on_floor():
			print("MARK landing at frame ", _frame)
		_was_on_floor = _player.is_on_floor()


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
	print("STAGE ", stage["name"], " at frame ", _frame)
	if stage.get("reset", false):
		_hold([])
		_player.teleport(START, PI / 2.0)


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	_hold([])
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _step in 8:
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
