@tool
class_name SlideTuning
extends Resource
## Every number of the slide, in one resource beside the character's `CharacterTuning`: the player
## scene holds one (`slide_tuning.tres`), and a copy of the file gives another character another
## slide (a longer one, one with no boost). `CharacterSlide` reads it.
##
## A number is read where it is used, every tick, so changing it in the inspector or the remote
## inspector works while the game runs; the body sizes (`height`, `camera_height`) say `changed`,
## and `Character` fits its capsule again. The defaults come from shipped games' slides (the kit's
## `docs/engines/godot/third-person/character.md#slide` lists the sources): an entry at about
## three quarters of a sprint, a small boost with a cooldown, about a second on the flat, faster
## downhill, a slide jump that keeps the speed.

@export_group("Start")
## On: crouch pressed while running fast starts a slide (`CharacterSlide`). Off: crouch only
## crouches.
@export var enabled := true
## The least ground speed a slide starts from: above a run, so a sprint slides and a jog
## crouches. Titanfall 2 needs 77 percent of its sprint speed.
@export_range(0.0, 16.0, 0.05, "suffix:m/s") var min_speed := 5.0
## On: only a body that holds sprint slides. Off: any body at `min_speed` does (a fast run
## of a game with a higher `run_speed`, or a bot that sends no sprint).
@export var needs_sprint := false
## On: a slide may start while aiming (aiming caps the speed, so it rarely reaches
## `min_speed`).
@export var while_aiming := false
## On: crouch held when the body lands at speed starts a slide (a slide out of a jump).
@export var on_landing := true
## On: the slide lasts while crouch is held and letting go ends it. Off: a press slides until
## the slide slows down or times out (with the crouch toggle on, the press itself is held).
@export var hold_to_continue := true
## Seconds before another slide can start after one ends.
@export_range(0.0, 5.0, 0.05, "suffix:s") var cooldown := 0.3

@export_group("Boost")
## Speed added the moment a slide starts.
@export_range(0.0, 8.0, 0.05, "suffix:m/s") var boost := 1.5
## The boost adds speed only up to this; a body already faster keeps its speed.
@export_range(0.0, 20.0, 0.05, "suffix:m/s") var boost_cap := 8.5
## After a boosted slide, slides get no boost for this long (they still slide), so chaining
## slides is not faster than sprinting.
@export_range(0.0, 10.0, 0.05, "suffix:s") var boost_cooldown := 2.0

@export_group("Friction and end")
## The steady part of the slide's friction: speed lost every second whatever the speed.
@export_range(0.0, 30.0, 0.05, "suffix:m/s²") var friction := 3.5
## The part of the friction that grows with speed: this share of the speed is lost every second,
## so a fast slide slows sooner than a slow one.
@export_range(0.0, 3.0, 0.01, "suffix:/s") var drag := 0.3
## The fastest a slide goes, downhill included.
@export_range(1.0, 30.0, 0.05, "suffix:m/s") var max_speed := 11.0
## The slide ends when its speed drops below this (after friction, a slope or a wall).
@export_range(0.0, 10.0, 0.05, "suffix:m/s") var exit_speed := 3.0
## The longest a slide lasts on flat ground or uphill, seconds; 0 lets friction alone end it.
@export_range(0.0, 10.0, 0.05, "suffix:s") var max_time := 1.5

@export_group("Slopes")
## On: a slide down a slope steeper than `flat_angle` has no time limit (it ends when it
## slows down or reaches the bottom).
@export var downhill_unlimited := true
## How hard a slope pulls the slide: gravity along the floor, so a slide speeds up down a slope
## and slows up one.
@export_range(0.0, 40.0, 0.1, "suffix:m/s²") var gravity := 9.8
## The share of the friction a slide feels going down a slope, so a slope steep enough speeds it
## up (Apex Legends and Fortnite slides speed up downhill and run on to the bottom).
@export_range(0.0, 1.0, 0.01) var downhill_friction := 0.2
## A floor flatter than this counts as flat for the slide (no pull, the time limit holds).
@export_range(0.0, 45.0, 0.5, "suffix:deg") var flat_angle := 4.0

@export_group("Steering")
## How fast the stick turns a slide's direction: a slide is hard to steer.
@export_range(0.0, 20.0, 0.05, "suffix:rad/s") var turn_rate := 1.2

@export_group("Body and camera")
## The capsule's height while sliding (a gap this low is slid under).
@export_range(0.7, 1.6, 0.01, "suffix:m") var height := 0.9:
	set(value):
		height = value
		emit_changed()
## Seconds to drop into the slide and to rise out of it.
@export_range(0.0, 1.0, 0.01, "suffix:s") var drop_time := 0.12
## Height of the camera's target while sliding.
@export_range(0.3, 2.0, 0.01, "suffix:m") var camera_height := 0.75:
	set(value):
		camera_height = value
		emit_changed()

@export_group("Shooting")
## On: aim and fire work while sliding (the body turns to the view). Off: the slide holds them.
@export var can_shoot := true

@export_group("Slide jump")
## On: jump works out of a slide and keeps its speed in the air.
@export var jump := true
## A jump out of a slide rises this share of a standing jump's height.
@export_range(0.1, 1.5, 0.01) var jump_height_scale := 0.85
## Speed added to a jump out of a slide.
@export_range(0.0, 8.0, 0.05, "suffix:m/s") var jump_boost := 0.0
## A jump out of a slide carries at most this ground speed.
@export_range(1.0, 30.0, 0.05, "suffix:m/s") var jump_max_speed := 9.0
## How fast the carried speed of a slide jump fades in the air.
@export_range(0.0, 30.0, 0.05, "suffix:m/s²") var jump_air_drag := 1.0
