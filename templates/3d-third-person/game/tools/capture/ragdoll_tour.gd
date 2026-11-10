## Plays the character through the ragdoll the way a player would, for a clip: it runs, dies in
## mid-stride with the `ragdoll` key (Y), lies while the camera orbits the body, gets up with the
## key again, then sprints up the ledge of the map and dies in the air as it leaves the edge. It
## presses the input actions (never moves the body itself) and turns the camera with the same
## `orbit()` the mouse, the stick and the touch layer use.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder), once for
## each mannequin (`RAGDOLL_MODEL=male` swaps the model at the start; the female is the default):
## `gds capture frames --project game --scene res://tools/capture/ragdoll_tour.tscn --seconds 40`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Camera turn speed toward a heading, in degrees a second.
const TURN_SPEED := 220.0
## A walk step is given up on after the body has not moved for this long.
const STUCK_SECONDS := 2.5

## The tour. Each step is a dictionary with a `do`:
## `walk` to (x, z) within `near` metres, holding `hold` actions on the way, or at once when the
## body is past `after_z` (south), `after_x` (east) or `before_x` (west);
## `look` turns the camera to `yaw` (degrees, 0 looks along -Z) and `pitch`;
## `press` holds `actions` for `seconds`.
const TOUR: Array[Dictionary] = [
	{"do": "look", "yaw": 180.0, "pitch": 14.0},
	{"do": "walk", "x": 2.0, "z": 15.0, "near": 0.8, "hold": [&"sprint"]},
	{"do": "walk", "x": -8.0, "z": 15.0, "near": 0.8, "hold": [&"sprint"], "before_x": -3.0},
	{"do": "press", "actions": [&"move_forward", &"sprint", &"ragdoll"], "seconds": 0.1},
	{"do": "press", "actions": [], "seconds": 2.0},
	{"do": "look", "yaw": 180.0, "pitch": 24.0},
	{"do": "look", "yaw": 270.0, "pitch": 24.0},
	{"do": "look", "yaw": 360.0, "pitch": 24.0},
	{"do": "look", "yaw": 450.0, "pitch": 14.0},
	{"do": "press", "actions": [&"ragdoll"], "seconds": 0.1},
	{"do": "press", "actions": [], "seconds": 1.2},
	{"do": "walk", "x": -8.0, "z": 15.0, "near": 0.8, "hold": [&"sprint"]},
	{"do": "walk", "x": -8.0, "z": 22.0, "near": 0.8, "hold": [&"sprint"]},
	{"do": "look", "yaw": -90.0, "pitch": 14.0},
	{"do": "walk", "x": 9.5, "z": 22.0, "near": 0.5, "hold": [&"sprint"], "after_x": 8.4},
	{"do": "press", "actions": [&"move_forward", &"sprint", &"ragdoll"], "seconds": 0.1},
	{"do": "press", "actions": [], "seconds": 3.0},
	{"do": "look", "yaw": 180.0, "pitch": 24.0},
	{"do": "press", "actions": [], "seconds": 1.0},
]

var _index := 0
var _clock := 0.0
var _stuck_for := 0.0
var _last_spot := Vector3.ZERO
var _held: Array[StringName] = []

@onready var _player: Player = $Main/Player
@onready var _rig: PlayerCamera = $Main/PlayerCamera


func _ready() -> void:
	if OS.get_environment("RAGDOLL_MODEL") == "male":
		var slot := _player.model
		var old := slot.rig()
		slot.remove_child(old)
		old.free()
		var male := load("res://assets/characters/mannequin/mannequin_male.glb") as PackedScene
		slot.add_child(male.instantiate())


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
	if (
		spot.z > step.get("after_z", INF)
		or spot.x > step.get("after_x", INF)
		or spot.x < step.get("before_x", -INF)
	):
		return true
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
