## Films speeding up into a sprint (gdstudio #1578), driven by the actions a player presses: W at
## a jog, then Shift held; and W crouched, then crouch let go as Shift is pressed; each from the
## game's camera and from the side. Where the jog alone meets the sprint alone (5.2 m/s) the legs
## were swapped from one gait to the other in a tick before the fix, a foot jumping up to 0.33 m;
## the ground blend now takes `GaitSettings.gait_change_time` over it. The label and the
## `RESPONSETOUR` lines are `responsive_tour.gd`'s.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 16 --fps 30 --name sprint_seam`
## with `--scene res://tools/capture/sprint_seam_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends "res://tools/capture/responsive_tour.gd"


func _init() -> void:
	var jog: Array = [
		[1.5, ["move_forward"]],
		[1.3, ["move_forward", "sprint"]],
		[0.6, []],
	]
	var crouched: Array = [
		[1.5, ["move_forward", "crouch"]],
		[1.3, ["move_forward", "sprint"]],
		[0.6, []],
	]
	sequences = [
		["Jog: W, then Shift", false, jog],
		["Jog: W, then Shift (side view)", true, jog],
		["Crouch walk: W+C, then C let go and Shift", false, crouched],
		["Crouch walk: W+C, then C let go and Shift (side view)", true, crouched],
	]
