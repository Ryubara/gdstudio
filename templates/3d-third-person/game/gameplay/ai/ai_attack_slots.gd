class_name AiAttackSlots
extends RefCounted
## The attack slots of a fight (kit #1203): at most `per_target` characters engage one target at
## once and at most `total` engage at all, so a crowd that sees a player does not all aim and fire
## (a fighting body costs two to three times a calm one: the AI behaviour page's cost follow-up).
## The `AiDirector` holds one and sets its counts from the inspector each tick; a fighting task
## (`AiAttack`, `AiTakeCover`'s peeks) asks for a slot each think before it fires, and a character
## without one holds and waits.
##
## A slot is freed by its holder (the task ends, is suspended or dropped, or loses sight of its
## target), when the holder leaves the director, and as a fallback when the holder is dead, gone,
## or has not asked again for `lease_ticks` ticks. Only the authority runs it (the AI runs on the
## server); nothing about it goes over the network.

## The most characters that engage one target at once.
var per_target := 6
## The most characters that engage at once, all targets together.
var total := 12
## Ticks a slot is kept without its holder asking again.
var lease_ticks := 180

# Holder's instance id -> its `Hold`.
var _holds: Dictionary = {}


## One character's slot.
class Hold:
	var holder: WeakRef
	var target_id := 0
	var tick := 0


## Asks for a slot on `target` for `holder` at `tick`: true when it holds one (it keeps the one it
## had and its lease starts again), false when the target's or the fight's count is reached. A
## holder that turns to another target gives up its old slot first.
func claim(holder: Node, target: Node, tick: int) -> bool:
	if holder == null or target == null:
		return false
	var key := holder.get_instance_id()
	var target_id := target.get_instance_id()
	var hold: Hold = _holds.get(key)
	if hold != null:
		if hold.target_id == target_id:
			hold.tick = tick
			return true
		_holds.erase(key)
	if not _room_for(target_id):
		_prune(tick)
		if not _room_for(target_id):
			return false
	hold = Hold.new()
	hold.holder = weakref(holder)
	hold.target_id = target_id
	hold.tick = tick
	_holds[key] = hold
	return true


## Gives up `holder`'s slot (nothing when it has none).
func release(holder: Node) -> void:
	if holder != null:
		_holds.erase(holder.get_instance_id())


## True when `holder` holds a slot.
func holds(holder: Node) -> bool:
	return holder != null and _holds.has(holder.get_instance_id())


## Slots held now, on `target` (or all of them for null).
func count(target: Node = null) -> int:
	if target == null:
		return _holds.size()
	return _count_on(target.get_instance_id())


## Frees every slot.
func clear() -> void:
	_holds.clear()


func _room_for(target_id: int) -> bool:
	return _holds.size() < total and _count_on(target_id) < per_target


func _count_on(target_id: int) -> int:
	var found := 0
	for hold: Hold in _holds.values():
		if hold.target_id == target_id:
			found += 1
	return found


# Frees the slots of holders that are gone or dead, or that have not asked for `lease_ticks`.
func _prune(tick: int) -> void:
	for key: int in _holds.keys():
		var hold: Hold = _holds[key]
		var holder := hold.holder.get_ref() as Node
		var dead := holder is Character and (holder as Character).is_dead()
		if holder == null or dead or tick - hold.tick > lease_ticks:
			_holds.erase(key)
