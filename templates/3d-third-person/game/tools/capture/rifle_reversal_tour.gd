## Films the rifle carried through a jog's and a sprint's reversals (gdstudio #1587), driven by the
## actions a player presses: W then S, and W+A then S+D, from the game camera behind the body and
## from the side; the label, the side view and the `RESPONSETOUR` frame lines are
## `responsive_tour.gd`'s. Before #1587 the gun stayed on the capsule's facing while a reversal's
## look turned the drawn body round, so the rifle swung from behind the right shoulder across the
## chest within a frame or two and the hands turned 13 to 26 degrees an update.
##
## Record it with Movie Maker through the kit (the frames land in the scratch folder):
## `gds capture frames --project game --seconds 33 --fps 30 --name rifle_reversal`
## with `--scene res://tools/capture/rifle_reversal_tour.tscn`.
## It lives in tools/, which the export leaves out, and nothing in the game refers to it.
extends "res://tools/capture/responsive_tour.gd"

const RIFLE := "res://gameplay/weapon/rifle.tres"


func _init() -> void:
	sequences = [
		["Jog with the rifle: W, then S", false, _reversal(["move_forward"], ["move_back"], [])],
		[
			"Sprint with the rifle: W, then S",
			false,
			_reversal(["move_forward"], ["move_back"], ["sprint"])
		],
		[
			"Jog with the rifle: W+A, then S+D",
			false,
			_reversal(["move_forward", "move_left"], ["move_back", "move_right"], [])
		],
		[
			"Jog with the rifle: W, then S (side view)",
			true,
			_reversal(["move_forward"], ["move_back"], [])
		],
		[
			"Sprint with the rifle: W, then S (side view)",
			true,
			_reversal(["move_forward"], ["move_back"], ["sprint"])
		],
	]


func _ready() -> void:
	var loadout := ($Main/PlayerRig/Player as Player).loadout
	loadout.give(load(RIFLE) as WeaponDef, 60)
	for slot in loadout.slots.size():
		if loadout.slots[slot] != null and loadout.slots[slot].resource_path == RIFLE:
			loadout.select(slot)
	super()
	# Nearer than the responsive tour's view, about as a player sees the character.
	_rig.distance = 3.2
	_rig.pitch = 14.0


func _reversal(first: Array, then: Array, gait: Array) -> Array:
	return [
		[1.0, []],
		[1.6, first + gait],
		[1.4, then + gait],
		[0.8, []],
	]
