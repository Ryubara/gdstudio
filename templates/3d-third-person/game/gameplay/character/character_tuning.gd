@tool
class_name CharacterTuning
extends Resource
## Every number a developer tunes on the character, in one resource: the player scene holds one
## (`player_tuning.tres`) and the inspector shows it grouped, with ranges and units. Make a copy
## of the file for a second character feel (a heavier one, a floaty one) and point the player at
## it.
##
## A number is read where it is used, every frame, so changing it in the inspector or the remote
## inspector works while the game runs. The few the body copies once (the capsule, the slope and
## the floor snap) say `changed`, and `Character` applies them again; so do the four speeds the
## animation's blend spaces are laid out by (`CharacterAnimation`).

@export_group("Ground")
## Speed at a walk (the move stick pushed a little, or the walk key held).
@export_range(0.5, 6.0, 0.05, "suffix:m/s") var walk_speed := 1.7:
	set(value):
		walk_speed = value
		emit_changed()
## Speed at a run: the default speed with the stick or the keys held down.
@export_range(1.0, 12.0, 0.05, "suffix:m/s") var run_speed := 4.0:
	set(value):
		run_speed = value
		emit_changed()
## Speed while the sprint button is held.
@export_range(1.0, 16.0, 0.05, "suffix:m/s") var sprint_speed := 6.5:
	set(value):
		sprint_speed = value
		emit_changed()
## How fast the character gets up to speed.
@export_range(1.0, 80.0, 0.5, "suffix:m/s²") var acceleration := 28.0
## How fast the character stops when the stick is let go.
@export_range(1.0, 80.0, 0.5, "suffix:m/s²") var deceleration := 36.0
## How fast the body turns to face where it goes.
@export_range(1.0, 40.0, 0.5, "suffix:rad/s") var turn_speed := 12.0
## A move stick pushed less than this share of the way walks instead of running.
@export_range(0.0, 1.0, 0.01) var walk_below_push := 0.45
## The least share of the walking (or crouching) speed a light push of the stick gives, so a
## nudge still moves the character at a visible pace.
@export_range(0.0, 1.0, 0.01) var least_walk_share := 0.5
## Ground speed above `walk_speed` by more than this counts as a run (the run clip plays).
@export_range(0.0, 3.0, 0.01, "suffix:m/s") var run_above_walk := 0.35
@export_subgroup("Stops")
## How fast a body on its feet slows, the stick let go, while it moves no faster than
## `walk_speed`: the walk's stop. Each gait's stop slows the body over the ground its stop clip's
## feet cover (`gds/Walk_Stop`, `gds/Jog_Stop`, `gds/Sprint_Stop` in `locomotion.json`), so the
## clip plays to its end as the body comes to rest; a faster stop leaves the clip's feet sliding.
## The defaults cover 0.48 m from the walk, 1.96 m from the jog and 4.82 m from the sprint.
@export_range(0.5, 80.0, 0.01, "suffix:m/s²") var walk_stop_deceleration := 2.84
## The same between `walk_speed` and `run_speed`: the jog's stop, after which the walk's slows it.
@export_range(0.5, 80.0, 0.01, "suffix:m/s²") var run_stop_deceleration := 4.38
## The same above `run_speed`: the sprint's stop, after which the jog's and the walk's slow it.
@export_range(0.5, 80.0, 0.01, "suffix:m/s²") var sprint_stop_deceleration := 4.57

@export_group("Jump")
## How high a standing jump rises when the button is held.
@export_range(0.2, 4.0, 0.05, "suffix:m") var jump_height := 1.25
## Seconds from leaving the ground to the top of the jump; with the height it sets gravity.
@export_range(0.15, 1.0, 0.01, "suffix:s") var jump_rise_time := 0.4
## Gravity is this much stronger on the way down, so a jump feels weighty.
@export_range(1.0, 3.0, 0.05) var fall_gravity_scale := 1.35
## The fastest the character falls.
@export_range(5.0, 80.0, 0.5, "suffix:m/s") var terminal_speed := 40.0
## A jump let go early rises only this share of its height.
@export_range(0.1, 1.0, 0.05) var short_jump_scale := 0.5
## A jump is still allowed this long after walking off an edge.
@export_range(0.0, 0.5, 0.01, "suffix:s") var coyote_time := 0.12
## A jump pressed this long before landing happens on landing.
@export_range(0.0, 0.5, 0.01, "suffix:s") var jump_buffer_time := 0.14

