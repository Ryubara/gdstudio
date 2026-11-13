class_name FreeHand
extends RefCounted
## How far a weapon's hold has let the support hand (the left) go, for an action that reaches with
## it: using a door, a lever or a pad plays the interact clip, whose left arm does the reaching
## (kit #1336). Every hold owns one (`WeaponHold` for a weapon that rides the right hand,
## `TwoHandHold` for a long gun), starts it when its character says `interacted` and reads
## `amount()` each frame, so the rule is the hold's and never a list of weapons: a new weapon that
## uses either hold frees its hand the same way. A game frees the hand for an action of its own
## with the hold's `free_hand(seconds)`.
##
## The amount is one number with two halves, so a hand never goes straight from the weapon to the
## clip's arm. Up to `LET_GO` the hand is still the hold's: its fingers open and it comes off the
## weapon along the hold's own clear way (`off()`); past it the clip's arm takes the opened hand
## (`gone()`). Coming back is the same way backwards. It is cosmetic, worked out on each machine
## from the time since the action began, and never sent; it knows no node, so a test steps it by
## hand.

## The share of the amount over which the hand comes off the weapon; the clip's arm takes it over
## the rest.
const LET_GO := 0.5
## The amount from which the opened fingers go to the clip's own.
const RELAX_FROM := 0.75

## Seconds from the hold to the clip's arm: the fingers open and the hand comes off over the first
## `LET_GO` of it. The interact clip's arm is a hand's length up by then.
var release_time := 0.16
## Seconds from the clip's arm back onto the weapon, ending as the action ends.
var return_time := 0.26

var _length := 0.0
var _left := 0.0


## Frees the hand for an action that lasts `seconds` from now.
func start(seconds: float) -> void:
	_length = maxf(seconds, 0.0)
	_left = _length


## Moves the time on by `delta` seconds.
func step(delta: float) -> void:
	_left = maxf(_left - delta, 0.0)


## Ends the action early: the hand comes back over at most `return_time` from now, the way it
## would at the action's own end, never with a jump (an item's use cut short).
func finish() -> void:
	if _left <= 0.0:
		return
	_left = minf(_left, return_time * amount())


## Puts the hand back on the weapon at once.
func stop() -> void:
	_left = 0.0


## True while the hand is anywhere off its hold.
func is_free() -> bool:
	return _left > 0.0


## How far the hand is from its hold now: 0 on the weapon, 1 with the clip's arm.
func amount() -> float:
	if _left <= 0.0:
		return 0.0
	var leaving := (_length - _left) / maxf(release_time, 0.001)
	var returning := _left / maxf(return_time, 0.001)
	return clampf(minf(leaving, returning), 0.0, 1.0)


## How far along its way off the weapon the hold has the hand at the amount `freed` (0 holding, 1
## clear of it with the fingers open).
static func off(freed: float) -> float:
	return clampf(freed / LET_GO, 0.0, 1.0)


## How far the clip's arm has the hand at the amount `freed` (0 the hold's place, 1 the clip's own
## arm).
static func gone(freed: float) -> float:
	return smoothstep(LET_GO, 1.0, freed)


## How far the hand's fingers are the clip's own at the amount `freed` (0 the hold's opened pose):
## they stay open until the arm is most of the way to the clip's, so none curls beside the weapon.
static func relaxed(freed: float) -> float:
	return smoothstep(RELAX_FROM, 1.0, freed)
