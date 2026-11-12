class_name GaitTransitionSet
extends Resource
## The clips `GaitTransitions` plays for each transition (gdstudio #1158), by the gait it leaves
## or reaches (`walk`, `run`, `sprint`: the ground blend space's points). A name is a clip's base:
## the tree looks for `<name>_L` or `<name>_R` first and then for `<name>` itself, and plays
## nothing when neither is in the libraries (the body states then blend as they always did).
##
## The side is the foot for a start (the foot that steps off), a stop and a reversal (the foot
## that plants, picked by the gait's phase), and the way the body turns for a pivot and a turn
## on the spot. A clip is played along its travel curve, or its turn curve, of `clips.json`
## (`GaitClips`) against what the controller really did. The clips themselves are gdstudio #1156
## (starts and stops) and #1157 (the reversal, pivots and turns).

## From standing into each gait.
@export var starts: Dictionary[StringName, StringName] = {
	&"walk": &"gds/Idle_To_Walk",
	&"run": &"gds/Idle_To_Jog",
	&"sprint": &"gds/Idle_To_Sprint",
}
## From each gait to standing.
@export var stops: Dictionary[StringName, StringName] = {
	&"walk": &"gds/Walk_Stop",
	&"run": &"gds/Jog_Stop",
	&"sprint": &"gds/Sprint_Stop",
}
## Turning half round while moving.
@export var reversals: Dictionary[StringName, StringName] = {
	&"run": &"gds/Jog_Turn_180",
	&"sprint": &"gds/Sprint_Turn_180",
}
## Turning a quarter round while moving.
@export var pivots: Dictionary[StringName, StringName] = {
	&"run": &"gds/Jog_Turn_90",
}
## Turning on the spot a quarter round, and half round.
@export var turn_quarter: StringName = &"gds/Turn_In_Place_90"
@export var turn_half: StringName = &"gds/Turn_In_Place_180"


## The clip of `base` for `side` (`"l"` or `"r"`) that `player` holds, or `&""`.
static func pick(player: AnimationPlayer, base: StringName, side: String) -> StringName:
	if player == null or base == &"":
		return &""
	var sided := StringName("%s_%s" % [base, side.to_upper()])
	if side != "" and player.has_animation(sided):
		return sided
	return base if player.has_animation(base) else &""


## The clip `bases[key]` (a gait's) for `side` that `player` holds, or `&""`.
static func pick_in(
	player: AnimationPlayer,
	bases: Dictionary[StringName, StringName],
	key: StringName,
	side: String
) -> StringName:
	return pick(player, bases.get(key, &""), side)
