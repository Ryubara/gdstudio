## Films a slide's exit into the run and the carried pistol through a run with turns, starts and
## stops (gdstudio #1577), driven by the actions a player presses; the label, the side view and the
## `RESPONSETOUR` frame lines are `responsive_tour.gd`'s. The game camera follows from behind, as a
## player sees it. Before #1577 getting up out of a slide went from lying to an upright run in
## about a quarter of a second, a slide let go early dropped the body to the floor before it rose,
## and the gun arm swung the pistol from down by the thigh to level forward every stride, up by the
## head at a sprint and out sideways in a turn.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 34 --fps 30 --name pistol_run`
## with `--scene res://tools/capture/pistol_run_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends "res://tools/capture/responsive_tour.gd"


func _init() -> void:
	sequences = [
		["Sprint, slide, run on", false, _slide(0.9)],
		["Sprint, a short slide, run on", false, _slide(0.35)],
		["Sprint, slide let go at once, run on", false, _slide(0.1)],
		["Sprint, slide, run on (side view)", true, _slide(0.9)],
		["Jog with the pistol: turns, a stop, a start", false, _turns([])],
		["Sprint with the pistol: turns, a stop, a start", false, _turns(["sprint"])],
		["Walk with the pistol: turns, a stop, a start", false, _turns(["walk"])],
	]


func _ready() -> void:
	super()
	# Nearer than the responsive tour's view, about as a player sees the character.
	_rig.distance = 3.2
	_rig.pitch = 14.0


func _slide(crouch_seconds: float) -> Array:
	return [
		[1.4, ["move_forward", "sprint"]],
		[crouch_seconds, ["move_forward", "sprint", "crouch"]],
		[1.6, ["move_forward", "sprint"]],
		[0.8, []],
	]


func _turns(gait: Array) -> Array:
	return [
		[1.4, ["move_forward"] + gait],
		[0.8, ["move_right"] + gait],
		[0.9, ["move_back"] + gait],
		[0.7, ["move_left"] + gait],
		[0.6, []],
		[0.8, ["move_forward", "move_left"] + gait],
		[0.9, ["move_back", "move_right"] + gait],
		[0.8, []],
	]
