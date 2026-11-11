class_name AiPathCheck
extends RefCounted
## Checks a new path as the body would walk it (kit docs/gamedev/bots.md#movement): a ray at knee
## height along each stretch of the first `reach` metres, against what the body collides with.
## The mesh can run through things that are not in its bake (a prop placed later, a locked door);
## only the body's own world says so. One ray a stretch, each taken from the shared `AiBudget`, so
## a check the budget refuses goes on at the next step.
##
## A hit on something that moves (a door that opens for the walker, a platform, a prop the body
## pushes) is not a block: it is out of the way by the time the body gets there, or the stuck
## ladder handles it. A hit on an obstacle with a `Vaultable` is a place to jump (a vault), not a
## block. A link's stretch is never checked: the gap under it is what the link crosses.

## The height (metres above the path) the ray runs at.
const KNEE := 0.5

## Metres of the path checked.
var reach := 12.0
## The physics layers that stop the ray (the body's own mask).
var mask := 1

## The first stretch's index that hit a block, or -1.
var blocked_at := -1
## What blocked it, for the debug overlay.
var blocker := ""
## Where a `Vaultable` lies across the path (INF for nowhere).
var vault_at := Vector3.INF

var _next := 0
var _checked := 0.0


## A new path to check, from its first stretch.
func begin() -> void:
	_next = 1
	_checked = 0.0
	blocked_at = -1
	blocker = ""
	vault_at = Vector3.INF


## True when every stretch within `reach` is checked (or a block was found).
func is_done(path: AiNavPath) -> bool:
	return blocked_at >= 0 or _next >= path.points.size() or _checked >= reach


## Casts rays along the next stretches of `path` while `budget` allows (no budget: all of them),
## for `body`.
func run(path: AiNavPath, body: CollisionObject3D, budget: AiBudget) -> void:
	var space := body.get_world_3d().direct_space_state
	while not is_done(path):
		var from := path.points[_next - 1]
		var to := path.points[_next]
		if path.link_at(_next - 1) == 0:
			if budget != null and not budget.take_ray():
				return
			_cast(space, from, to, body)
		_checked += from.distance_to(to)
		_next += 1


func _cast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, body: Node) -> void:
	var lift := Vector3.UP * KNEE
	var query := PhysicsRayQueryParameters3D.create(from + lift, to + lift, mask)
	query.exclude = [(body as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var collider: Object = hit["collider"]
	if Vaultable.find(collider) != null:
		if not vault_at.is_finite():
			vault_at = hit["position"]
		return
	if collider is Door:
		if (collider as Door).locked:
			blocked_at = _next - 1
			blocker = (collider as Node).name
		return
	if collider is AnimatableBody3D or collider is RigidBody3D or collider is CharacterBody3D:
		return
	blocked_at = _next - 1
	blocker = (collider as Node).name if collider is Node else "?"
