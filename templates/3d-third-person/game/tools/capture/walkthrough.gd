## Plays the character through the sample map the way a player would, for a clip: it presses the
## input actions (never moves the body itself) and turns the camera toward each waypoint with the
## same `orbit()` the mouse, the stick and the touch layer use.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --scene res://tools/capture/walkthrough.tscn --seconds 40`
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends Node

## Camera turn speed toward the next waypoint, in degrees a second.
const TURN_SPEED := 200.0
## Seconds to hold the jump button for a jump.
const JUMP_HOLD := 0.35
## A waypoint is given up on after the body has not moved for this long.
const STUCK_SECONDS := 2.0
## The route: x, z, how near counts as arrived, and the distance at which to jump (0 never jumps).
const ROUTE: Array[Array] = [
	[-4.0, 3.0, 1.0, 0.0],
	[-4.0, 8.0, 1.0, 0.0],
	[-7.0, 8.3, 0.6, 0.0],
	[-7.0, 13.0, 1.0, 0.0],
	[-21.0, 14.2, 1.0, 0.0],
	[-21.0, 17.0, 0.5, 1.6],
	[-18.0, 17.0, 0.5, 2.0],
	[-15.0, 17.0, 0.5, 2.0],
	[-12.0, 17.0, 0.5, 2.0],
	[-10.0, 21.0, 1.0, 0.0],
	[3.0, 12.0, 1.5, 0.0],
	[10.0, 10.0, 1.0, 0.0],
	[10.0, 1.0, 1.0, 0.0],
	[13.0, -3.0, 1.0, 0.0],
	[13.0, -14.0, 1.0, 0.0],
]

var _index := 0
var _jump_left := 0.0
var _done := false
var _stuck_for := 0.0
var _last_spot := Vector3.ZERO

@onready var _player: Player = $Main/PlayerRig/Player
@onready var _rig: PlayerCamera = $Main/PlayerRig/PlayerCamera


func _physics_process(delta: float) -> void:
	if _done or _index >= ROUTE.size():
		_stop()
		return
	var step := ROUTE[_index]
	var spot := _player.global_position
	var to := Vector2(step[0] - spot.x, step[1] - spot.z)
	_stuck_for = _stuck_for + delta if spot.distance_to(_last_spot) < 0.02 else 0.0
	_last_spot = spot
	if to.length() < step[2] or _stuck_for > STUCK_SECONDS:
		_index += 1
		_stuck_for = 0.0
		return
	_turn_toward(to, delta)
	Input.action_press(&"move_forward", 1.0)
	_jump_if_due(step, to, delta)


func _turn_toward(to: Vector2, delta: float) -> void:
	var wanted := rad_to_deg(atan2(-to.x, -to.y))
	var diff := wrapf(wanted - _rig.yaw, -180.0, 180.0)
	var turn := clampf(diff, -TURN_SPEED * delta, TURN_SPEED * delta)
	_rig.orbit(Vector2(-turn, 0.0))


func _jump_if_due(step: Array, to: Vector2, delta: float) -> void:
	_jump_left = maxf(_jump_left - delta, 0.0)
	if _jump_left > 0.0:
		return
	Input.action_release(&"jump")
	if step[3] > 0.0 and to.length() < step[3] and _player.is_on_floor():
		Input.action_press(&"jump")
		_jump_left = JUMP_HOLD


func _stop() -> void:
	_done = true
	for action in [&"move_forward", &"jump"]:
		Input.action_release(action)
	get_tree().quit()
