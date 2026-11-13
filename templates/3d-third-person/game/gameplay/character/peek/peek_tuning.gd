@tool
class_name PeekTuning
extends Resource
## Every number of the peek lean around cover (gdstudio #1400), in one resource beside the
## character's `CharacterTuning`: the player scene holds one (`peek_tuning.tres`), and a copy of
## the file gives another character another lean. `CharacterPeek` reads it.
##
## The lean is gameplay, not a pose: the upper body tilts from the hips so the head and the
## shoulders go `side_offset` to the side (never more than `max_angle`), the eye point and the
## camera go with them, the body's shots leave from there and its hits land there. The feet and
## the pelvis stay. A number is read where it is used, every tick, so changing it in the inspector
## or the remote inspector works while the game runs. The defaults come from tactical shooters'
## leans: a quarter to a third of a metre to the side, about a fifth of a second to lean out.

## How the human's controls ask for a lean (`PlayerInput` reads it, unless the player's
## Settings > Controls says otherwise; a command only says "lean left, right or not").
enum InputMode {
	## Leans while `lean_left` or `lean_right` is held.
	HOLD,
	## A press of `lean_left` or `lean_right` leans that way, the next press of it stands up, a press
	## of the other side leans the other way.
	TOGGLE,
}

@export_group("Lean")
## On: the lean commands lean the body. Off: they do nothing.
@export var enabled := true
## How far the head and the shoulders go to the side at a whole lean, standing, in metres (the
## eye point and the camera go as far). Crouched, the bend is shorter, so the same angle goes less.
@export_range(0.0, 0.8, 0.01, "suffix:m") var side_offset := 0.35
## The most the upper body tilts from the hips, in degrees: `side_offset` is reached by this tilt
## or less.
@export_range(0.0, 60.0, 0.5, "suffix:deg") var max_angle := 30.0
## Where the bend starts, as a share of the eye's height above the feet (the hips, about 0.55):
## everything below it stays where it is.
@export_range(0.2, 0.9, 0.01) var pivot_share := 0.55
## Seconds from upright to a whole lean (and back).
@export_range(0.0, 1.0, 0.01, "suffix:s") var lean_time := 0.2

@export_group("Moving")
## On: the body leans crouched as well as standing.
@export var while_crouched := true
## The fastest a leaning body walks, in m/s: a lean is a slow walk at most. A sprint ends the lean.
@export_range(0.0, 6.0, 0.05, "suffix:m/s") var move_speed := 1.2

@export_group("Body")
## The radius of the shape that stands for the leaning shoulders and head: what a shot meets
## outside the upright capsule, and what the wall test sweeps.
@export_range(0.05, 0.5, 0.01, "suffix:m") var shape_radius := 0.2
## Where that shape starts up the bend, as a share of the bend's length from the hips to the eye
## (the shoulders' lower edge); it ends a radius above the eye.
@export_range(0.0, 1.0, 0.01) var shape_start := 0.45
## The room kept between the leaning shape and a wall, in metres: the lean stops this short.
@export_range(0.0, 0.2, 0.005, "suffix:m") var wall_margin := 0.03

@export_group("Input")
## Hold or toggle, when the player's settings say nothing (`PlayerInput`).
@export var input_mode := InputMode.HOLD