@export_group("Air")
## How much of the ground steering works in the air: 0 keeps the take-off velocity, 1 steers as
## on the ground.
@export_range(0.0, 1.0, 0.01) var air_control := 0.45

@export_group("Slopes and steps")
## The steepest slope that counts as floor.
@export_range(10.0, 80.0, 1.0, "suffix:deg") var max_slope := 48.0:
	set(value):
		max_slope = value
		emit_changed()
## The highest edge the character steps up without jumping.
@export_range(0.0, 0.8, 0.01, "suffix:m") var step_height := 0.32
## How far the character is held to the ground going down a slope or a stair.
@export_range(0.0, 1.0, 0.01, "suffix:m") var snap_length := 0.35:
	set(value):
		snap_length = value
		emit_changed()
## How far past the capsule's side the step check looks for an edge to climb.
@export_range(0.0, 0.3, 0.005, "suffix:m") var step_probe_margin := 0.06

@export_group("Crouch")
## The capsule's height while crouched (the character fits under a ceiling this low).
@export_range(0.7, 1.6, 0.01, "suffix:m") var crouch_height := 1.1:
	set(value):
		crouch_height = value
		emit_changed()
## Speed at a crouch walk with the stick fully pushed.
@export_range(0.3, 4.0, 0.05, "suffix:m/s") var crouch_speed := 1.5:
	set(value):
		crouch_speed = value
		emit_changed()
## Seconds to go from standing to crouched and back.
@export_range(0.0, 1.0, 0.01, "suffix:s") var crouch_time := 0.2
## On: the crouch button switches crouching on and off. Off: the character is crouched only while
## the button is held.
@export var crouch_toggle := false
## Height of the camera's target (the point the camera follows) when standing.
@export_range(0.5, 2.5, 0.01, "suffix:m") var camera_height := 1.55:
	set(value):
		camera_height = value
		emit_changed()
## Height of the camera's target when crouched.
@export_range(0.3, 2.0, 0.01, "suffix:m") var crouch_camera_height := 0.9:
	set(value):
		crouch_camera_height = value
		emit_changed()
## Height of the camera's target above the hips of a dead body lying in its ragdoll.
@export_range(0.0, 1.5, 0.01, "suffix:m") var dead_camera_rise := 0.25

@export_group("Aim")
## The share of the walking speed the character keeps while aiming (1 is the full speed).
@export_range(0.1, 1.0, 0.05) var aim_move_scale := 0.6
## While aiming the speed is at most this many walking speeds, before `aim_move_scale`.
@export_range(0.5, 4.0, 0.05) var aim_walk_cap := 1.5
## How fast the body turns to the camera's heading while aiming.
@export_range(1.0, 60.0, 0.5, "suffix:rad/s") var aim_turn_speed := 18.0
## Seconds the arm takes to come up to aim and to go down again.
@export_range(0.0, 1.0, 0.01, "suffix:s") var aim_pose_time := 0.15
## A press of the fire button is kept this long while the arm comes up, then it shoots; the arm
## keeps coming up for it after the button is let go. Shorter than half of `aim_pose_time` and a
## quick tap from the hip shoots nothing.
@export_range(0.0, 1.0, 0.01, "suffix:s") var fire_buffer_time := 0.3
## How far the arm must be up (0 down, 1 aiming) before a shot leaves.
@export_range(0.0, 1.0, 0.01) var shot_aim_amount := 0.5
## How far the aim layer turns the upper body to put the weapon on the aim while standing
## (`AimLayer`); the body itself turns to the view while aiming, so this covers the turn's lag.
@export var aim_limits := AimLimits.new()
## The same while crouched.
@export var crouch_aim_limits := AimLimits.new()

