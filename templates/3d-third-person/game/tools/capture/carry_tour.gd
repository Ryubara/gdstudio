## Films how the character carries the pistol, seen from its right side by the game camera:
## standing, walking, jogging, sprinting, crouch walking, a jump, then aiming, hip fire and aim
## with fire. It
## presses the input actions the way a player would (it only puts the body back at the start of
## each stage), for the pull request's captures, once for each mannequin (`CARRY_MODEL=male`
## swaps the model at the start; the female is the default).
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/carry_tour.tscn --seconds 15
## --fps 20`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## A flat floor built high above the map (nothing to walk into, no camera zone), where each
## stage starts, and the camera's pitch.
const FLOOR_AT := Vector3(0.0, 300.0, 0.0)
const START := Vector3(-12.0, 300.1, 0.0)
const PITCH := 10.0
## The camera backs off the shoulder view's 1.7 m so the legs are in the frame.
const DISTANCE := 3.4

## The tour. Each stage is a dictionary: `name` (printed when it starts), `hold` the actions held,
## `seconds` how long, `yaw` the camera heading in degrees (0 looks along -Z; 0 puts the
## character's right side toward the camera when it walks to the right), `reset` to put the body
## back at the start, `tap` actions pressed for `tap_seconds` at `tap_at` seconds into the stage.
const STAGES: Array[Dictionary] = [
	{"name": "stand", "hold": [], "seconds": 0.8, "reset": true},
	{"name": "walk", "hold": [&"move_right", &"walk"], "seconds": 1.6},
	{"name": "jog", "hold": [&"move_right"], "seconds": 1.4, "reset": true},
	{"name": "sprint", "hold": [&"move_right", &"sprint"], "seconds": 1.4, "reset": true},
	{"name": "crouch", "hold": [&"move_right", &"crouch"], "seconds": 1.6, "reset": true},
	{
		"name": "jump",
		"hold": [&"move_right"],
		"seconds": 1.8,
		"reset": true,
		"tap": [&"jump"],
		"tap_at": 0.6,
		"tap_seconds": 0.25,
	},
	{"name": "aim", "hold": [&"aim"], "seconds": 1.0, "reset": true},
	{
		"name": "hip fire",
		"hold": [],
		"seconds": 1.2,
		"tap": [&"fire"],
		"tap_at": 0.2,
		"tap_seconds": 0.12,
	},
	{
		"name": "aim and fire",
		"hold": [&"aim"],
		"seconds": 1.4,
		"tap": [&"fire"],
		"tap_at": 0.5,
		"tap_seconds": 0.12
	},
	{"name": "aim walk", "hold": [&"aim", &"move_right"], "seconds": 1.2, "reset": true},
	{"name": "let go", "hold": [], "seconds": 0.8},
]

var _index := -1
var _clock := 0.0
var _held: Array[StringName] = []

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _ready() -> void:
	var animation: CharacterAnimation = _player.get_node("Animation")
	if OS.get_environment("CARRY_BONES") != "":
		var bones: Array[StringName] = []
		for bone in OS.get_environment("CARRY_BONES").split(","):
			bones.append(StringName(bone))
		animation.grip_bones = bones
	if OS.get_environment("CARRY_HELD") == "1":
		animation.carry = CharacterAnimation.Carry.HELD_POSE
	var floor_block := (load("res://world/blocks/proto_block.tscn") as PackedScene).instantiate()
	floor_block.size = Vector3(60.0, 1.0, 30.0)
	floor_block.position = FLOOR_AT - Vector3(0.0, 0.5, 0.0)
	add_child(floor_block)
	_rig.distance = DISTANCE
	_player.teleport(START, PI / 2.0)
	if OS.get_environment("CARRY_MODEL") == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		var male := load("res://assets/characters/mannequin/mannequin_male.glb") as PackedScene
		slot.add_child(male.instantiate())


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
