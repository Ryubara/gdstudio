class_name PlayerTuning
extends Resource
## Every number a developer tunes on the character, in one resource: the player scene holds one
## (`player_tuning.tres`) and the inspector shows it grouped, with ranges and units. Make a copy
## of the file for a second character feel (a heavier one, a floaty one) and point the player at
## it.

@export_group("Ground")
## Speed at a walk (the move stick pushed a little, or the walk key held).
@export_range(0.5, 6.0, 0.05, "suffix:m/s") var walk_speed := 1.7
## Speed at a run: the default speed with the stick or the keys held down.
@export_range(1.0, 12.0, 0.05, "suffix:m/s") var run_speed := 4.0
## Speed while the sprint button is held.
@export_range(1.0, 16.0, 0.05, "suffix:m/s") var sprint_speed := 6.5
## How fast the character gets up to speed.
@export_range(1.0, 80.0, 0.5, "suffix:m/s²") var acceleration := 28.0
## How fast the character stops when the stick is let go.
@export_range(1.0, 80.0, 0.5, "suffix:m/s²") var deceleration := 36.0
## How fast the body turns to face where it goes.
@export_range(1.0, 40.0, 0.5, "suffix:rad/s") var turn_speed := 12.0

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
@export_range(10.0, 80.0, 1.0, "suffix:deg") var max_slope := 48.0
## The highest edge the character steps up without jumping.
@export_range(0.0, 0.8, 0.01, "suffix:m") var step_height := 0.32
## How far the character is held to the ground going down a slope or a stair.
@export_range(0.0, 1.0, 0.01, "suffix:m") var snap_length := 0.35

@export_group("Pushing")
## The share of its own speed the character gives a light prop it walks into: 1 moves the prop
## as fast as the character walks, 0 does not move it.
@export_range(0.0, 1.0, 0.01) var push_strength := 0.85
## A prop this heavy gets half of that share; lighter ones get more, heavier ones less.
@export_range(1.0, 500.0, 1.0, "suffix:kg") var push_mass := 40.0

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

@export_group("Body")
## The capsule's radius.
@export_range(0.1, 1.0, 0.01, "suffix:m") var radius := 0.34
## The capsule's height.
@export_range(0.8, 3.0, 0.01, "suffix:m") var height := 1.8


## Gravity pulling up to the jump's top in `jump_rise_time`.
func gravity() -> float:
	return 2.0 * jump_height / (jump_rise_time * jump_rise_time)


## Speed at the moment of take-off for the jump above.
func jump_speed() -> float:
	return 2.0 * jump_height / jump_rise_time
