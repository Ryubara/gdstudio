## Plays the character through the crouch course, the range and the cubes the way a player would,
## for a clip: it presses the input actions (never moves the body itself) and turns the camera with
## the same `orbit()` the mouse, the stick and the touch layer use.
##
## Record it with Movie Maker through the kit (the frames and the sound land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/action_tour.tscn --seconds 60`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Camera turn speed toward a heading, in degrees a second.
const TURN_SPEED := 220.0
## A walk step is given up on after the body has not moved for this long.
const STUCK_SECONDS := 2.5

## The tour. Each step is a dictionary with a `do`:
## `walk` to (x, z) within `near` metres, holding `hold` actions on the way;
## `look` turns the camera to `yaw` (degrees, 0 looks along -Z) and `pitch`;
## `press` holds `actions` for `seconds`; `tap` presses one action for a moment.
const TOUR: Array[Dictionary] = [
	{"do": "walk", "x": 0.0, "z": -5.0, "near": 0.6},
	{"do": "look", "yaw": 20.0, "pitch": 4.0},
	{"do": "press", "actions": [&"aim"], "seconds": 0.9},
	{"do": "press", "actions": [&"aim", &"fire"], "seconds": 0.12},
	{"do": "press", "actions": [&"aim"], "seconds": 0.6},
	{"do": "look", "yaw": 31.0, "pitch": 4.0},
	{"do": "press", "actions": [&"aim", &"fire"], "seconds": 0.12},
	{"do": "press", "actions": [&"aim"], "seconds": 0.6},
	{"do": "look", "yaw": -20.0, "pitch": 4.0},
	{"do": "press", "actions": [&"aim", &"fire"], "seconds": 0.12},
	{"do": "press", "actions": [&"aim"], "seconds": 0.6},
	{"do": "look", "yaw": -31.0, "pitch": 4.0},
	{"do": "press", "actions": [&"aim", &"fire"], "seconds": 0.12},
	{"do": "press", "actions": [&"aim"], "seconds": 1.4},
	{"do": "walk", "x": 0.0, "z": -14.3, "near": 0.5, "hold": [&"sprint"]},
	{"do": "press", "actions": [&"crouch"], "seconds": 0.5},
	{"do": "walk", "x": 0.0, "z": -18.6, "near": 0.4, "hold": [&"crouch"]},
	{"do": "walk", "x": 0.0, "z": -21.5, "near": 0.4, "hold": [&"crouch"]},
	{"do": "look", "yaw": 90.0, "pitch": 14.0, "hold": [&"crouch"]},
	{"do": "walk", "x": -7.5, "z": -21.5, "near": 0.5, "hold": [&"crouch"]},
	{"do": "press", "actions": [], "seconds": 0.5},
	{"do": "look", "yaw": -90.0, "pitch": 14.0},
	{"do": "walk", "x": 0.0, "z": -21.5, "near": 0.4},
	{"do": "walk", "x": 3.5, "z": -21.5, "near": 0.4, "hold": [&"crouch"]},
	{"do": "press", "actions": [], "seconds": 1.2},
	{"do": "look", "yaw": 180.0, "pitch": 14.0},
	{"do": "walk", "x": 3.5, "z": -18.2, "near": 0.5},
	{"do": "walk", "x": 0.0, "z": -18.2, "near": 0.5},
	{"do": "look", "yaw": 0.0, "pitch": 14.0},
	{"do": "walk", "x": 0.0, "z": -13.5, "near": 0.5, "hold": [&"crouch"]},
	{"do": "walk", "x": 5.5, "z": -9.0, "near": 0.8, "hold": [&"sprint"]},
	{"do": "walk", "x": 5.5, "z": 14.0, "near": 1.0, "hold": [&"sprint"]},
	{"do": "walk", "x": -3.5, "z": 22.0, "near": 0.7},
	{"do": "look", "yaw": 0.0, "pitch": 14.0},
	{"do": "walk", "x": -3.5, "z": 14.0, "near": 0.5},
]

var _index := 0
var _clock := 0.0
var _stuck_for := 0.0
var _last_spot := Vector3.ZERO
var _held: Array[StringName] = []

@onready var _player: Player = $Main/Player
@onready var _rig: PlayerCamera = $Main/PlayerCamera


func _physics_process(delta: float) -> void:
	if _index >= TOUR.size():
		_release_all()
		_finish()
		return
	var step := TOUR[_index]
	var done := false
	match step["do"]:
		"walk":
			done = _walk(step, delta)
		"look":
			_hold(step.get("hold", []))
			done = _look(step, delta)
		"press":
			_hold(step["actions"])
			_clock += delta
			done = _clock >= float(step["seconds"])
	if done:
		_index += 1
		_clock = 0.0
		_stuck_for = 0.0


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits
# (a voice still playing at exit is reported as a leak).
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
		await get_tree().process_frame
	get_tree().quit()


func _walk(step: Dictionary, delta: float) -> bool:
	var spot := _player.global_position
	var to := Vector2(step["x"] - spot.x, step["z"] - spot.z)
	_stuck_for = _stuck_for + delta if spot.distance_to(_last_spot) < 0.01 else 0.0
	_last_spot = spot
	if to.length() < step["near"] or _stuck_for > STUCK_SECONDS:
		return true
	var actions: Array[StringName] = [&"move_forward"]
	actions.append_array(step.get("hold", []))
	_hold(actions)
	_turn(rad_to_deg(atan2(-to.x, -to.y)), _rig.pitch, delta)
	return false


func _look(step: Dictionary, delta: float) -> bool:
	return _turn(step["yaw"], step["pitch"], delta)


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


func _release_all() -> void:
	_hold([])
