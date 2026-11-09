@tool
class_name PlayerTuning
extends Resource
## Every number a developer tunes on the character, in one resource: the player scene holds one
## (`player_tuning.tres`) and the inspector shows it grouped, with ranges and units. Make a copy
## of the file for a second character feel (a heavier one, a floaty one) and point the player at
## it.
##
## A number is read where it is used, every frame, so changing it in the inspector or the remote
## inspector works while the game runs. The few the body copies once (the capsule, the slope and
## the floor snap) say `changed`, and `Player` applies them again.

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

@export_group("Crouch")
## The capsule's height while crouched (the character fits under a ceiling this low).
@export_range(0.7, 1.6, 0.01, "suffix:m") var crouch_height := 1.1:
	set(value):
		crouch_height = value
		emit_changed()
## Speed at a crouch walk with the stick fully pushed.
@export_range(0.3, 4.0, 0.05, "suffix:m/s") var crouch_speed := 1.5
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

@export_group("Aim")
## The share of the walking speed the character keeps while aiming (1 is the full speed).
@export_range(0.1, 1.0, 0.05) var aim_move_scale := 0.6
## How fast the body turns to the camera's heading while aiming.
@export_range(1.0, 60.0, 0.5, "suffix:rad/s") var aim_turn_speed := 18.0
## Seconds the arm takes to come up to aim and to go down again.
@export_range(0.0, 1.0, 0.01, "suffix:s") var aim_pose_time := 0.15
## Seconds that firing keeps the character aiming after the fire button is let go.
@export_range(0.0, 5.0, 0.05, "suffix:s") var aim_hold_time := 0.8

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

@export_group("Ragdoll")
## The whole body's weight, shared out over the bones by `RagdollLayout`.
@export_range(10.0, 300.0, 1.0, "suffix:kg") var ragdoll_mass := 75.0:
	set(value):
		ragdoll_mass = value
		emit_changed()
## How much of the body's velocity at the moment of death the bones start with: 1 keeps the run
## going, 0 drops the body where it stands.
@export_range(0.0, 2.0, 0.05) var ragdoll_carry := 1.0
## Drag on the bones' movement: higher settles the body sooner and floppier.
@export_range(0.0, 5.0, 0.01) var ragdoll_linear_damp := 0.05:
	set(value):
		ragdoll_linear_damp = value
		emit_changed()
## Drag on the bones' turning (the joints' stiffness): 0 is limp and swings long, higher is stiff.
@export_range(0.0, 20.0, 0.05) var ragdoll_angular_damp := 2.0:
	set(value):
		ragdoll_angular_damp = value
		emit_changed()
## Friction of the bones on the floor and the props.
@export_range(0.0, 2.0, 0.01) var ragdoll_friction := 1.0:
	set(value):
		ragdoll_friction = value
		emit_changed()
## How much the bones bounce.
@export_range(0.0, 1.0, 0.01) var ragdoll_bounce := 0.0:
	set(value):
		ragdoll_bounce = value
		emit_changed()
## How far the joints may bend, as a share of what a person's joints do: 0 is rigid, 1 a person's,
## above 1 a rubber doll.
@export_range(0.0, 1.5, 0.01) var ragdoll_joint_freedom := 1.0:
	set(value):
		ragdoll_joint_freedom = value
		emit_changed()
## Seconds the body takes to blend from the ragdoll's pose into the animation when it gets up.
@export_range(0.0, 3.0, 0.01, "suffix:s") var ragdoll_get_up_time := 0.7
## Height above the pelvis of the point the camera follows while the character is dead.
@export_range(0.0, 2.0, 0.01, "suffix:m") var ragdoll_camera_lift := 0.5
## The layers the bones are on. The player's capsule, the doors and the zones look at layer 1, so
## the bones stay out of their way; the bones hit what is on `ragdoll_collision_mask`.
@export_flags_3d_physics var ragdoll_collision_layer := 2:
	set(value):
		ragdoll_collision_layer = value
		emit_changed()
## The layers the bones hit: the world and the props (layer 1). Add the bones' own layer, and the
## limbs hit each other too.
@export_flags_3d_physics var ragdoll_collision_mask := 1:
	set(value):
		ragdoll_collision_mask = value
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
