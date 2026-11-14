class_name CharacterLanding
extends RefCounted
## A `Character`'s touch-down, from the fall speed it lands with (`_fall_speed`): a landing from
## `CharacterTuning.land_clip_speed` is in `LAND` for `land_time`; a hard one, from
## `hard_land_speed`, for `hard_land_time` (the hard landing clip's `control` frame), and it holds
## the body all that time as an action does (gdstudio #1535): the push is ignored, the body keeps
## `hard_land_keep` of its ground speed and slows by `deceleration`, and it neither turns, jumps nor
## aims. All of it is step state already there (`_land_timer`, `_action_lock`), so a predicting
## client and the server hold a body the same. Its functions are static and keep nothing, like the
## body's other modules.


## The landing of `body` on the tick it touched down.
static func touch_down(body: Character) -> void:
	var tuning := body.tuning
	var fall := body._fall_speed
	body._land_timer = tuning.land_time_after(fall, body._land_timer)
	var hold := tuning.land_hold_after(fall)
	if hold <= 0.0:
		return
	body._action_lock = maxf(body._action_lock, hold)
	body.velocity.x *= tuning.hard_land_keep
	body.velocity.z *= tuning.hard_land_keep
