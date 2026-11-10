## Plays the pistol through the bullet impacts the way a player would, for a clip: it shoots a
## pushed cube from the north and walks into it, so the cube carries its marks, then shoots a
## burst at the orange block of the ragdoll ledge and waits while the marks fade out. It presses
## the input actions (`aim`, `fire`, `move_forward`) and turns the camera with the same
## `orbit()` the mouse uses, putting the crosshair on a point by looking at where the lens shows
## it. The only help is `teleport` to stage each scene.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/impacts_tour.tscn --seconds 50`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

enum Phase { AIM, FIRE, PAUSE }

## A walk step is given up on after the body has not moved for this long.
const STUCK_SECONDS := 2.5
## The share of the crosshair's distance from the point that one frame turns.
const AIM_GAIN := 0.35
## The crosshair is on the point within this many pixels.
const AIM_PIXELS := 5.0
## How long the fire button is held for each shot, and the pause after it.
const SHOT_HOLD := 0.1
const SHOT_PAUSE := 0.28

## The tour. Each step is a dictionary with a `do`:
## `teleport` puts the character at `at`, facing south (the camera cuts to it);
## `walk` to (x, z) within `near` metres, holding `hold` actions on the way;
## `aim` puts the crosshair on `at` (a point) and holds the aim button;
## `burst` fires `shots` shots at the points of `around` (one each, in turn) while aiming;
## `push` walks at the node `node` for `seconds`, turning the camera toward it, so it is pushed;
## `wait` holds `hold` actions for `seconds`;
## `set` sets the property `name` of the `Impacts` to `value`.
const TOUR: Array[Dictionary] = [
	{"do": "set", "name": "mark_size", "value": 0.2},
	{"do": "set", "name": "mark_lifetime", "value": 12.0},
	{"do": "set", "name": "mark_fade_time", "value": 8.0},
	{"do": "teleport", "at": Vector3(-6.0, 0.0, 14.5)},
	{"do": "wait", "seconds": 1.0, "hold": []},
	{"do": "aim", "at": Vector3(-6.0, 0.55, 18.5)},
	{
		"do": "burst",
		"around":
		[
			Vector3(-6.2, 0.6, 18.5),
			Vector3(-5.8, 0.35, 18.5),
			Vector3(-5.95, 0.8, 18.5),
			Vector3(-6.25, 0.3, 18.5),
		],
	},
	{"do": "wait", "seconds": 0.6, "hold": []},
	{"do": "push", "node": "Main/Level/PushCubes/PushCube1", "seconds": 1.6},
	{"do": "wait", "seconds": 1.5, "hold": []},
	{"do": "teleport", "at": Vector3(6.0, 0.0, 16.8)},
	{"do": "wait", "seconds": 1.0, "hold": []},
	{"do": "aim", "at": Vector3(6.0, 1.6, 20.5)},
	{
		"do": "burst",
		"around":
		[
			Vector3(5.3, 1.2, 20.5),
			Vector3(6.5, 1.9, 20.5),
			Vector3(7.1, 1.0, 20.5),
			Vector3(5.8, 1.6, 20.5),
			Vector3(6.7, 2.3, 20.5),
			Vector3(4.8, 2.0, 20.5),
			Vector3(6.1, 0.8, 20.5),
			Vector3(7.5, 1.5, 20.5),
		],
	},
	{"do": "wait", "seconds": 22.0, "hold": []},
]

var _index := 0
var _clock := 0.0
var _stuck_for := 0.0
var _last_spot := Vector3.ZERO
var _held: Array[StringName] = []
var _shots_done := 0
var _shot_clock := 0.0
var _phase := Phase.AIM
var _pitch_sign := 1.0
var _last_error := INF

@onready var _player: Player = $Main/Player
@onready var _rig: PlayerCamera = $Main/PlayerCamera
@onready var _impacts: Impacts = $Main/Impacts
@onready var _camera: Camera3D = $Main/Camera


func _physics_process(delta: float) -> void:
	if _index >= TOUR.size():
		_hold([])
		_finish()
		return
	var step := TOUR[_index]
	var done := false
	match step["do"]:
		"set":
			_impacts.set(step["name"], step["value"])
			done = true
		"teleport":
			_player.teleport(step["at"], 0.0)
			done = true
		"walk":
			done = _walk(step, delta)
		"aim":
			_hold([&"aim"])
			done = _aim(step["at"])
		"burst":
			done = _burst(step, delta)
		"push":
			done = _push(step, delta)
		"wait":
			_hold(step["hold"])
			_clock += delta
			done = _clock >= float(step["seconds"])
	if done:
		_index += 1
		_clock = 0.0
		_stuck_for = 0.0
		_shots_done = 0
		_shot_clock = 0.0
		_phase = Phase.AIM
		_last_error = INF


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
	_hold([&"move_forward"])
	var want := rad_to_deg(atan2(-to.x, -to.y))
	_rig.orbit(Vector2(-clampf(wrapf(want - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	return false


# Walks at a node, the camera turning toward it, for a while.
func _push(step: Dictionary, delta: float) -> bool:
	var target := get_node(step["node"]) as Node3D
	var to := Vector2(
		target.global_position.x - _player.global_position.x,
		target.global_position.z - _player.global_position.z
	)
	_hold([&"move_forward"])
	var want := rad_to_deg(atan2(-to.x, -to.y))
	_rig.orbit(Vector2(-clampf(wrapf(want - _rig.yaw, -180.0, 180.0), -6.0, 6.0), 0.0))
	_clock += delta
	return _clock >= float(step["seconds"])


# Turns the camera until the crosshair is over `at`; true when it is (within a few pixels).
func _aim(at: Vector3) -> bool:
	var centre := get_viewport().get_visible_rect().size / 2.0
	var error := _camera.unproject_position(at) - centre
	var focal := centre.y / tan(deg_to_rad(_camera.fov) / 2.0)
	if error.length() > _last_error + 0.5:
		_pitch_sign = -_pitch_sign
	_last_error = error.length()
	var turn := Vector2(rad_to_deg(atan(error.x / focal)), rad_to_deg(atan(error.y / focal)))
	_rig.orbit(Vector2(turn.x, turn.y * _pitch_sign) * AIM_GAIN)
	return error.length() < AIM_PIXELS


# One shot at each point of `around`: aim at it, hold the fire button for a moment, pause.
func _burst(step: Dictionary, delta: float) -> bool:
	var points: Array = step["around"]
	if _shots_done >= points.size():
		_hold([&"aim"])
		return true
	match _phase:
		Phase.AIM:
			_hold([&"aim"])
			if _aim(points[_shots_done]):
				_phase = Phase.FIRE
				_shot_clock = 0.0
		Phase.FIRE:
			_hold([&"aim", &"fire"])
			_shot_clock += delta
			if _shot_clock >= SHOT_HOLD:
				_phase = Phase.PAUSE
				_shot_clock = 0.0
		Phase.PAUSE:
			_hold([&"aim"])
			_shot_clock += delta
			if _shot_clock >= SHOT_PAUSE:
				_phase = Phase.AIM
				_shots_done += 1
	return false


# Holds exactly these actions down and lets go of the rest.
func _hold(actions: Array) -> void:
	for action in _held:
		if not actions.has(action):
			Input.action_release(action)
	_held.clear()
	for action: StringName in actions:
		Input.action_press(action)
		_held.append(action)
