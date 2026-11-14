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


## The stop of `base` that begins nearest `phase` (0 to 1) of `gait`'s cycle, among the one on each
## foot's strike (`<base>_L`, `<base>_R`, picked by `side` when the gait has no record) and the
## entries between them that `player` holds, named by the gait's frame they begin on
## (`<base>_05`, gdstudio #1525). Each begins on the gait's own pose at its frame
## (`joins.first_frame`), so a body let go between two strikes is drawn at most half the spacing
## from it, not the half cycle to the next strike.
static func pick_entry(
	player: AnimationPlayer, base: StringName, side: String, gait: StringName, phase: float
) -> StringName:
	var picked := pick(player, base, side)
	var frames := roundi(GaitClips.seconds(gait) * GaitClips.FPS)
	if picked == &"" or frames <= 0:
		return picked
	var at := fposmod(phase, 1.0) * frames
	var nearest := INF
	for name: StringName in [StringName("%s_L" % base), StringName("%s_R" % base)]:
		var joins: Dictionary = GaitClips.record(name).get("joins", {})
		if player.has_animation(name) and joins.has("first_frame"):
			var gap := _frames_apart(float(joins.first_frame), at, frames)
			if gap < nearest:
				nearest = gap
				picked = name
	for frame in frames:
		var entry := StringName("%s_%02d" % [base, frame])
		var gap := _frames_apart(float(frame), at, frames)
		if gap < nearest and player.has_animation(entry):
			nearest = gap
			picked = entry
	return picked


static func _frames_apart(a: float, b: float, frames: int) -> float:
	var apart := absf(a - b)
	return minf(apart, frames - apart)


## The clip `bases[key]` (a gait's) for `side` that `player` holds, or `&""`.
static func pick_in(
	player: AnimationPlayer,
	bases: Dictionary[StringName, StringName],
	key: StringName,
	side: String
) -> StringName:
	return pick(player, bases.get(key, &""), side)