@export_group("Pushing")
## The share of its own speed the character gives a light prop it walks into: 1 moves the prop
## as fast as the character walks, 0 does not move it.
@export_range(0.0, 1.0, 0.01) var push_strength := 0.85
## A prop this heavy gets half of that share; lighter ones get more, heavier ones less.
@export_range(1.0, 500.0, 1.0, "suffix:kg") var push_mass := 40.0
## The share given to a prop is multiplied by this before it is capped at 1, so a prop at
## `push_mass` keeps up with a walk.
@export_range(0.5, 4.0, 0.05) var push_boost := 1.5
## The least the share of a heavy prop falls to, before the boost.
@export_range(0.0, 1.0, 0.01) var push_least_share := 0.15
## How much faster than a prop's `push_speed` the character walks while it pushes the prop: the
## prop is given the push speed, and the character stays against it and pushes it every tick
## (equal speeds would let a gap open and the friction slow the prop between pushes).
@export_range(1.0, 2.0, 0.01) var push_contact := 1.15
## Seconds a slow push goes on counting after the last touch: pushing a heavy prop is a series of
## touches with a small gap between them, and the push clip and the speed limit should not flicker.
@export_range(0.0, 1.0, 0.01, "suffix:s") var push_hold := 0.25

@export_group("Actions")
## The character cannot move for this long while it uses something.
@export_range(0.0, 3.0, 0.05, "suffix:s") var interact_time := 0.7
## How far in front the character reaches to use something.
@export_range(0.3, 4.0, 0.05, "suffix:m") var interact_reach := 1.6
## The character cannot move for this long after a hit.
@export_range(0.0, 2.0, 0.05, "suffix:s") var hit_stun_time := 0.45
## How fast a hit throws the character back.
@export_range(0.0, 20.0, 0.1, "suffix:m/s") var knockback_speed := 5.0
## A landing harder than this plays the landing clip and says `landed` with the speed.
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var land_clip_speed := 4.5
## How long the landing holds the body in its landing state.
@export_range(0.0, 2.0, 0.05, "suffix:s") var land_time := 0.3
## A body slower than this on the ground counts as standing still.
@export_range(0.0, 1.0, 0.01, "suffix:m/s") var stand_speed := 0.15

@export_group("Body")
## The capsule's radius.
@export_range(0.1, 1.0, 0.01, "suffix:m") var radius := 0.34:
	set(value):
		radius = value
		emit_changed()
## The capsule's height.
@export_range(0.8, 3.0, 0.01, "suffix:m") var height := 1.8:
	set(value):
		height = value
		emit_changed()

@export_group("Safety")
## Below this height (y) the character went out of the map and starts again at its spawn point.
## Set it under the lowest floor.
@export_range(-1000.0, 0.0, 1.0, "or_greater", "suffix:m") var fall_limit := -25.0


## Gravity pulling up to the jump's top in `jump_rise_time`.
func gravity() -> float:
	return 2.0 * jump_height / (jump_rise_time * jump_rise_time)


## Speed at the moment of take-off for the jump above.
func jump_speed() -> float:
	return 2.0 * jump_height / jump_rise_time


## How fast a body on its feet with the stick let go slows at ground speed `speed`: the stop
## deceleration of the gait whose speed band it is in. A function of the speed alone, so a
## predicting client and the server stop a body at the same place.
func stop_deceleration(speed: float) -> float:
	if speed > run_speed:
		return sprint_stop_deceleration
	if speed > walk_speed:
		return run_stop_deceleration
	return walk_stop_deceleration


## The ground a body on its feet covers from ground speed `speed` to rest with the stick let go,
## by the stop decelerations (m): what an AI's navigator leaves itself to stop on its point.
func stop_distance(speed: float) -> float:
	var bands: Array[Array] = [
		[run_speed, sprint_stop_deceleration],
		[walk_speed, run_stop_deceleration],
		[0.0, walk_stop_deceleration],
	]
	var distance := 0.0
	var top := maxf(speed, 0.0)
	for band in bands:
		var bottom: float = minf(band[0], top)
		distance += (top * top - bottom * bottom) / (2.0 * maxf(band[1], 0.01))
		top = bottom
	return distance
