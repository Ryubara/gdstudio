## Films every stance change the maintainer's recordings showed (gdstudio #1576), each from the side
## and then from the game's camera, driven by the actions a player presses: getting up from lying,
## getting up through a held crouch, lying down from a held crouch, lying down from a sprint and
## getting up again, and a crouch and a stand at rest. The label, the side view and the
## `RESPONSETOUR` frame lines are `responsive_tour.gd`'s. Before #1576 getting up ended on the
## crouch idle and rose to standing in 0.1 s, and a crouch or a stand at rest dropped or rose in six
## ticks.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 46 --fps 30 --name stance`
## with `--scene res://tools/capture/stance_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends "res://tools/capture/responsive_tour.gd"


func _init() -> void:
	sequences = []
	var shown: Array = [
		["Prone to stand", _prone_to_stand()],
		["Prone to crouch to stand", _prone_to_crouch_to_stand()],
		["Crouch to prone", _crouch_to_prone()],
		["Sprint to prone, and up", _sprint_to_prone()],
		["Crouch and stand at rest", [[0.6, []], [1.4, ["crouch"]], [1.6, []]]],
	]
	for side: bool in [true, false]:
		for entry: Array in shown:
			var title := "%s (%s)" % [entry[0], "side view" if side else "game camera"]
			sequences.append([title, side, entry[1]])


func _prone_to_stand() -> Array:
	return [[0.4, []], [0.1, ["prone"]], [1.4, []], [0.1, ["prone"]], [1.8, []]]


func _prone_to_crouch_to_stand() -> Array:
	return [
		[0.4, []],
		[0.1, ["prone"]],
		[1.3, ["crouch"]],
		[0.1, ["crouch", "prone"]],
		[1.3, ["crouch"]],
		[1.6, []],
	]


func _crouch_to_prone() -> Array:
	return [
		[1.2, ["crouch"]],
		[0.1, ["crouch", "prone"]],
		[1.4, ["crouch"]],
		[0.1, ["prone"]],
		[1.8, []],
	]


func _sprint_to_prone() -> Array:
	return [
		[1.6, ["move_forward", "sprint"]],
		[0.1, ["move_forward", "sprint", "prone"]],
		[1.4, []],
		[0.1, ["prone"]],
		[1.8, []],
	]
