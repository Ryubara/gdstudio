## Plays the character along a wall of the sample map and asks the camera the question of the
## "first person" fault: aim, fire and sprint next to the wall at camera yaws all round, and
## let go. It presses the input actions (never moves the body itself) and turns the camera with
## the same `orbit()` the mouse, the stick and the touch layer use. It also prints, every
## physics frame, how far the lens is from the head (the line starts with `LENS`), so a run can
## be checked for a lens that comes closer than the wall forces it.
##
## Record it with Movie Maker through the kit (the frames and the sound land in the scratch folder):
## `gds capture frames --project game --seconds 40 --name walls`
## with `--scene res://tools/capture/camera_walls_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Camera turn speed toward a heading, in degrees a second.
const TURN_SPEED := 200.0
## The spot by the south wall of the sample map (its inner face is at z = 24), clear of blocks.
const SPOT := Vector3(4.0, 0.0, 22.2)

## The tour. Each step is a dictionary with a `do`:
## `look` turns the camera to `yaw` (degrees, 0 looks along -Z) and `pitch`;
## `press` holds `actions` for `seconds`; `walk` holds `move_forward` and `actions` for
## `seconds`; `place` puts the character at the wall.
const TOUR: Array[Dictionary] = [
	{"do": "place"},
	{"do": "look", "yaw": 0.0, "pitch": 12.0},
	{"do": "press", "actions": [], "seconds": 0.8},
	{"do": "look", "yaw": -60.0, "pitch": 12.0},
	{"do": "press", "actions": [&"aim"], "seconds": 1.0},
	{"do": "look", "yaw": -90.0, "pitch": 12.0},
	{"do": "press", "actions": [&"aim"], "seconds": 1.0},
	{"do": "look", "yaw": -120.0, "pitch": 12.0},
	{"do": "press", "actions": [&"aim"], "seconds": 1.0},
	{"do": "press", "actions": [], "seconds": 1.2},
	{"do": "look", "yaw": -75.0, "pitch": 12.0},
	{"do": "press", "actions": [&"fire"], "seconds": 0.5},
	{"do": "press", "actions": [], "seconds": 1.2},
	{"do": "look", "yaw": -110.0, "pitch": 12.0},
	{"do": "press", "actions": [&"fire"], "seconds": 0.5},
	{"do": "press", "actions": [], "seconds": 1.2},
	{"do": "look", "yaw": 100.0, "pitch": 12.0},
	{"do": "press", "actions": [&"aim"], "seconds": 1.0},
	{"do": "press", "actions": [], "seconds": 1.0},
	{"do": "look", "yaw": 180.0, "pitch": 12.0},
	{"do": "press", "actions": [&"aim", &"fire"], "seconds": 0.8},
	{"do": "press", "actions": [], "seconds": 1.0},
	{"do": "look", "yaw": 90.0, "pitch": 12.0},
	{"do": "walk", "actions": [&"sprint"], "seconds": 1.6},
	{"do": "look", "yaw": -90.0, "pitch": 12.0},
	{"do": "walk", "actions": [&"sprint"], "seconds": 1.6},
	{"do": "press", "actions": [], "seconds": 0.8},
]

var _index := 0
var _clock := 0.0
var _held: Array[StringName] = []
var _frame := 0

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera
@onready var _camera: Camera3D = $Main/PlayerRig/Camera
@onready var _head: Node3D = $Main/PlayerRig/Player/CameraTarget


func _physics_process(delta: float) -> void:
	_frame += 1
	if _frame > 8:
		print(
			"LENS ",
			_frame,
			" ",
			snappedf(_camera.global_position.distance_to(_head.global_position), 0.01),
			" yaw ",
			snappedf(_rig.yaw, 1.0),
			" aim ",
			Input.is_action_pressed(&"aim"),
			" fire ",
			Input.is_action_pressed(&"fire")
		)
	if _index >= TOUR.size():
		_hold([])
		_finish()
		return
	var step := TOUR[_index]
	var done := false
	match step["do"]:
		"place":
			_player.teleport(SPOT)
			done = true
		"look":
			_hold([])
			done = _turn(step["yaw"], step["pitch"], delta)
		"press":
			_hold(step["actions"])
			_clock += delta
			done = _clock >= float(step["seconds"])
		"walk":
			var actions: Array = [&"move_forward"]
			actions.append_array(step["actions"])
			_hold(actions)
			_clock += delta
			done = _clock >= float(step["seconds"])
	if done:
		_index += 1
		_clock = 0.0


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame_count in 8:
		await get_tree().process_frame
	get_tree().quit()


# Turns the camera toward a heading and a pitch; true when it is there.
func _turn(yaw: float, pitch: float, delta: float) -> bool:
	var by_yaw := clampf(
		wrapf(yaw - _rig.yaw, -180.0, 180.0), -TURN_SPEED * delta, TURN_SPEED * delta
	)
	var by_pitch := clampf(pitch - _rig.pitch, -TURN_SPEED * delta, TURN_SPEED * delta)
	_rig.orbit(Vector2(-by_yaw, by_pitch))
	return absf(wrapf(yaw - _rig.yaw, -180.0, 180.0)) < 1.0 and absf(pitch - _rig.pitch) < 1.0


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)
