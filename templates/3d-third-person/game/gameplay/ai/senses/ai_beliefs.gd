class_name AiBeliefs
extends RefCounted
## Everything one AI character believes, one `AiBelief` per entity it perceived, keyed by the
## entity's instance id, with the senses' own clock. `AiSenses` writes it; the brain reads it:
## `fire_target()` (only what is believed and seen now), `search_target()` (the freshest memory),
## `believes(node)`, `most_aware()`. A belief older than the profile's `memory_seconds` is
## forgotten (`expire`).
##
## It holds no node but weak references and reads no clock: `clock` moves with the thinks, so a
## test steps it.

## Seconds of the senses' own clock (the sum of the thinks' intervals).
var clock := 0.0
## The beliefs, by the entity's instance id (0: "something", a noise with no known source).
var by_id: Dictionary[int, AiBelief] = {}


## The belief about `node`, or null.
func of(node: Object) -> AiBelief:
	if node == null:
		return null
	return by_id.get(node.get_instance_id(), null)


## True when it holds any belief about `node` (seen, heard, told, felt or remembered).
func knows(node: Object) -> bool:
	return of(node) != null


## True when it believes in `node`: noticed, and the reaction delay passed.
func believes(node: Object) -> bool:
	var belief := of(node)
	return belief != null and belief.believed


## The belief about `node`, made (unaware, at its position) when there is none.
func track(node: Node3D, member: AiFactionMember = null) -> AiBelief:
	var id := node.get_instance_id() if node != null else 0
	var belief: AiBelief = by_id.get(id, null)
	if belief == null:
		belief = AiBelief.new()
		belief.set_entity(node)
		belief.member = member
		belief.time = clock
		if node != null:
			belief.last_position = node.global_position
		by_id[id] = belief
	return belief


## Forgets the entity with instance id `id`.
func forget(id: int) -> void:
	by_id.erase(id)


## Forgets every belief.
func clear() -> void:
	by_id.clear()


## How many beliefs it holds.
func size() -> int:
	return by_id.size()


## Forgets every belief last perceived more than `memory_seconds` ago, or whose entity is gone,
## and returns the forgotten ones (that had been noticed) so the senses can say `entity_lost`.
func expire(memory_seconds: float) -> Array[AiBelief]:
	var gone: Array[AiBelief] = []
	var stale: Array[int] = []
	for id in by_id:
		var belief: AiBelief = by_id[id]
		if clock - belief.time > memory_seconds or (id != 0 and belief.entity() == null):
			stale.append(id)
	for id in stale:
		var belief: AiBelief = by_id[id]
		by_id.erase(id)
		if belief.noticed:
			gone.append(belief)
	return gone


## The belief with the highest awareness, or null.
func most_aware() -> AiBelief:
	var best: AiBelief = null
	for belief: AiBelief in by_id.values():
		if best == null or belief.awareness > best.awareness:
			best = belief
	return best


## The highest awareness of any belief (0 with none): what the situation reads.
func top_awareness() -> float:
	var best := 0.0
	for id in by_id:
		best = maxf(best, by_id[id].awareness)
	return best


## What to shoot at: the nearest to `from` of the beliefs that are believed and seen now, or null.
## A remembered, heard or told entity is never one.
func fire_target(from: Vector3) -> AiBelief:
	var best: AiBelief = null
	var nearest := INF
	for belief: AiBelief in by_id.values():
		if not belief.can_fire_at():
			continue
		var far := from.distance_squared_to(belief.last_position)
		if far < nearest:
			nearest = far
			best = belief
	return best


## Where to search: the freshest belief that is believed but not seen now, or null.
func search_target() -> AiBelief:
	var best: AiBelief = null
	for belief: AiBelief in by_id.values():
		if belief.believed and not belief.seen_now and (best == null or belief.time > best.time):
			best = belief
	return best


## Every belief in one line each, sorted, for logs and the determinism test.
func describe() -> PackedStringArray:
	var lines := PackedStringArray()
	for belief: AiBelief in by_id.values():
		lines.append(belief.describe())
	lines.sort()
	return lines
