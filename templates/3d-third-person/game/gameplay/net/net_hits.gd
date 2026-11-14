class_name NetHits
extends RefCounted
## What a HIT event names (`NetEvent.hit`): the kind of thing a shot met and its id, the same on
## the server and on every client, so a client finds its own copy of what the server's shot hit.
## Kept in one file: the world table of networked parts (gdstudio #907) takes the low ids.
##
## Ids: a player is `PLAYER_BASE + slot` (its body carries the meta `net_slot`, set by the server
## and by the client for its own body and every puppet); an AI character is `AI_BASE` + its wire id
## (the meta `net_ai`, set by the server's `AiBroadcast` and on every puppet); a `Target` is
## `TARGET_BASE` + its place
## among the map's targets by node path (both sides load the same map: the world hash); anything
## else is `NetEvent.NO_ID`, and the client finds the surface itself with a short ray.

## What a shot met (the HIT's code).
enum Kind {
	WORLD = 0,  ## The level, or anything with no id: the client looks for it by a ray.
	PLAYER = 1,  ## A player's body (the id names the slot).
	TARGET = 2,  ## A shooting-range `Target` (the id names which).
	PROP = 3,  ## A physics body (a crate): looked for by a ray, as the level.
	AI = 4,  ## An AI character (the id names it: `AI_BASE` + its wire id).
}

## The meta a player's body carries on every peer: its slot.
const SLOT_META := &"net_slot"
## The meta an AI character carries on the server and its puppet on every client: its wire id.
const AI_META := &"net_ai"
## AI ids: `AI_BASE` to `AI_BASE + NetLimits.MAX_AI_ID`, under the targets' and players'.
const AI_BASE := 0x8000
## How many parents up from what a shot met an AI character is looked for (its hit zones are a
## child of it).
const AI_DEPTH := 2
const PLAYER_BASE := 0xFF00
const TARGET_BASE := 0xFE00
## The most targets a map may have that a HIT can name.
const MAX_TARGETS := 0x100
## How far along the normal a client's ray looks for the surface a HIT names, either side, metres:
## a HIT's point is in whole centimetres.
const PROBE := 0.1


## The kind of `collider` for a HIT.
static func kind_of(collider: Object) -> Kind:
	if ai_of(collider) != null:
		return Kind.AI
	if collider is Node and (collider as Node).has_meta(SLOT_META):
		return Kind.PLAYER
	if target_of(collider) != null:
		return Kind.TARGET
	if collider is RigidBody3D:
		return Kind.PROP
	return Kind.WORLD


## The id a HIT on `collider` carries.
static func id_of(collider: Object) -> int:
	var ai := ai_of(collider)
	if ai != null:
		return AI_BASE + int(ai.get_meta(AI_META))
	if collider is Node and (collider as Node).has_meta(SLOT_META):
		return PLAYER_BASE + int((collider as Node).get_meta(SLOT_META))
	var target := target_of(collider)
	if target != null:
		var index := targets_in(target).find(target)
		if index >= 0 and index < MAX_TARGETS:
			return TARGET_BASE + index
	return NetEvent.NO_ID


## The health a HIT on `collider` left: its `Health`'s `wire_value()` (at most 254), or
## `NetEvent.NO_HEALTH`.
static func health_of(collider: Object) -> int:
	var ai := ai_of(collider)
	var health := Health.of(ai if ai != null else collider)
	if health == null:
		return NetEvent.NO_HEALTH
	return mini(health.wire_value(), NetEvent.NO_HEALTH - 1)


## The character carrying `AI_META` that `collider` is, or is part of (its hit zones), or null.
static func ai_of(collider: Object) -> Node3D:
	var node := collider as Node
	for _level in AI_DEPTH + 1:
		if node == null:
			return null
		if node.has_meta(AI_META):
			return node as Node3D
		node = node.get_parent()
	return null


## The AI wire id a HIT's id names, or -1.
static func ai_id_of(id: int) -> int:
	var ai := id - AI_BASE
	return ai if ai >= 0 and ai <= NetLimits.MAX_AI_ID else -1


## The slot a player id names, or -1.
static func slot_of(id: int) -> int:
	var slot := id - PLAYER_BASE
	return slot if slot >= 0 and slot < NetLimits.MAX_PLAYERS else -1


## The `Target` a target id names in the map `near` is in, or null.
static func target_by_id(id: int, near: Node) -> Target:
	var index := id - TARGET_BASE
	if index < 0 or index >= MAX_TARGETS or near == null or not near.is_inside_tree():
		return null
	var all := targets_in(near)
	return all[index] if index < all.size() else null


## The `Target` `collider` is, or is part of, or null.
static func target_of(collider: Object) -> Target:
	var node := collider as Node
	while node != null:
		if node is Target:
			return node
		if node is CollisionObject3D and node != collider:
			return null
		node = node.get_parent()
	return null


## Every `Target` of the map `near` is in (drawn in its viewport), by node path.
static func targets_in(near: Node) -> Array[Target]:
	var found: Array[Target] = []
	if near == null or not near.is_inside_tree():
		return found
	# The map drawn in the same viewport: one process may hold several (a test, a capture).
	var viewport := near.get_viewport()
	for node in near.get_tree().get_nodes_in_group(Target.GROUP):
		var target := node as Target
		if target != null and target.get_viewport() == viewport:
			found.append(target)
	found.sort_custom(
		func(a: Target, b: Target) -> bool: return str(a.get_path()) < str(b.get_path())
	)
	return found


## The thing a HIT at `point` with `normal` met in `space`: a short ray along the normal, both
## sides of the point. `{}` when it finds nothing.
static func probe(space: PhysicsDirectSpaceState3D, point: Vector3, normal: Vector3) -> Dictionary:
	if space == null:
		return {}
	var along := normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	var query := PhysicsRayQueryParameters3D.create(
		point + along * PROBE, point - along * PROBE, PhysicsLayers.SURFACE_MASK
	)
	return space.intersect_ray(query)
