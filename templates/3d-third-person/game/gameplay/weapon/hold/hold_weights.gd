class_name HoldWeights
extends RefCounted
## What a `TwoHandHold` last wrote to its modifiers (kit #1347): each one's `influence` and
## `active`, and the hands' second, open and together values, so a frame writes only what
## changed and reads nothing back from the modifiers (a property of another object costs more
## than a line in the web build's GDScript).

## What a modifier of the hold is, for its weight: the stance or the right arm, the left arm, the
## right hand's fingers, the left hand's fingers (the hands' last: `>= FINGERS`).
const OTHER := 0
const LEFT_ARM := 1
const FINGERS := 2
const LEFT_FINGERS := 3

var _kinds := PackedByteArray()
var _influences := PackedFloat64Array()
var _actives := PackedByteArray()
var _hands := PackedFloat64Array([NAN, NAN, NAN, NAN])


## Keeps a modifier just made, as the `kind` it is.
func add(modifier: SkeletonModifier3D, kind: int) -> void:
	_kinds.append(kind)
	_influences.append(modifier.influence)
	_actives.append(int(modifier.active))


func clear() -> void:
	_kinds.clear()
	_influences.clear()
	_actives.clear()
	_hands = PackedFloat64Array([NAN, NAN, NAN, NAN])


## Weighs each of `modifiers` (in the order they were added): the arms and the stance by `reach`,
## the hands by `fingers`, none when not `alive`; the left arm and fingers less as an action's
## clip takes the left hand (`freed`, `FreeHand`).
func weigh(
	modifiers: Array[SkeletonModifier3D], alive: bool, reach: float, fingers: float, freed: float
) -> void:
	for index in modifiers.size():
		var modifier := modifiers[index]
		if not is_instance_valid(modifier):
			continue
		var kind := _kinds[index]
		var share := fingers if kind >= FINGERS else reach
		if not alive:
			share = 0.0
		elif kind == LEFT_ARM and freed > 0.0:
			# The clip's own arm has the left hand while an action reaches with it.
			share *= 1.0 - FreeHand.gone(freed)
		elif kind == LEFT_FINGERS and freed > 0.0:
			share *= 1.0 - FreeHand.relaxed(freed)
		if not is_equal_approx(_influences[index], share):
			modifier.influence = share
			_influences[index] = share
		if _actives[index] != int(share > 0.0):
			modifier.active = share > 0.0
			_actives[index] = int(share > 0.0)


## Gives the right hand its trigger finger's way and the left hand its thumb's way, its opening
## and whether its fingers open together.
func hands(
	right: HandPoseModifier,
	left: HandPoseModifier,
	trigger: float,
	thumb: float,
	opened: float,
	together: bool
) -> void:
	if trigger != _hands[0]:
		right.second_weight = trigger
		_hands[0] = trigger
	if thumb != _hands[1]:
		left.second_weight = thumb
		_hands[1] = thumb
	if opened != _hands[2]:
		left.open_weight = opened
		_hands[2] = opened
	if int(together) != int(_hands[3]):
		left.open_together = together
		_hands[3] = float(together)
