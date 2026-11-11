@tool
class_name VaultClip
extends Resource
## What a vault clip was keyed on, so the vault can fit it to another obstacle (the animation
## itself is named where it is played, 3D Third Person's `CharacterAnimation.vault_clip`): the
## reference obstacle, the constant speed the body was moved at, where the body's root was when
## the clip starts and when each contact happens. With one of these in `VaultSettings.low_clip` or
## `high_clip` the vault is timed by the clip itself instead of by `plant_at` and `clear_at`:
##
## - the clip starts at the frame whose root is as far from the obstacle as the body is
##   (`start_time()`), so a press close to the wall skips the run-in;
## - the model's root moves forward through the clip's own places at its contact times
##   (`forward_at()`): at the hand plant it is where the clip had it, so the hand lands on the
##   top, and while the hand is planted it moves at the clip's speed, so the hand stays still;
## - the root stays level (the clip carries the rise and the fall in its pelvis) and is lifted by
##   the difference to the reference height while a hand is on the top (`raised()`).
##
## Times are seconds from the clip's start; places are metres along the crossing, 0 at the
## obstacle's front face, negative before it. The kit's
## `docs/engines/godot/third-person/traversal.md` has the method.

@export_group("Keyed on")
## The height of the obstacle the clip was keyed over.
@export_range(0.0, 3.0, 0.01, "suffix:m") var obstacle_height := 0.8
## The depth of that obstacle.
@export_range(0.0, 3.0, 0.01, "suffix:m") var obstacle_depth := 0.4
## The speed the body's root was moved at while the clip was keyed.
@export_range(0.1, 15.0, 0.01, "suffix:m/s") var speed := 4.0
## Where the root is when the clip starts (negative: before the front face).
@export_range(-10.0, 0.0, 0.001, "suffix:m") var root_start := -1.3

@export_group("Contacts")
## When the last foot leaves the ground.
@export_range(0.0, 5.0, 0.0001, "suffix:s") var takeoff := 0.1667
## When the hand lands on the top.
@export_range(0.0, 5.0, 0.0001, "suffix:s") var hand_plant := 0.25
## When the fingers of the last hand leave the top (the push).
@export_range(0.0, 5.0, 0.0001, "suffix:s") var push_off := 0.4167
## When the landing foot is down: the vault ends here.
@export_range(0.0, 5.0, 0.0001, "suffix:s") var land := 0.7917
## The least time before the hand plant a vault starts at, however close the body is: the time
## the body has to get from where it stands to where the clip plants the hand from.
@export_range(0.0, 1.0, 0.001, "suffix:s") var lead := 0.125

## For an obstacle lower than the clip's own: when the root may start to come down to it, and
## when it is down. The feet must be off the ground and rising by then, or the lowered body puts
## them under the floor; a hand reaches the top only at the second time. Both 0: as for a higher
## obstacle (from `lead` before the hand plant to the plant).
@export_range(0.0, 5.0, 0.0001, "suffix:s") var lower_from := 0.0
@export_range(0.0, 5.0, 0.0001, "suffix:s") var lower_by := 0.0

@export_group("Hands")
## The hand bones that land on the top, and for each where its wrist sits: x metres to the
## body's left of its line, y metres above the top, z metres in from the front edge.
@export var planted_hands: Dictionary[StringName, Vector3] = {}
## When each of those hands' wrists leaves the top (the same keys).
@export var hand_release: Dictionary[StringName, float] = {}
## On: both hands are open on the obstacle, so a held weapon is put away for the vault.
@export var puts_weapon_away := false


## Where the clip itself has the root at `time`.
func keyed_forward(time: float) -> float:
	return root_start + speed * time


## The clip time a vault starts at for a body `near` metres before the front face: the frame
## whose root is that far away, never later than `lead` before the hand plant (and never after
## the takeoff).
func start_time(near: float) -> float:
	var latest := maxf(minf(takeoff, hand_plant - lead), 0.0)
	return clampf((-near - root_start) / speed, 0.0, latest)


## Where the root is at clip time `time`, for a vault that started at `start` (a clip time) with
## the body `near` before the face and lands `landing` past it: from the body's place to the
## clip's own at the hand plant, at the clip's speed while a hand is on the top, then to the
## landing.
func forward_at(time: float, start: float, near: float, landing: float) -> float:
	var keys := _keys(start, near, landing)
	for index in range(1, keys.size()):
		if time <= keys[index].x or index == keys.size() - 1:
			var span := maxf(keys[index].x - keys[index - 1].x, 0.000001)
			var part := clampf((time - keys[index - 1].x) / span, 0.0, 1.0)
			return lerpf(keys[index - 1].y, keys[index].y, part)
	return landing


## The first clip time at which the root is `forward` along the crossing (the inverse of
## `forward_at()`); `start` when it is there from the beginning, `land` when it never is.
func time_at(forward: float, start: float, near: float, landing: float) -> float:
	var keys := _keys(start, near, landing)
	if forward <= keys[0].y:
		return start
	for index in range(1, keys.size()):
		var from := keys[index - 1]
		var to := keys[index]
		if forward <= to.y and to.y > from.y:
			return lerpf(from.x, to.x, clampf((forward - from.y) / (to.y - from.y), 0.0, 1.0))
	return land


## How much of the difference to another height the root is lifted by at `time` (0 to 1): none
## on the ground, all of it from the hand plant to the push, none again at the landing. With
## `lowered` (an obstacle lower than the clip's own) it comes down between `lower_from` and
## `lower_by` instead, when those are set.
func raised(time: float, start: float, lowered: bool = false) -> float:
	var from := maxf(minf(takeoff, hand_plant - lead), minf(start, hand_plant - 0.001))
	var by := hand_plant
	if lowered and lower_by > 0.0:
		from = maxf(lower_from, minf(start, lower_by - 0.001))
		by = lower_by
	return smoothstep(from, by, time) * (1.0 - smoothstep(push_off, land, time))


## When a hand is on the top of an obstacle `height` metres high: the hand plant, or `lower_by`
## for an obstacle lower than the clip's own.
func planted_from(height: float) -> float:
	return maxf(hand_plant, lower_by) if height < obstacle_height else hand_plant


## How far the fall to a landing lower or higher than the start has come at `time` (0 to 1).
func fallen(time: float) -> float:
	var part := clampf((time - push_off) / maxf(land - push_off, 0.000001), 0.0, 1.0)
	return part * part


## How far past the far face the clip itself lands the root.
func keyed_landing() -> float:
	return keyed_forward(land) - obstacle_depth


# The (time, forward) keys the root goes through.
func _keys(start: float, near: float, landing: float) -> PackedVector2Array:
	var keys := PackedVector2Array([Vector2(start, -near)])
	if hand_plant > start:
		keys.append(Vector2(hand_plant, keyed_forward(hand_plant)))
	if push_off > maxf(start, hand_plant):
		keys.append(Vector2(push_off, keyed_forward(push_off)))
	keys.append(Vector2(maxf(land, start + 0.001), landing))
	return keys
