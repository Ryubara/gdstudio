## Films lying down and getting up with the rifle (gdstudio #1581), each from the side, close, and
## then from the game's camera, driven by the actions a player presses: from a held crouch, from
## standing and from a jog, each getting up again. The label and the `RESPONSETOUR` frame lines are
## `responsive_tour.gd`'s. Before #1581 the rifle's hold stayed on the hidden rifle all the way
## down and its chest turn swung the other way in one tick halfway down, the head 0.48 m.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 33 --fps 60 --name rifle_stow`
## with `--scene res://tools/capture/rifle_stow_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends "res://tools/capture/responsive_tour.gd"

## How far the side camera stands from the body, in metres: closer than the base tour's, so the
## head and the hands read.
const SIDE_DISTANCE := 3.2


func _init() -> void:
	sequences = []
	var shown: Array = [
		["Rifle: crouch, then lie down", _from_crouch()],
		["Rifle: lie down from standing", _from_standing()],
		["Rifle: lie down from a jog", _from_jog()],
	]
	for side: bool in [true, false]:
		for entry: Array in shown:
			var title := "%s (%s)" % [entry[0], "side view" if side else "game camera"]
			sequences.append([title, side, entry[1]])


func _ready() -> void:
	_player.tuning = _player.tuning.duplicate()
	_player.tuning.crouch_toggle = false
	_player.loadout.give(load("res://gameplay/weapon/rifle.tres") as WeaponDef, 30)
	super()


func _process(delta: float) -> void:
	super(delta)
	if _sequence < sequences.size() and sequences[_sequence][1]:
		var at := _player.global_position
		var axis := _side_axis if _side_axis != Vector3.ZERO else Vector3.BACK
		_side.global_position = at + axis.cross(Vector3.UP) * SIDE_DISTANCE + Vector3.UP * 0.8
		_side.look_at(at + Vector3(0.0, 0.6, 0.0), Vector3.UP)


func _from_crouch() -> Array:
	return [
		[1.2, ["crouch"]],
		[0.1, ["crouch", "prone"]],
		[1.4, ["crouch"]],
		[0.1, ["prone"]],
		[1.8, []],
	]


func _from_standing() -> Array:
	return [[1.0, []], [0.1, ["prone"]], [1.4, []], [0.1, ["prone"]], [1.8, []]]


func _from_jog() -> Array:
	return [
		[1.4, ["move_forward"]],
		[0.1, ["move_forward", "prone"]],
		[1.4, []],
		[0.1, ["prone"]],
		[1.8, []],
	]
