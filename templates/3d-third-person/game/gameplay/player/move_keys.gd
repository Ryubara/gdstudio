class_name MoveKeys
extends RefCounted
## The move stick from the four move actions, as `Input.get_vector` makes it, but for two opposing
## actions held at once (W and S, A and D): the one pressed last wins, so holding W and then S as
## well runs back, a reversal, and letting go of S runs on to W (gdstudio #1563). With
## `get_vector` the two cancelled out: no move at all, so the body played its stop while both keys
## were held and cut it when one went up. Two pressed on the same tick still cancel (nothing says
## which came last). A pad's stick never holds both ends of an axis, so it reads as before.

const ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_forward", &"move_back"]

# The tick each action last went down on (0 while it is up), and the tick count.
var _pressed_at: Array[int] = [0, 0, 0, 0]
var _tick := 0


## The stick for this tick (x right, y back, as `Input.get_vector`); called once a tick.
func read() -> Vector2:
	_tick += 1
	var strengths: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var deadzone := 0.0
	for index in ACTIONS.size():
		var strength := Input.get_action_raw_strength(ACTIONS[index])
		strengths[index] = strength
		deadzone += InputMap.action_get_deadzone(ACTIONS[index])
		if strength <= 0.0:
			_pressed_at[index] = 0
		elif _pressed_at[index] == 0:
			_pressed_at[index] = _tick
	_keep_last(strengths, 0, 1)
	_keep_last(strengths, 2, 3)
	# `Input.get_vector` from here on, with its default deadzone (the four actions' mean).
	var stick := Vector2(strengths[1] - strengths[0], strengths[3] - strengths[2])
	deadzone /= ACTIONS.size()
	var length := stick.length()
	if length <= deadzone:
		return Vector2.ZERO
	if length > 1.0:
		return stick / length
	return stick * (inverse_lerp(deadzone, 1.0, length) / length)


## Forgets which keys are down (the input was turned off).
func clear() -> void:
	_pressed_at.fill(0)


# Of the two opposing actions `a` and `b`, both held, keeps the one pressed later.
func _keep_last(strengths: Array[float], a: int, b: int) -> void:
	if strengths[a] <= 0.0 or strengths[b] <= 0.0 or _pressed_at[a] == _pressed_at[b]:
		return
	if _pressed_at[a] > _pressed_at[b]:
		strengths[b] = 0.0
	else:
		strengths[a] = 0.0
