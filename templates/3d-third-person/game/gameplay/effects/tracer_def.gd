@tool
class_name TracerDef
extends Resource
## What a hitscan shot's tracer looks like: a thin glowing streak from the muzzle to where the ray
## hit (or to its reach). A `WeaponDef` names one in its `tracer` (empty: no tracer), and the
## level's `TracerPool` draws it. Cosmetic: each screen draws it from the shot it already has, and
## nothing about it is ever sent.
##
## With a `speed` the streak runs from the muzzle to the end, `length` long, then fades over
## `fade_time`; with no speed the whole line shows at once and fades. Every number is read when the
## shot is fired, so a change while the game runs shows in the next shot.

@export_group("Look")
## The streak's colour. Added to what is behind it, so it never darkens the scene.
@export var color := Color(1.0, 0.82, 0.48)
## How bright the streak is: the colour is multiplied by this.
@export_range(0.0, 8.0, 0.05, "or_greater") var energy := 1.6
## How wide the streak is, turned to face the camera.
@export_range(0.002, 0.5, 0.001, "or_greater", "suffix:m") var width := 0.025

@export_group("Motion")
## How fast the streak runs from the muzzle to the end. Zero: the whole line shows at once.
@export_range(0.0, 2000.0, 1.0, "or_greater", "suffix:m/s") var speed := 320.0
## How long the running streak is (ignored with no `speed`).
@export_range(0.05, 50.0, 0.05, "or_greater", "suffix:m") var length := 3.0
## How long the streak takes to fade once its head has reached the end.
@export_range(0.0, 2.0, 0.005, "suffix:s") var fade_time := 0.06
## How far from the muzzle the streak starts (the flash covers the first few centimetres).
@export_range(0.0, 2.0, 0.01, "suffix:m") var start_offset := 0.1


## Seconds the head of a streak takes to run `distance` metres (0 with no `speed`).
func travel_time(distance: float) -> float:
	return distance / speed if speed > 0.0 else 0.0


## Seconds a streak over `distance` metres shows, its run and its fade.
func lifetime(distance: float) -> float:
	return travel_time(distance) + fade_time
