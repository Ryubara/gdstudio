@tool
class_name ProneTuning
extends Resource
## Every number of the prone stance and the crawl, in one resource beside the character's
## `CharacterTuning`: the player scene holds one (`prone_tuning.tres`), and a copy of the file
## gives another character another crawl (a heavier soldier, a creature that lies lower).
##
## A number is read where it is used, every tick, so changing it in the inspector or the remote
## inspector works while the game runs; the body sizes (`height`, `radius`, `camera_height`) say
## `changed`, and `Character` fits its capsule again. The defaults come from shipped third-person
## games (the template docs list the sources): a crawl about a quarter to two thirds of a walk,
## half a second to go down and a little longer to get up, slower turns, a steadier aim.

## How the human's controls ask for prone (`PlayerInput` reads it; a command only says "prone or
## not", so an AI or a server never meets these modes).
enum InputMode {
	## A press of the `prone` action lies down, the next one gets up.
	TOGGLE,
	## Prone while the `prone` action is held.
	HOLD,
	## As `TOGGLE`, and holding the crouch button for `crouch_hold_time` lies down too (the pad's
	## usual way); a press of crouch while prone gets up.
	HOLD_CROUCH,
}

@export_group("Crawl")
## Speed of a crawl straight ahead with the stick fully pushed.
@export_range(0.1, 3.0, 0.05, "suffix:m/s") var crawl_speed := 1.0
## The share of `crawl_speed` crawling backwards (the way the body faces, turned around).
@export_range(0.1, 1.0, 0.05) var backward_share := 0.7
## The share of `crawl_speed` crawling sideways.
@export_range(0.1, 1.0, 0.05) var sideways_share := 0.8
## How fast the crawl gets up to speed.
@export_range(0.5, 60.0, 0.5, "suffix:m/s²") var acceleration := 10.0
## How fast the crawl stops when the stick is let go.
@export_range(0.5, 60.0, 0.5, "suffix:m/s²") var deceleration := 12.0
## How fast the lying body turns to the way it crawls (the standing turn is the tuning's
## `turn_speed`); a body on the ground turns slowly.
@export_range(0.5, 40.0, 0.5, "suffix:rad/s") var turn_speed := 3.0
## On: the body crawls while it goes down and gets up. Off: it stops and moves again once down.
@export var move_while_changing := false

@export_group("Getting down and up")
## Seconds from standing (or crouched) to lying.
@export_range(0.0, 3.0, 0.01, "suffix:s") var enter_time := 0.5
## Seconds from lying to crouched; it then stands up over the crouch time when crouch is let go.
@export_range(0.0, 3.0, 0.01, "suffix:s") var exit_time := 0.7
## Seconds in the air (off a ledge) before a lying body gets up to crouch. It lies down again on
## landing while prone is still asked for.
@export_range(0.0, 1.0, 0.01, "suffix:s") var air_time := 0.15

@export_group("Body")
## The capsule's height lying down (it fits under a gap this low). A capsule is at least two
## radii tall.
@export_range(0.3, 1.2, 0.01, "suffix:m") var height := 0.6:
	set(value):
		height = value
		emit_changed()
## The capsule's radius lying down. The capsule stands upright: the length of the lying body
## (head and feet) is not part of it.
@export_range(0.1, 0.6, 0.01, "suffix:m") var radius := 0.28:
	set(value):
		radius = value
		emit_changed()
## Height of the camera's target lying down.
@export_range(0.1, 1.5, 0.01, "suffix:m") var camera_height := 0.55:
	set(value):
		camera_height = value
		emit_changed()

@export_group("Aim")
## On: the character aims lying down. Off: aim and fire do nothing while prone.
@export var aim_allowed := true
## On: the character shoots lying down (it must also be allowed to aim).
@export var fire_allowed := true
## The weapon's spread lying down, as a share of its own (`Weapon.spread`): lying is steadier.
@export_range(0.0, 2.0, 0.05) var spread_share := 0.5
## The share of the crawl speed kept while aiming.
@export_range(0.0, 1.0, 0.05) var aim_move_share := 0.5
## How fast the lying body turns to the view's heading while aiming.
@export_range(0.5, 60.0, 0.5, "suffix:rad/s") var aim_turn_speed := 6.0
## The highest the character looks (and the camera turns) lying down. With the camera's target
## at `camera_height` and the template's 1.7 m camera, 12 degrees keeps the lens about 0.3 m
## over the ground; more puts it down on the floor.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var look_up_limit := 12.0
## The lowest the character looks (and the camera turns) lying down.
@export_range(0.0, 89.0, 0.5, "suffix:deg") var look_down_limit := 40.0
## How far the aim layer turns the upper body lying down to put the weapon on the aim
## (`AimLayer`); the lying body turns to the view while aiming, so this covers the turn's lag.
@export var aim_limits := AimLimits.new()

@export_group("Input")
## How the human's controls ask for prone.
@export var input_mode := InputMode.TOGGLE
## In `HOLD_CROUCH`, how long the crouch button is held before the character lies down.
@export_range(0.1, 2.0, 0.05, "suffix:s") var crouch_hold_time := 0.5
## On: a jump press while prone gets up instead of jumping.
@export var jump_gets_up := true
## On: a sprint press while prone gets up.
@export var sprint_gets_up := true
