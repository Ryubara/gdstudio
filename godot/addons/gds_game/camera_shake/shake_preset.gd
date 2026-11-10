@tool
class_name ShakePreset
extends Resource
## One kind of camera shake as a resource: how hard, how long, how fast and which way it turns the
## view. `CameraShake.shake(preset, at)` plays it once from anywhere (a shot, a landing, a blast);
## `CameraShake.hold_everywhere(source, preset)` keeps it going (a sprint, an engine). Save one as
## a `.tres` of the game's own (3D Blank's `core/camera_shake/presets/` has a few), tune it in
## the inspector and drop it on any export that takes a `ShakePreset`.
##
## The turn at any moment is `max_rotation * level ^ exponent * wave`, where `level` is the
## trauma of a one-shot (it drains by itself) or the blend of a held source, 0 to 1. The square
## (`exponent` 2) makes a light hit barely felt and hits that come close together add up.

## How the shake moves between its peaks.
enum Wave {
	NOISE,  ## Smooth random: an impact, a blast, a landing. Seeded, the same in tests and captures.
	SINE,  ## A steady rhythm: pitch at `frequency`, yaw and roll at half of it. A gait, an engine.
}

@export_group("One shot")
## The trauma one play adds, 0 to 1. Plays of the same preset stack up to 1.
@export_range(0.0, 1.0, 0.01) var trauma := 0.5
## Seconds a trauma of 1 takes to die away (a smaller trauma takes proportionally less).
@export_range(0.05, 10.0, 0.01, "or_greater", "suffix:s") var duration := 0.4

@export_group("Motion")
## The wave the shake follows.
@export var wave := Wave.NOISE
## Wiggles a second (noise) or cycles a second (sine).
@export_range(0.1, 60.0, 0.1, "suffix:Hz") var frequency := 12.0
## The turn of the view at full strength, in degrees: x pitch, y yaw, z roll.
@export_custom(PROPERTY_HINT_RANGE, "0,10,0.01,suffix:deg")
var max_rotation := Vector3(1.0, 0.8, 0.4)
## The slide of the view at full strength, in metres: x sideways, y up and down. It moves the
## picture without moving the camera, so nothing slides into a wall.
@export_custom(PROPERTY_HINT_RANGE, "0,1,0.001,suffix:m") var max_offset := Vector2.ZERO
## The curve of strength: 1 follows the level, 2 (the classic) keeps a light hit light.
@export_range(1.0, 4.0, 0.1) var exponent := 2.0

@export_group("Held")
## How fast a held source builds up and dies down (1 is a second, 4 a quarter of one).
@export_range(0.5, 20.0, 0.1, "suffix:/s") var blend_speed := 4.0

@export_group("Distance")
## A play at a world position is felt this far from the camera and fades to nothing at the edge.
## Zero is felt everywhere (a hit on the player's own body).
@export_range(0.0, 500.0, 0.5, "or_greater", "suffix:m") var radius := 0.0


## The share of the shake felt `distance` metres from where it happened: 1 at the spot, 0 at
## `radius` and beyond, smooth between. 1 everywhere when `radius` is zero.
func falloff(distance: float) -> float:
	if radius <= 0.0:
		return 1.0
	return 1.0 - smoothstep(0.0, radius, distance)
