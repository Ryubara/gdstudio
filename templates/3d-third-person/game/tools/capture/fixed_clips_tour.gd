## Films the two fixed clips the game plays (`CharacterClips.STAND_INS`, kit #1295) from the game
## camera, close: a jump on the spot and its landing seen from the body's left (the arm the
## landing's fix swings), then a sprint into a slide that is let go of, seen from its right (the
## slide exit's arm). It presses the input actions the way a player would and only puts the body
## back at the start of a stage. `LIBRARY_CLIPS=1` plays the library's own clips instead, for the
## capture to compare with.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/fixed_clips_tour.tscn --seconds 9
## --fps 30`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing to walk into, no camera zone).
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(-14.0, 300.1, 0.0)
const PITCH := 6.0
const DISTANCE := 2.4

## `name`, the actions held, `seconds`, `reset` (to the start), the camera's `yaw` (0 looks at
## the body's right side, 180 at its left), and `tap` pressed for `tap_seconds` at `tap_at`.
const STAGES: Array[Dictionary] = [
	{"name": "stand", "hold": [], "seconds": 0.8, "reset": true, "yaw": 180.0},
	{
		"name": "jump and land",
		"hold": [],
		"seconds": 2.2,
		"yaw": 180.0,
		"tap": [&"jump"],
		"tap_at": 0.1,
		"tap_seconds": 0.2,
	},
	{"name": "turn", "hold": [], "seconds": 1.0, "yaw": 0.0},
	{"name": "sprint", "hold": [&"move_right", &"sprint"], "seconds": 1.0, "yaw": 0.0},
	{"name": "slide", "hold": [&"move_right", &"sprint", &"crouch"], "seconds": 1.8, "yaw": 0.0},
	{"name": "stand", "hold": [], "seconds": 1.6, "yaw": 0.0},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var blocks := load("res://world/blocks/proto_block.tscn") as PackedScene
	var floor_block := blocks.instantiate()
	floor_block.size = Vector3(60.0, 1.0, 24.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	if OS.get_environment("LIBRARY_CLIPS") == "1":
		var animation: CharacterAnimation = _player.get_node("Animation")
		animation.land_clip = CharacterClips.STAND_INS[animation.land_clip]
		animation.slide_exit_clip = CharacterClips.STAND_INS[animation.slide_exit_clip]
	_rig.distance = DISTANCE
	_player.teleport(START, PI / 2.0)


func _physics_process(delta: float) -> void:
	if _index >= STAGES.size():
		return
	if _index < 0 or _clock >= float(STAGES[_index]["seconds"]):
		_next()
		if _index >= STAGES.size():
			_finish()
			return
	var stage := STAGES[_index]
	var yaw := float(stage["yaw"])
	_rig.orbit(Vector2(-clampf(wrapf(yaw - _rig.yaw, -180.0, 180.0), -8.0, 8.0), 0.0))
	_rig.orbit(Vector2(0.0, clampf(PITCH - _rig.pitch, -2.0, 2.0)))
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
	print("STAGE ", stage["name"], " ", _player.global_position)
	if stage.get("reset", false):
		_hold([])
		_player.teleport(START, PI / 2.0)


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
