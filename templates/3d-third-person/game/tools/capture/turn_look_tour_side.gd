## `turn_look_tour.gd` with every move turned a quarter to the right: the body runs across the
## game's camera, so the plant and the hips coming round are seen side on (gdstudio #1574).
## Record it as the tour says, with `--scene res://tools/capture/turn_look_tour_side.tscn`.
extends "res://tools/capture/turn_look_tour.gd"


func _init() -> void:
	side_view = true
