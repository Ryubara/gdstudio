## Plays prone the way a player would, for a clip of every way a lying body moves: it goes down,
## lies still, crawls ahead, turns round to crawl back the way it came, turns to the left and to
## the right, then holds aim (the body faces the camera) and crawls backwards and to each side,
## turns with the camera while it lies, and gets up. It presses the input actions (never moves
## the body itself) and turns the camera with the same `orbit()` the mouse and the stick use.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/prone_moves_tour.tscn
## --seconds 30`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Camera turn speed toward a heading, in degrees a second.
const TURN_SPEED := 60.0
## Where the tour starts: open ground on the east side of the map.
const START := Vector3(5.5, 0.0, 3.5)

## The tour: `wait` holds `actions` for `seconds`; `tap` presses one action for a moment; `look`
## turns the camera (holding `actions` while it turns).
const TOUR: Array[Dictionary] = [
	{"do": "look", "yaw": 0.0, "pitch": 8.0, "actions": []},
	{"do": "wait", "actions": [], "seconds": 0.6},
	{"do": "tap", "action": &"prone"},
	{"do": "wait", "actions": [], "seconds": 1.6},
	{"do": "wait", "actions": [&"move_forward"], "seconds": 2.5},
	{"do": "wait", "actions": [], "seconds": 0.6},
	{"do": "wait", "actions": [&"move_back"], "seconds": 3.0},
	{"do": "wait", "actions": [&"move_left"], "seconds": 2.0},
	{"do": "wait", "actions": [&"move_right"], "seconds": 2.5},
	{"do": "wait", "actions": [], "seconds": 0.4},
	{"do": "wait", "actions": [&"aim"], "seconds": 1.0},
	{"do": "wait", "actions": [&"aim", &"move_back"], "seconds": 2.0},
	{"do": "wait", "actions": [&"aim", &"move_left"], "seconds": 1.6},
	{"do": "wait", "actions": [&"aim", &"move_right"], "seconds": 1.6},
	{"do": "wait", "actions": [&"aim", &"move_forward"], "seconds": 1.6},
	{"do": "wait", "actions": [], "seconds": 0.4},
	{"do": "look", "yaw": 60.0, "pitch": 8.0, "actions": [&"aim"]},
	{"do": "wait", "actions": [], "seconds": 0.6},
	{"do": "tap", "action": &"prone"},
	{"do": "wait", "actions": [], "seconds": 1.6},
]

var _index := 0
var _clock := 0.0
var _held: Array[StringName] = []
var _started := false

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _physics_process(delta: float) -> void:
	if not _started:
		_started = true
		_player.teleport(START, PI)
		return
	if _index >= TOUR.size():
		_hold([])
		_finish()
		return
	var step := TOUR[_index]
	var done := false
	_clock += delta
	match step["do"]:
		"wait":
			_hold(step["actions"])
			done = _clock >= float(step["seconds"])
		"tap":
			_hold([step["action"]])
			done = _clock >= 0.1
		"look":
			_hold(step["actions"])
			done = _turn(step["yaw"], step["pitch"], delta)
	if done:
		_index += 1
		_clock = 0.0


# Stops the sounds and gives the mixer a few frames to let go of them before the capture quits.
func _finish() -> void:
	set_physics_process(false)
	AudioSettings.stop_players(get_tree().root)
	for _frame in 8:
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
