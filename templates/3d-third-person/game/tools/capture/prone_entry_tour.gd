## Films lying down from a walk, a jog, a sprint and a jog's stop clip, and getting up again, from
## the side (gdstudio #1568), driven by the actions a player presses; the label, the side view and
## the `RESPONSETOUR` frame lines are `responsive_tour.gd`'s. Before #1568 the drawn body went from
## upright to lying in one frame and the to-prone clip lifted it into its pose.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 20 --fps 30 --name prone_entry`
## with `--scene res://tools/capture/prone_entry_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends "res://tools/capture/responsive_tour.gd"


func _init() -> void:
	sequences = [
		["Walk: W, lying down, getting up (side view)", true, _down_and_up(["walk"])],
		["Jog: W, lying down, getting up (side view)", true, _down_and_up([])],
		["Sprint: W, lying down, getting up (side view)", true, _down_and_up(["sprint"])],
		[
			"Jog: W, let go, lying down in the stop (side view)",
			true,
			[
				[1.4, ["move_forward"]],
				[0.25, []],
				[0.1, ["prone"]],
				[1.2, []],
				[0.1, ["prone"]],
				[1.2, []],
			]
		],
	]


func _down_and_up(gait: Array) -> Array:
	return [
		[1.4, ["move_forward"] + gait],
		[0.1, ["move_forward", "prone"] + gait],
		[1.2, []],
		[0.1, ["prone"]],
		[1.2, []],
	]
