class_name HoldWeights
extends RefCounted
## What a `TwoHandHold` last wrote to its modifiers (kit #1347): each one's `influence` and
## `active`, and the hands' second, open and together values, so a frame writes only what
## changed and reads nothing back from the modifiers (a property of another object costs more
## than a line in the web build's GDScript).

## What a modifier of the hold is, for its weight: the stance, the right arm, the left arm, the
## right hand's fingers, the left hand's fingers (the arms `ARM` and `LEFT_ARM`, the hands last:
## `>= FINGERS`).
const OTHER := 0
const ARM := 1
const LEFT_ARM := 2
const FINGERS := 3
const LEFT_FINGERS := 4

var _kinds := PackedByteArray()
var _influences := PackedFloat64Array()
var _actives := PackedByteArray()
var _hands := PackedFloat64Array([NAN, NAN, NAN, NAN, NAN])
var _elbow := NAN


## Keeps a modifier just made, as the `kind` it is.
func add(modifier: SkeletonModifier3D, kind: int) -> void:
	_kinds.append(kind)
	_influences.append(modifier.influence)
	_actives.append(int(modifier.active))
	_elbow = NAN


func clear() -> void:
	_kinds.clear()
	_influences.clear()
	_actives.clear()
	_hands = PackedFloat64Array([NAN, NAN, NAN, NAN, NAN])
	_elbow = NAN


## Weighs each of `modifiers` (in the order they were added): the arms and the stance by `reach`,
## the hands by `fingers`, none when not `alive`; the left arm and fingers less as an action's
## clip takes the left hand (`freed`, `FreeHand`); each arm keeps its clip's elbow by
## `keep_elbow` (`HoldArm.keep_elbow`: a melee blow's clip has the elbows, `HoldBlow`); with
## `put_away` (the gun hidden for the action, a high vault: gdstudio #1409) both arms go to it.
func weigh(
	modifiers: Array[SkeletonModifier3D],
	alive: bool,
	reach: float,
	fingers: float,
	freed: float,
	keep_elbow := 0.0,
	put_away := false
) -> void:
	var elbow := keep_elbow != _elbow
	_elbow = keep_elbow
	for index in modifiers.size():
		var modifier := modifiers[index]
		if not is_instance_valid(modifier):
			continue
		var kind := _kinds[index]
		if elbow and (kind == ARM or kind == LEFT_ARM):
			(modifier as HoldArm).keep_elbow = keep_elbow
		var share := fingers if kind >= FINGERS else reach
		if not alive:
			share = 0.0
		elif (kind == LEFT_ARM or put_away and kind == ARM) and freed > 0.0:
			# The clip's own arm has the left hand while an action reaches with it, and both
			# while the gun is put away for it.
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
## whether its fingers open together and its hook on the charging handle (`charge`, the left
## hand's third pose: `ChargePull`).
func hands(
	right: HandPoseModifier,
	left: HandPoseModifier,
	trigger: float,
	thumb: float,
	opened: float,
	together: bool,
	charge := 0.0
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
	if charge != _hands[4]:
		left.third_weight = charge
		_hands[4] = charge
